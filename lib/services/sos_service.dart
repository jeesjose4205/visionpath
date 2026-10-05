import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/emergency_contact.dart';
import '../models/sos_session.dart';
import 'emergency_contact_service.dart';
import 'navigation_service.dart';
import 'settings_service.dart';
import 'sos_platform.dart';
import 'vibration_service.dart';
import 'voice_service.dart';

/// Owns the emergency procedure for the whole app.
///
/// This is the single place SOS lives. The screen only renders [session] and
/// calls [activate] / [reset]; it never calls, texts or plays a tone itself.
/// That is what lets the alert keep sounding after the user leaves the SOS
/// screen, and what makes [reset] able to guarantee nothing is left running.
///
/// Deliberate behaviours:
///
///  * **The alert starts before the call.** Audible feedback is the one channel
///    that needs no permission and no user action, so it goes first.
///  * **The call is never gated on GPS.** Location resolution runs
///    concurrently; a slow or absent fix must not delay reaching a person.
///  * **One session, one call, one message, one tone loop.** [activate] is
///    idempotent, so a double activation cannot double anything.
///  * **Nothing claims success it did not get.** Every step is derived from the
///    platform's own report, so the UI cannot say "sent" or "calling" when it
///    was not.
class SosService extends ChangeNotifier {
  SosService({
    SosPlatform platform = const SosPlatform(),
    VoiceService? voice,
    VibrationService? vibration,
    EmergencyContactService? contacts,
    NavigationService? navigation,
    SettingsService? settings,
  })  : _platform = platform,
        _voice = voice ?? VoiceService(),
        _vibration = vibration ?? VibrationService.instance,
        _contacts = contacts ?? EmergencyContactService.instance,
        _navigation = navigation,
        _settings = settings ?? SettingsService.instance;

  final SosPlatform _platform;
  final VoiceService _voice;
  final VibrationService _vibration;
  final EmergencyContactService _contacts;
  final SettingsService _settings;

  /// Set by the app once navigation exists, so muting one screen's reader
  /// cannot be undone by another screen's service instance.
  NavigationService? _navigation;

  /// Attaches the app's navigation service.
  ///
  /// Called from `VisionPathApp` after navigation is constructed. Late
  /// attachment is intentional: SOS may be created before navigation is built,
  /// and a missing navigation service must not break an emergency.
  void attachNavigation(NavigationService? navigation) {
    _navigation = navigation;
  }

  SosSession _session = const SosSession(
    state: SosState.inactive,
    contactName: '',
    contactPhone: '',
    callStep: SosStep.pending,
    locationStep: SosStep.pending,
    smsStep: SosStep.pending,
    alerting: false,
  );

  /// The app-wide singleton. Lives for the whole process so the alert is not
  /// tied to any screen's lifecycle.
  static final SosService instance = SosService();

  /// The current emergency snapshot. Safe to read from a builder.
  SosSession get session => _session;

  SosState get state => _session.state;

  /// True while SOS is running and [reset] is meaningful.
  bool get isActive =>
      _session.state == SosState.active ||
      _session.state == SosState.activating;

  /// Whether the alert tone is genuinely playing right now.
  bool get isAlerting => _session.alerting;

  /// The primary emergency contact, or `null` when none is saved.
  EmergencyContact? get primaryContact {
    final List<EmergencyContact> all = _contacts.contacts;
    if (all.isEmpty) return null;
    // The existing architecture treats list order as priority: index 0 is the
    // contact the app has always called first.
    return all.first;
  }

  /// Keeps emergency guidance off the floor until reset.
  ///
  /// The block lives on [VoiceService] because the engine and queue are shared
  /// process-wide: gating there is what stops navigation turns, object
  /// detection and long-form reading from talking over SOS. Nothing is queued
  /// while it is blocked, so releasing it cannot replay stale announcements.
  void _suppressAppSpeech() {
    VoiceService.setRoutineSpeechBlocked(true);
    _navigation?.sceneVoiceMuted = true;
    _voice.stop();
  }

  void _releaseAppSpeech() {
    _navigation?.sceneVoiceMuted = false;
    VoiceService.setRoutineSpeechBlocked(false);
  }

