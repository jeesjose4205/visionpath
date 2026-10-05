import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
// Prefixed import so the platform method below can keep the friendlier name
// without colliding with the top-level `openAppSettings` from
// permission_handler.
import 'package:permission_handler/permission_handler.dart' as ph;

import '../models/sos_session.dart';

/// Why the app cannot place a call directly, or `null` when it can.
///
/// These are deliberately distinct rather than a single boolean: the UI has to
/// tell the user whether a one-time permission grant would fix it, or whether
/// the device genuinely cannot do it.
enum SosCallBlocker {
  /// [android.permission.CALL_PHONE] has not been granted yet.
  callPhonePermission,

  /// No app on the device can handle `tel:` intents.
  noDialer,

  /// A stored contact had no dialable digits.
  invalidNumber,

  /// Something unexpected went wrong on the platform side.
  failed,
}

extension SosCallBlockerText on SosCallBlocker {
  /// True when granting the missing permission would make calling work.
  bool get isPermission =>
      this == SosCallBlocker.callPhonePermission;

  /// Short phrase for the UI, spoken and displayed.
  String get message => switch (this) {
        SosCallBlocker.callPhonePermission =>
          'Phone permission is needed to call automatically.',
        SosCallBlocker.noDialer =>
          'This device has no phone app, so a call cannot be placed.',
        SosCallBlocker.invalidNumber =>
          'The saved contact has no usable phone number.',
        SosCallBlocker.failed =>
          'The call could not be started on this device.',
      };
}

/// Why an emergency message was not sent, or `null` when it was confirmed.
enum SosSmsBlocker {
  /// [android.permission.SEND_SMS] has not been granted yet.
  sendSmsPermission,

  /// The platform has no SMS service.
  noSmsService,

  /// The saved contact had no dialable digits.
  invalidNumber,

  /// There was nothing to send.
  emptyMessage,

  /// The radio accepted the message but delivery was never confirmed.
  deliveryUnconfirmed,

  /// The carrier reported a failure.
  notDelivered,

  /// Something unexpected went wrong on the platform side.
  failed,
}

extension SosSmsBlockerText on SosSmsBlocker {
  bool get isPermission => this == SosSmsBlocker.sendSmsPermission;

  String get message => switch (this) {
        SosSmsBlocker.sendSmsPermission =>
          'Message permission is needed to send the location automatically.',
        SosSmsBlocker.noSmsService =>
          'This device has no messaging service.',
        SosSmsBlocker.invalidNumber =>
          'The saved contact has no usable phone number.',
        SosSmsBlocker.emptyMessage => 'There was no message to send.',
        SosSmsBlocker.deliveryUnconfirmed =>
          'The message was sent but delivery was not confirmed.',
        SosSmsBlocker.notDelivered => 'The carrier did not deliver the message.',
        SosSmsBlocker.failed => 'The message could not be sent on this device.',
      };
}

/// Why a location fix was unavailable, or `null` when one was obtained.
enum SosLocationBlocker {
  /// Neither location permission has been granted.
  locationPermission,

  /// Location is switched off for the device.
  disabled,

  /// No fix arrived within the timeout.
  timeout,

  /// The platform could not produce a fix at all.
  unavailable,
}

extension SosLocationBlockerText on SosLocationBlocker {
  bool get isPermission => this == SosLocationBlocker.locationPermission;

  String get message => switch (this) {
        SosLocationBlocker.locationPermission =>
          'Location permission is needed to share your position.',
        SosLocationBlocker.disabled => 'Location is switched off on this device.',
        SosLocationBlocker.timeout => 'Your location could not be found in time.',
        SosLocationBlocker.unavailable =>
          'Your location is not currently available.',
      };
}

/// What actually happened when the app tried to reach the contact.
class SosCallResult {
  const SosCallResult._({
    required this.connected,
    required this.blocker,
    required this.openedDialerInstead,
  });

  /// The platform accepted an `ACTION_CALL` request.
  ///
  /// This means the dialer was asked to connect the number. It deliberately
  /// does **not** claim the other person answered.
  final bool connected;

  /// Why it failed, or `null` on success.
  final SosCallBlocker? blocker;

  /// True when the call could not be placed and a pre-filled dialer was opened
  /// instead, so the user has to press call themselves.
  final bool openedDialerInstead;

