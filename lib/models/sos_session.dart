import 'package:flutter/foundation.dart';

/// The single source of truth for whether SOS is running.
///
/// Everything the emergency procedure does - the alert tone, the call, the
/// location, the message - is driven from here rather than from a widget. That
/// is what lets the alert keep sounding after the user leaves the SOS screen,
/// and what makes "reset" able to guarantee nothing is left running.
enum SosState {
  /// Nothing is happening. The normal app is in charge.
  inactive,

  /// SOS was requested and the procedure is under way.
  ///
  /// The emergency call is placed during this phase, so it is short-lived and
  /// the audible tone is already playing.
  activating,

  /// The emergency procedure is live and the alert is repeating.
  active,

  /// The user asked to stop. Teardown is in progress.
  resetting,
}

/// One step of the automatic emergency procedure, for display and speech.
///
/// Each step is reported with what actually happened, so nothing in the UI can
/// claim a call or message succeeded when it did not.
enum SosStep {
  /// Nothing has started yet.
  pending,

  /// Contacting the primary emergency contact.
  calling,

  /// A direct call was accepted by the platform.
  callConnected,

  /// A pre-filled dialer was opened; the user must still press call.
  callNeedsUserTap,

  /// The call could not be placed.
  callFailed,

  /// Obtaining a GPS fix.
  locating,

  /// A fix was obtained and is being attached to the message.
  locationFound,

  /// No fix was available; the message says so.
  locationUnavailable,

  /// Sending the emergency message.
  sendingMessage,

  /// The platform confirmed the message was delivered.
  messageDelivered,

  /// The message could not be confirmed as sent.
  messageNotDelivered,

  /// The alert tone is repeating.
  alerting,
}

/// A single GPS fix, as attached to an emergency message.
@immutable
class SosLocation {
  const SosLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.age,
  });

  final double latitude;
  final double longitude;

  /// Reported accuracy in metres, or `null` when the fix carried none.
  final double? accuracyMeters;

  /// How old the fix was when it was handed over.
  final Duration age;

  /// A link the recipient can tap to open the position in Maps.
  String get mapsUrl =>
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';

  /// Coordinates rounded to roughly one-metre precision.
  ///
  /// Six decimals is about 0.11 m, which keeps the message readable without
  /// meaningfully overstating how accurate the fix actually is.
  String get coordinates =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}

/// A read-only snapshot of the emergency procedure.
///
/// Immutable so a widget can render one without later mutating under it.
@immutable
class SosSession {
  const SosSession({
    required this.state,
    required this.contactName,
    required this.contactPhone,
    required this.callStep,
    required this.locationStep,
    required this.smsStep,
    required this.alerting,
    this.location,
    this.callBlockerMessage,
    this.smsBlockerMessage,
    this.locationBlockerMessage,
  });

  /// The state this session was left in.
  final SosState state;

  /// The primary contact being reached, or an empty string when none is saved.
  final String contactName;
  final String contactPhone;

  /// How far the call step got.
  final SosStep callStep;

  /// How far the location step got.
  final SosStep locationStep;

  /// How far the message step got.
  final SosStep smsStep;

  /// Whether the repeating alert tone is genuinely playing.
  final bool alerting;

  /// The fix used in the message, when one was obtained.
  final SosLocation? location;

  /// Why the call did not connect, when it did not.
  final String? callBlockerMessage;

  /// Why the message was not confirmed, when it was not.
  final String? smsBlockerMessage;

  /// Why no location was obtained, when none was.
  final String? locationBlockerMessage;

  /// True while the user may still reset SOS.
  bool get canReset => state == SosState.active || state == SosState.activating;

  /// True when a contact was available to reach at all.
  bool get hasContact => contactName.isNotEmpty && contactPhone.isNotEmpty;

  /// An explicit `true` for a blocker clears the stored message.
  ///
  /// Needed because `null` already means "leave it alone", so a step that is
  /// retried after failing has to be able to drop its earlier explanation.
  SosSession copyWith({
    SosState? state,
    SosStep? callStep,
    SosStep? locationStep,
    SosStep? smsStep,
    bool? alerting,
    SosLocation? location,
    bool clearLocation = false,
    String? callBlockerMessage,
    bool clearCallBlocker = false,
    String? smsBlockerMessage,
    bool clearSmsBlocker = false,
    String? locationBlockerMessage,
    bool clearLocationBlocker = false,
  }) {
    return SosSession(
      state: state ?? this.state,
      contactName: contactName,
      contactPhone: contactPhone,
      callStep: callStep ?? this.callStep,
      locationStep: locationStep ?? this.locationStep,
      smsStep: smsStep ?? this.smsStep,
      alerting: alerting ?? this.alerting,
      location: clearLocation ? null : (location ?? this.location),
      callBlockerMessage: clearCallBlocker
          ? null
          : (callBlockerMessage ?? this.callBlockerMessage),
      smsBlockerMessage: clearSmsBlocker
          ? null
          : (smsBlockerMessage ?? this.smsBlockerMessage),
      locationBlockerMessage: clearLocationBlocker
          ? null
          : (locationBlockerMessage ?? this.locationBlockerMessage),
    );
  }
}