  /// Emergency announcement, audible over the mute that SOS installs.
  void _announce(String message) => _voice.speakEmergency(message);

  /// Bumped on every activate and reset.
  ///
  /// Asynchronous work captures the current value and re-checks it after each
  /// await, so anything started before a reset becomes a no-op instead of
  /// sending a message or mutating a session the user already cancelled.
  int _generation = 0;

  /// True while [token] is still the live session.
  bool _live(int token) => token == _generation;

  /// Starts the emergency procedure.
  ///
  /// Returns false when SOS was already running, which is how a second
  /// activation is ignored instead of producing a second call.
  Future<bool> activate() async {
    if (isActive) {
      _announce('SOS is already active.');
      return false;
    }

    // A new generation invalidates anything left over from a previous session.
    final int token = ++_generation;

    final EmergencyContact? contact = primaryContact;
    _session = SosSession(
      state: SosState.activating,
      contactName: contact?.name ?? '',
      contactPhone: contact?.phone ?? '',
      callStep: SosStep.pending,
      locationStep: SosStep.pending,
      smsStep: SosStep.pending,
      alerting: false,
    );
    notifyListeners();

    // Silence the app's own guidance first: SOS owns the floor from here on,
    // and an object announcement landing mid-emergency is actively harmful.
    _suppressAppSpeech();

    // Audible indication goes first and needs no permission.
    await _startAlert(token);
    if (!_live(token)) return false;
    _vibration.vibrateSOS();

    final String name = _session.contactName;
    _announce(
      name.isEmpty
          ? 'SOS activated. No emergency contact is saved yet.'
          : 'SOS activated. Emergency call to $name.',
    );

    if (contact == null) {
      // Nothing to call or text, so no location request is started either.
      _session = _session.copyWith(
        state: SosState.active,
        callStep: SosStep.callFailed,
        callBlockerMessage:
            'No emergency contact is saved. Add one in Emergency settings.',
      );
      notifyListeners();
      _announce('No emergency contact is saved.');
      return true;
    }

    // GPS starts now and runs concurrently with the call. It is never awaited
    // before the call, and the message is chained off it afterwards.
    final Future<SosLocationResult> locationFuture = _resolveLocation(token);

    await _placeCall(contact, token);
    if (!_live(token)) return false;
    _session = _session.copyWith(state: SosState.active);
    notifyListeners();

    // Sequencing the message behind the fix is deliberate: the message should
    // carry a position, but must never delay reaching a person.
    unawaited(locationFuture.then((SosLocationResult r) {
      return _sendMessage(contact, r, token);
    }));
    return true;
  }

  /// Ends the emergency and returns the app to normal.
  ///
  /// Stops the tone, restores speech, and leaves nothing able to restart itself.
  Future<void> reset() async {
    if (!isActive) return;
    // Invalidates in-flight permission prompts, GPS and messaging *before* any
    // await, so a reset during a system dialog stops the rest of the procedure.
    _generation++;
    _session = _session.copyWith(state: SosState.resetting);
    notifyListeners();

    await _platform.stopAlertTone();
    _session = SosSession(
      state: SosState.inactive,
      contactName: '',
      contactPhone: '',
      callStep: SosStep.pending,
      locationStep: SosStep.pending,
      smsStep: SosStep.pending,
      alerting: false,
    );
    notifyListeners();

    _vibration.stopVibration();
    _releaseAppSpeech();
  }

  // ------------------------------------------------------------------
  // Steps
  // ------------------------------------------------------------------

  /// Starts the repeating alert, honouring the user's sound setting.
  ///
  /// The alert setting gates the tone only. The call, the message and GPS all
  /// run regardless, so switching the sound off never weakens the emergency.
  Future<void> _startAlert(int token) async {
    if (!_settings.sosAlertSoundEnabled) {
      // Deliberately reported as not alerting rather than pretending.
      return;
    }
    final bool playing =
        await _platform.startAlertTone(_settings.sosAlertTone.name);
    if (!_live(token)) {
      // Reset landed while the platform was starting: do not leave a tone behind.
      await _platform.stopAlertTone();
      return;
    }
    _session = _session.copyWith(alerting: playing);
    notifyListeners();
  }