  bool get succeeded => connected;

  /// True when the user still has to do something to complete the call.
  bool get needsUserAction => blocker != null || openedDialerInstead;
}

/// What actually happened when the app tried to send the emergency message.
class SosSmsResult {
  const SosSmsResult._({
    required this.delivered,
    required this.blocker,
    required this.openedComposerInstead,
  });

  /// The platform reported the message reached the handset.
  ///
  /// Only a real delivery report sets this. A message the radio merely
  /// accepted is never reported as delivered.
  final bool delivered;

  final SosSmsBlocker? blocker;

  /// True when a pre-filled composer was opened instead, so the message has not
  /// been sent until the user presses send.
  final bool openedComposerInstead;

  bool get succeeded => delivered;

  bool get needsUserAction => blocker != null || openedComposerInstead;
}

/// What actually happened when the app tried to get a GPS fix.
class SosLocationResult {
  const SosLocationResult._({required this.location, required this.blocker});

  /// A confirmed fix.
  const SosLocationResult.found(SosLocation location)
      : this._(location: location, blocker: null);

  /// No fix, with the reason why.
  const SosLocationResult.failed(SosLocationBlocker blocker)
      : this._(location: null, blocker: blocker);

  /// The fix, or `null` when none was obtained.
  final SosLocation? location;

  final SosLocationBlocker? blocker;

  bool get succeeded => location != null;
}

/// The runtime permissions the automatic procedure depends on.
///
/// Kept as its own enum so the permission flow can be reasoned about and tested
/// as one thing, instead of as three unrelated plugin calls.
enum SosPermission {
  /// Needed to place the call without a second tap.
  call,

  /// Needed to send the location by text automatically.
  message,

  /// Needed to attach a position to the message.
  location,
}

/// Android emergency capabilities used by SOS.
///
/// Backed by a single [MethodChannel] implemented in `MainActivity.kt`. Every
/// method reports what the platform actually did, and each degrades to an
/// explicit failure rather than an optimistic success, so the SOS flow can
/// never report a call or message that did not happen.
class SosPlatform {
  const SosPlatform();

  static const MethodChannel _channel =
      MethodChannel('com.example.visionpath/emergency');

  /// How long to wait for a GPS fix before falling back.
  static const Duration locationTimeout = Duration(seconds: 12);

  /// Test seam: set to intercept every channel call instead of the platform.
  ///
  /// Lets the SOS orchestration be tested end to end without a device.
  @visibleForTesting
  static Future<Object?>? Function(MethodCall call)? debugHandler;

  Future<Object?> _invoke(String method, [Map<String, Object?>? args]) async {
    final Future<Object?>? Function(MethodCall)? handler = debugHandler;
    if (handler != null) {
      return handler(MethodCall(method, args));
    }
    return _channel.invokeMethod<Object?>(method, args);
  }

  static Map<String, Object?> _map(Object? raw) {
    if (raw is Map) {
      return raw.map<String, Object?>(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      );
    }
    return const <String, Object?>{};
  }

  /// Maps a platform failure code onto a typed reason.
  static SosCallBlocker _callBlocker(String code) => switch (code) {
        'permission_call_phone' => SosCallBlocker.callPhonePermission,
        'no_dialer' => SosCallBlocker.noDialer,
        'invalid_number' => SosCallBlocker.invalidNumber,
        _ => SosCallBlocker.failed,
      };

  static SosSmsBlocker _smsBlocker(String code) => switch (code) {
        'permission_send_sms' => SosSmsBlocker.sendSmsPermission,
        'no_sms_service' => SosSmsBlocker.noSmsService,
        'invalid_number' => SosSmsBlocker.invalidNumber,
        'empty_message' => SosSmsBlocker.emptyMessage,
        'unconfirmed' => SosSmsBlocker.deliveryUnconfirmed,
        'not_delivered' => SosSmsBlocker.notDelivered,
        _ => SosSmsBlocker.failed,
      };

  static SosLocationBlocker _locationBlocker(String code) => switch (code) {
        'permission_location' => SosLocationBlocker.locationPermission,
        'location_disabled' => SosLocationBlocker.disabled,
        'location_timeout' => SosLocationBlocker.timeout,
        _ => SosLocationBlocker.unavailable,
      };

  /// Places the call directly, so no second tap is needed.
  ///
  /// Falls back to opening a pre-filled dialer only when a direct call is
  /// impossible, and reports that as [SosCallResult.openedDialerInstead] rather
  /// than as a placed call.
  Future<SosCallResult> placeDirectCall(String phone) async {
    try {
      final Map<String, Object?> data = _map(await _invoke(
        'placeDirectCall',
        <String, Object?>{'number': phone},
      ));
      final bool connected = data['placed'] == true;
      final String error = '${data['error'] ?? ''}';
      if (connected) {
        return SosCallResult._(
          connected: true,
          blocker: null,
          openedDialerInstead: false,
        );
      }

      // Direct calling failed: give the user a pre-filled dialer so the number
      // is at least on screen, but keep reporting that nothing was placed.
      if (error == 'permission_call_phone' || error == 'no_dialer') {
        final bool opened = await _openDialer(phone);
        return SosCallResult._(
          connected: false,
          blocker: _callBlocker(error),
          openedDialerInstead: opened,
        );
      }

      return SosCallResult._(
        connected: false,
        blocker: _callBlocker(error),
        openedDialerInstead: false,
      );
    } on PlatformException {
      return SosCallResult._(
        connected: false,
        blocker: SosCallBlocker.failed,
        openedDialerInstead: false,
      );
    } on MissingPluginException {
      return SosCallResult._(
        connected: false,
        blocker: SosCallBlocker.failed,
        openedDialerInstead: false,
      );
    }
  }