  /// Places the call, requesting permission only if it is genuinely missing.
  Future<void> _placeCall(EmergencyContact contact, int token) async {
    _session = _session.copyWith(callStep: SosStep.calling);
    notifyListeners();

    if (!await _platform.hasCallPermission()) {
      if (!_live(token)) return;
      // Ask once, at the moment it is needed, so an emergency never fails
      // silently. A refusal falls back to a pre-filled dialer rather than
      // giving up, and is reported honestly.
      final bool granted = await _platform.requestCallPermission();
      if (!_live(token)) return;
      if (!granted) {
        final bool dialer = await _platform.openDialerFallback(contact.phone);
        if (!_live(token)) return;
        _session = _session.copyWith(
          callStep: SosStep.callNeedsUserTap,
          callBlockerMessage: dialer
              ? SosCallBlocker.callPhonePermission.message
              : SosCallBlocker.failed.message,
        );
        notifyListeners();
        _announce(
          dialer
              ? 'The dialer is open. Press call to connect.'
              : 'The call was not placed. Phone permission was not granted.',
        );
        return;
      }
    }

    final SosCallResult result = await _platform.placeDirectCall(contact.phone);
    if (!_live(token)) return;

    if (result.succeeded) {
      _session = _session.copyWith(
        callStep: SosStep.callConnected,
        clearCallBlocker: true,
      );
      notifyListeners();
      // Only acknowledge the platform accepting the call. Whether the person
      // answers is not something the app can know, so it is not claimed.
      _announce('Calling ${contact.name} now.');
    } else if (result.openedDialerInstead) {
      _session = _session.copyWith(
        callStep: SosStep.callNeedsUserTap,
        callBlockerMessage: result.blocker?.message ??
            SosCallBlocker.noDialer.message,
      );
      notifyListeners();
      _announce(
        'Could not call automatically. Press call on the dialer screen.',
      );
    } else {
      _session = _session.copyWith(
        callStep: SosStep.callFailed,
        callBlockerMessage:
            result.blocker?.message ?? SosCallBlocker.failed.message,
      );
      notifyListeners();
      _announce('The call was not placed.');
    }
  }

  /// Gets a fix, requesting permission only if it is missing.
  ///
  /// Never throws and never blocks the caller: a failure comes back as a typed
  /// blocker so the message can state that the position is unavailable.
  Future<SosLocationResult> _resolveLocation(int token) async {
    _session = _session.copyWith(locationStep: SosStep.locating);
    notifyListeners();

    if (!await _platform.hasLocationPermission()) {
      if (!_live(token)) {
        return const SosLocationResult.failed(
          SosLocationBlocker.locationPermission,
        );
      }
      final bool granted = await _platform.requestLocationPermission();
      if (!_live(token)) {
        return const SosLocationResult.failed(
          SosLocationBlocker.locationPermission,
        );
      }
      if (!granted) {
        _session = _session.copyWith(
          locationStep: SosStep.locationUnavailable,
          locationBlockerMessage: SosLocationBlocker.locationPermission.message,
        );
        notifyListeners();
        return const SosLocationResult.failed(
          SosLocationBlocker.locationPermission,
        );
      }
    }

    final SosLocationResult result = await _platform.getLocation();
    // A stale result is dropped rather than reported: the user already reset.
    if (!_live(token)) return result;

    if (result.succeeded) {
      _session = _session.copyWith(
        locationStep: SosStep.locationFound,
        location: result.location,
        clearLocationBlocker: true,
      );
    } else {
      _session = _session.copyWith(
        locationStep: SosStep.locationUnavailable,
        locationBlockerMessage:
            result.blocker?.message ?? SosLocationBlocker.unavailable.message,
        clearLocation: true,
      );
    }
    notifyListeners();
    return result;
  }