  /// Opens a pre-filled dialer for [phone].
  ///
  /// Public because it is also the fallback when the call permission is denied:
  /// the number should still end up on screen, with the UI saying plainly that
  /// the user still has to press call.
  Future<bool> openDialerFallback(String phone) async {
    try {
      final Map<String, Object?> data = _map(await _invoke(
        'openDialer',
        <String, Object?>{'number': phone},
      ));
      return data['opened'] == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> _openDialer(String phone) => openDialerFallback(phone);

  /// Sends the emergency message without a composer.
  ///
  /// [SosSmsResult.delivered] is only true once the platform reports a real
  /// delivery. Anything else is an explicit failure or a composer fallback.
  Future<SosSmsResult> sendSms({
    required String phone,
    required String body,
  }) async {
    try {
      final Map<String, Object?> data = _map(await _invoke(
        'sendSms',
        <String, Object?>{'number': phone, 'body': body},
      ));
      final String status = '${data['status'] ?? data['error'] ?? 'failed'}';
      if (data['sent'] == true) {
        return SosSmsResult._(
          delivered: true,
          blocker: null,
          openedComposerInstead: false,
        );
      }

      if (status == 'permission_send_sms' || status == 'no_sms_service') {
        final bool opened = await _openComposer(phone, body);
        return SosSmsResult._(
          delivered: false,
          blocker: _smsBlocker(status),
          openedComposerInstead: opened,
        );
      }

      return SosSmsResult._(
        delivered: false,
        blocker: _smsBlocker(status),
        openedComposerInstead: false,
      );
    } on PlatformException {
      return SosSmsResult._(
        delivered: false,
        blocker: SosSmsBlocker.failed,
        openedComposerInstead: false,
      );
    } on MissingPluginException {
      return SosSmsResult._(
        delivered: false,
        blocker: SosSmsBlocker.failed,
        openedComposerInstead: false,
      );
    }
  }

  /// Opens a pre-filled composer for [phone] containing [body].
  ///
  /// Public for the same reason as [openDialerFallback]: it is the fallback when
  /// the send permission is missing. Nothing is sent until the user taps send,
  /// and callers report it that way.
  Future<bool> openComposerFallback(String phone, String body) async {
    try {
      final Map<String, Object?> data = _map(await _invoke(
        'openSmsComposer',
        <String, Object?>{'number': phone, 'body': body},
      ));
      return data['opened'] == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> _openComposer(String phone, String body) =>
      openComposerFallback(phone, body);

  /// Fetches one GPS fix, or explains why none is available.
  Future<SosLocationResult> getLocation() async {
    try {
      final Map<String, Object?> data = _map(await _invoke(
        'getLocation',
        <String, Object?>{
          'timeoutMs': locationTimeout.inMilliseconds,
        },
      ));
      final Object? latitude = data['latitude'];
      final Object? longitude = data['longitude'];
      if (latitude is num && longitude is num) {
        final Object? accuracy = data['accuracyMeters'];
        final Object? age = data['ageMs'];
        return SosLocationResult._(
          location: SosLocation(
            latitude: latitude.toDouble(),
            longitude: longitude.toDouble(),
            accuracyMeters:
                accuracy is num && accuracy.toDouble() > 0
                    ? accuracy.toDouble()
                    : null,
            age: Duration(milliseconds: age is num ? age.toDouble().round() : 0),
          ),
          blocker: null,
        );
      }
      return SosLocationResult._(
        location: null,
        blocker: _locationBlocker('${data['error'] ?? 'unavailable'}'),
      );
    } on PlatformException {
      return SosLocationResult._(
        location: null,
        blocker: SosLocationBlocker.unavailable,
      );
    } on MissingPluginException {
      return SosLocationResult._(
        location: null,
        blocker: SosLocationBlocker.unavailable,
      );
    }
  }

  /// Starts the repeating alert tone.
  ///
  /// Returns false when the platform refused to make any sound, which happens
  /// on devices that silence tones under Do Not Disturb. The caller must
  /// surface that instead of implying an alarm is sounding.
  Future<bool> startAlertTone(String tone) async {
    try {
      return await _invoke(
            'startAlertTone',
            <String, Object?>{'tone': tone},
          ) ==
          true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Stops the alert tone and releases the audio resource.
  Future<void> stopAlertTone() async {
    try {
      await _invoke('stopAlertTone');
    } on PlatformException {
      // Nothing to do: the tone is already not sounding from our side.
    } on MissingPluginException {
      // No platform channel, so no tone was ever started here.
    }
  }

  Future<bool> isAlertToneSupported() async {
    try {
      return await _invoke('isAlertToneSupported') == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Test seam: answers permission queries without touching the platform.
  ///
  /// Permission requests cannot run in a widget test, so the SOS orchestration
  /// tests substitute the answers directly.
  @visibleForTesting
  static bool Function(SosPermission permission)? debugPermission;

  static bool _permission(SosPermission permission) {
    final bool Function(SosPermission)? hook = debugPermission;
    if (hook != null) return hook(permission);
    return false;
  }

  /// Whether a direct call could work if granted.
  ///
  /// Every permission query is error-guarded: an emergency must degrade to a
  /// dialer fallback rather than throw while asking whether it may dial.
  Future<bool> hasCallPermission() async {
    if (debugPermission != null) return _permission(SosPermission.call);
    return _guard(() => Permission.phone.isGranted);
  }

  /// Asks for the permission that allows direct calling.
  Future<bool> requestCallPermission() async {
    if (debugPermission != null) return _permission(SosPermission.call);
    return _guard(() async {
      final PermissionStatus status = await Permission.phone.request();
      return status.isGranted;
    });
  }

  Future<bool> hasSmsPermission() async {
    if (debugPermission != null) return _permission(SosPermission.message);
    return _guard(() => Permission.sms.isGranted);
  }

  Future<bool> requestSmsPermission() async {
    if (debugPermission != null) return _permission(SosPermission.message);
    return _guard(() async {
      final PermissionStatus status = await Permission.sms.request();
      return status.isGranted;
    });
  }

  Future<bool> hasLocationPermission() async {
    if (debugPermission != null) return _permission(SosPermission.location);
    return _guard(() async {
      return await Permission.locationWhenInUse.isGranted ||
          await Permission.location.isGranted;
    });
  }

  Future<bool> requestLocationPermission() async {
    if (debugPermission != null) return _permission(SosPermission.location);
    return _guard(() async {
      final PermissionStatus whenInUse =
          await Permission.locationWhenInUse.request();
      if (whenInUse.isGranted) return true;
      final PermissionStatus status = await Permission.location.request();
      return status.isGranted;
    });
  }

  /// Runs a permission query, treating any platform failure as "not granted".
  static Future<bool> _guard(Future<bool> Function() action) async {
    try {
      return await action();
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Sends the user to the system settings page for this app.
  ///
  /// Used when a permission was permanently denied, since the system dialog
  /// will no longer appear on its own.
  Future<bool> openAppSettings() async {
    try {
      return await ph.openAppSettings();
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}