  /// Sends the emergency message with the location attached.
  ///
  /// Reports delivery honestly: a composer fallback is never described as a
  /// sent message.
  Future<void> _sendMessage(
    EmergencyContact contact,
    SosLocationResult location,
    int token,
  ) async {
    if (!_live(token)) return;
    _session = _session.copyWith(smsStep: SosStep.sendingMessage);
    notifyListeners();

    final String body = buildMessage(location: location.location);

    if (!await _platform.hasSmsPermission()) {
      if (!_live(token)) return;
      final bool granted = await _platform.requestSmsPermission();
      if (!_live(token)) return;
      if (!granted) {
        // Fall back to a pre-filled composer so the message is at least ready,
        // and keep reporting that nothing was sent.
        final bool composer = await _platform.openComposerFallback(
          contact.phone,
          body,
        );
        if (!_live(token)) return;
        _session = _session.copyWith(
          smsStep: SosStep.messageNotDelivered,
          smsBlockerMessage: composer
              ? 'A message is ready to send. Press send to deliver it.'
              : SosSmsBlocker.sendSmsPermission.message,
        );
        notifyListeners();
        _announce(
          composer
              ? 'The message is ready. Press send to deliver it.'
              : 'The message was not sent. Message permission was not granted.',
        );
        return;
      }
    }

    final SosSmsResult result = await _platform.sendSms(
      phone: contact.phone,
      body: body,
    );
    if (!_live(token)) return;

    if (result.delivered) {
      _session = _session.copyWith(
        smsStep: SosStep.messageDelivered,
        clearSmsBlocker: true,
      );
      notifyListeners();
      _announce('Emergency location sent to ${contact.name}.');
    } else if (result.openedComposerInstead) {
      _session = _session.copyWith(
        smsStep: SosStep.messageNotDelivered,
        smsBlockerMessage:
            'A message is ready to send. Press send to deliver it.',
      );
      notifyListeners();
      _announce('The message is ready. Press send to deliver it.');
    } else {
      _session = _session.copyWith(
        smsStep: SosStep.messageNotDelivered,
        smsBlockerMessage:
            result.blocker?.message ?? SosSmsBlocker.failed.message,
      );
      notifyListeners();
      _announce('The location message was not sent.');
    }
  }

  /// The exact emergency message body.
  ///
  /// Kept separate and deterministic so the wording is verifiable, and so an
  /// unavailable location produces an honest message rather than being omitted.
  static String buildMessage({SosLocation? location}) {
    final StringBuffer buffer = StringBuffer('SOS ALERT!');
    buffer.write('\nI need emergency assistance.');

    if (location == null) {
      buffer.write(
        '\nMy current location could not be obtained right now. '
        'Please check with me directly.',
      );
      return buffer.toString();
    }

    buffer.write('\nMy current location:');
    buffer.write('\n${location.mapsUrl}');
    buffer.write('\n(${location.coordinates})');
    return buffer.toString();
  }

  /// Turns the current session into one spoken summary.
  ///
  /// Used by the screen so a single tap gives the user the whole state rather
  /// than making them read it.
  String describeSession() {
    final SosSession s = _session;
    final List<String> parts = <String>[];
    if (s.state == SosState.inactive) {
      return 'SOS is not active.';
    }

    switch (s.callStep) {
      case SosStep.callConnected:
        parts.add('Calling ${s.contactName}.');
      case SosStep.callNeedsUserTap:
        parts.add('The dialer is open. Press call to connect.');
      case SosStep.callFailed:
        parts.add('The call was not placed. ${s.callBlockerMessage ?? ''}');
      case SosStep.calling:
        parts.add('Starting the call.');
      case SosStep.pending:
        break;
      case SosStep.locating:
      case SosStep.locationFound:
      case SosStep.locationUnavailable:
      case SosStep.sendingMessage:
      case SosStep.messageDelivered:
      case SosStep.messageNotDelivered:
      case SosStep.alerting:
        break;
    }

    switch (s.smsStep) {
      case SosStep.messageDelivered:
        parts.add('The location message was delivered.');
      case SosStep.messageNotDelivered:
        parts.add('The location message was not sent. ${s.smsBlockerMessage ?? ''}');
      case SosStep.sendingMessage:
        parts.add('Sending the location message.');
      default:
        break;
    }

    parts.add(s.alerting ? 'The alert is sounding.' : 'The alert is silent.');
    parts.add('Activate and hold anywhere to reset SOS.');
    return parts.join(' ');
  }
}