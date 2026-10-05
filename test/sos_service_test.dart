import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/models/app_settings.dart';
import 'package:visionpath/models/emergency_contact.dart';
import 'package:visionpath/models/sos_session.dart';
import 'package:visionpath/services/emergency_contact_service.dart';
import 'package:visionpath/services/settings_service.dart';
import 'package:visionpath/services/sos_platform.dart';
import 'package:visionpath/services/sos_service.dart';
import 'package:visionpath/services/vibration_service.dart';
import 'package:visionpath/services/voice_service.dart';

/// The automatic emergency procedure, verified against a stubbed platform.
///
/// The stub answers exactly what the Android side answers, so these tests pin
/// the behaviour that actually matters to a user in an emergency: one call, one
/// message, a call that never waits for GPS, no duplicate activation, honest
/// wording when something failed, and reset cancelling everything in flight.
void main() {
  late _PlatformStub platform;
  late SosService service;

  setUp(() {
    platform = _PlatformStub();
    SosPlatform.debugHandler = platform.handle;
    SosPlatform.debugPermission = (_) => true;

    service = SosService(
      platform: const SosPlatform(),
      contacts: _Contacts.seeded(),
      settings: _Settings(),
      vibration: _NoVibration(),
      voice: _SilentVoice(),
    );
  });

  tearDown(() {
    SosPlatform.debugHandler = null;
    SosPlatform.debugPermission = null;
  });

  /// Lets pending futures finish under a bounded budget, so a regression fails
  /// instead of hanging the suite.
  Future<void> settle() async {
    for (int i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('activation', () {
    test('places the call, gets a fix and sends one message', () async {
      await service.activate();
      await settle();

      final SosSession s = service.session;
      expect(s.state, SosState.active);
      expect(s.callStep, SosStep.callConnected);
      expect(s.locationStep, SosStep.locationFound);
      expect(s.smsStep, SosStep.messageDelivered);
      expect(s.alerting, isTrue);

      expect(platform.count('placeDirectCall'), 1);
      expect(platform.count('sendSms'), 1);
      expect(platform.count('startAlertTone'), 1);
    });

    test('the alert starts before the call is placed', () async {
      await service.activate();
      await settle();

      expect(
        platform.indexOf('startAlertTone'),
        lessThan(platform.indexOf('placeDirectCall')),
        reason: 'audible feedback needs no permission, so it must go first',
      );
    });

    test('the call is placed while GPS is still pending', () async {
      // GPS never answers during the call, proving the call is not gated on it.
      platform.holdLocation();

      await service.activate();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        platform.methods,
        contains('placeDirectCall'),
        reason: 'the call must not wait for a GPS fix',
      );
      expect(service.session.locationStep, SosStep.locating);
      expect(service.session.callStep, SosStep.callConnected);

      platform.releaseLocation();
      await settle();
      expect(service.session.smsStep, SosStep.messageDelivered);
    });

    test('a second activation produces no second call or message', () async {
      await service.activate();
      await settle();
      final int count = platform.methods.length;

      expect(await service.activate(), isFalse);
      await settle();

      expect(platform.methods.length, count);
      expect(platform.count('placeDirectCall'), 1);
      expect(platform.count('sendSms'), 1);
    });
  });

  group('honest reporting', () {
    test('a failed call is never reported as connected', () async {
      platform.callPlaced = false;
      platform.dialerOpens = false;

      await service.activate();
      await settle();

      expect(service.session.callStep, SosStep.callFailed);
      expect(service.session.callBlockerMessage, isNotNull);
      // The rest of the emergency still happened.
      expect(service.session.smsStep, SosStep.messageDelivered);
    });

    test('a dialer fallback asks for the tap instead of claiming a call',
        () async {
      platform.callPlaced = false;

      await service.activate();
      await settle();

      expect(service.session.callStep, SosStep.callNeedsUserTap);
      expect(service.session.callBlockerMessage, isNotNull);
      expect(platform.count('openDialer'), 1);
    });

    test('an unconfirmed message is not reported as sent', () async {
      platform.smsDelivered = false;
      platform.composerOpens = false;

      await service.activate();
      await settle();

      expect(service.session.smsStep, SosStep.messageNotDelivered);
      expect(service.session.smsBlockerMessage, isNotNull);
    });

    test('a composer fallback says the user must press send', () async {
      // The platform could not send it at all, which is the case where a
      // pre-filled composer is a real fallback.
      platform.smsDelivered = false;
      platform.smsStatus = 'no_sms_service';

      await service.activate();
      await settle();

      expect(service.session.smsStep, SosStep.messageNotDelivered);
      expect(service.session.smsBlockerMessage, contains('Press send'));
      expect(platform.count('openSmsComposer'), 1);
    });

    test('a missing fix produces an honest message, not an empty one',
        () async {
      platform.locationWorks = false;

      await service.activate();
      await settle();

      expect(service.session.locationStep, SosStep.locationUnavailable);
      expect(platform.lastBody, contains('could not be obtained'));
      expect(platform.lastBody, isNot(contains('maps/search')));
    });

    test('a message that was delivered carries the maps link', () async {
      await service.activate();
      await settle();

      expect(
        platform.lastBody,
        contains('https://www.google.com/maps/search/?api=1&query='),
      );
      expect(platform.lastNumber, '+15550000000');
    });

    test('a silent alert is reported as not alerting, emergency unaffected',
        () async {
      platform.alertPlays = false;

      await service.activate();
      await settle();

      expect(service.session.alerting, isFalse);
      expect(service.session.callStep, SosStep.callConnected);
      expect(service.session.smsStep, SosStep.messageDelivered);
    });

    test('with no contact saved the failure is explained', () async {
      service = SosService(
        platform: const SosPlatform(),
        contacts: _Contacts.empty(),
        settings: _Settings(),
        vibration: _NoVibration(),
        voice: _SilentVoice(),
      );

      await service.activate();
      await settle();

      expect(service.session.callStep, SosStep.callFailed);
      expect(service.session.callBlockerMessage, contains('No emergency contact'));
      expect(platform.methods, isNot(contains('placeDirectCall')));
      expect(platform.methods, isNot(contains('sendSms')));
    });

    test('a denied call permission falls back to a dialer', () async {
      SosPlatform.debugPermission = (SosPermission p) =>
          p != SosPermission.call;

      await service.activate();
      await settle();

      expect(platform.count('openDialer'), 1);
      expect(service.session.callStep, SosStep.callNeedsUserTap);
      // GPS and messaging are unaffected by the call permission.
      expect(service.session.smsStep, SosStep.messageDelivered);
    });

    test('a denied message permission falls back to a composer', () async {
      SosPlatform.debugPermission = (SosPermission p) =>
          p != SosPermission.message;

      await service.activate();
      await settle();

      expect(platform.count('openSmsComposer'), 1);
      expect(service.session.smsStep, SosStep.messageNotDelivered);
      expect(platform.methods, isNot(contains('sendSms')));
      // The call still happened.
      expect(service.session.callStep, SosStep.callConnected);
    });

    test('a denied location permission reports the position as unavailable',
        () async {
      SosPlatform.debugPermission = (SosPermission p) =>
          p != SosPermission.location;

      await service.activate();
      await settle();

      expect(service.session.locationStep, SosStep.locationUnavailable);
      expect(platform.methods, isNot(contains('getLocation')));
      expect(platform.lastBody, contains('could not be obtained'));
      // Call and message still happened.
      expect(service.session.callStep, SosStep.callConnected);
      expect(service.session.smsStep, SosStep.messageDelivered);
    });
  });

  group('reset', () {
    test('stops the tone and clears the session', () async {
      await service.activate();
      await settle();

      await service.reset();
      await settle();

      expect(service.session.state, SosState.inactive);
      expect(service.session.canReset, isFalse);
      expect(platform.count('stopAlertTone'), greaterThanOrEqualTo(1));
    });

    test('a message pending when reset lands is never sent', () async {
      // Messaging only begins once the fix resolves, so hold GPS open, reset,
      // then release it.
      platform.holdLocation();

      await service.activate();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await service.reset();

      platform.releaseLocation();
      await settle();

      expect(
        platform.methods,
        isNot(contains('sendSms')),
        reason: 'a cancelled session must not send anything after reset',
      );
      expect(service.session.state, SosState.inactive);
    });

    test('a fix that arrives after reset does not revive SOS', () async {
      platform.holdLocation();

      await service.activate();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await service.reset();

      platform.releaseLocation();
      await settle();

      expect(service.session.canReset, isFalse);
      expect(service.session.locationStep, SosStep.pending);
      expect(service.session.location, isNull);
    });

    test('a stale blocker message is cleared once the step succeeds',
        () async {
      platform.callPlaced = false;
      platform.dialerOpens = false;
      await service.activate();
      await settle();
      expect(service.session.callBlockerMessage, isNotNull);

      // A second run succeeds; the old explanation must not linger.
      await service.reset();
      await settle();
      platform.callPlaced = true;
      await service.activate();
      await settle();

      expect(service.session.callStep, SosStep.callConnected);
      expect(service.session.callBlockerMessage, isNull);
    });

    test('SOS can be activated again after a reset', () async {
      await service.activate();
      await settle();
      await service.reset();
      await settle();

      expect(await service.activate(), isTrue);
      await settle();

      expect(service.session.state, SosState.active);
      expect(platform.count('placeDirectCall'), 2);
      expect(platform.count('sendSms'), 2);
    });
  });

  group('message body', () {
    test('includes the maps link and coordinates when a fix is known', () {
      const SosLocation fix = SosLocation(
        latitude: 51.507351,
        longitude: -0.127758,
        accuracyMeters: 8,
        age: Duration(seconds: 2),
      );
      final String body = SosService.buildMessage(location: fix);

      expect(body, contains('SOS ALERT'));
      expect(
        body,
        contains(
          'https://www.google.com/maps/search/?api=1&query=51.507351,-0.127758',
        ),
      );
      expect(body, contains('51.507351, -0.127758'));
    });

    test('states plainly that the position is unavailable otherwise', () {
      final String body = SosService.buildMessage();

      expect(body, contains('could not be obtained'));
      expect(body, isNot(contains('maps')));
    });
  });
}

/// Answers the platform channel the way `MainActivity` would, and records what
/// it was asked, so tests can assert what did and did not happen.
class _PlatformStub {
  bool callPlaced = true;
  bool smsDelivered = true;

  /// Platform failure code returned when the message is not delivered.
  String smsStatus = 'unconfirmed';
  bool dialerOpens = true;
  bool composerOpens = true;
  bool locationWorks = true;
  bool alertPlays = true;

  final List<String> methods = <String>[];
  final List<Map<String, Object?>> args = <Map<String, Object?>>[];

  String lastNumber = '';
  String lastBody = '';

  Completer<void>? _locationGate;

  /// Makes `getLocation` hang until [releaseLocation] is called.
  void holdLocation() => _locationGate = Completer<void>();

  void releaseLocation() {
    _locationGate?.complete();
    _locationGate = null;
  }

  int count(String method) => methods.where((String m) => m == method).length;

  int indexOf(String method) => methods.indexOf(method);

  Future<Object?> handle(MethodCall call) async {
    methods.add(call.method);
    final Map<Object?, Object?> a =
        (call.arguments as Map<Object?, Object?>?) ?? const <Object?, Object?>{};
    args.add(a.map<String, Object?>(
      (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
    ));

    switch (call.method) {
      case 'startAlertTone':
        return alertPlays;
      case 'stopAlertTone':
      case 'isAlertToneSupported':
        return true;
      case 'placeDirectCall':
        lastNumber = '${a['number'] ?? ''}';
        return <String, Object?>{
          'placed': callPlaced,
          'error': callPlaced ? '' : 'no_dialer',
        };
      case 'openDialer':
        lastNumber = '${a['number'] ?? ''}';
        return <String, Object?>{'opened': dialerOpens};
      case 'sendSms':
        lastNumber = '${a['number'] ?? ''}';
        lastBody = '${a['body'] ?? ''}';
        return <String, Object?>{
          'sent': smsDelivered,
          'status': smsDelivered ? 'delivered' : smsStatus,
          'error': smsDelivered ? '' : smsStatus,
        };
      case 'openSmsComposer':
        lastNumber = '${a['number'] ?? ''}';
        lastBody = '${a['body'] ?? ''}';
        return <String, Object?>{'opened': composerOpens};
      case 'getLocation':
        await _locationGate?.future;
        if (!locationWorks) {
          return <String, Object?>{
            'latitude': null,
            'longitude': null,
            'error': 'location_timeout',
          };
        }
        return <String, Object?>{
          'latitude': 51.5074,
          'longitude': -0.1278,
          'accuracyMeters': 8.0,
          'ageMs': 1500,
        };
      default:
        return null;
    }
  }
}

/// Contact store with the primary contact preloaded.
class _Contacts extends Fake implements EmergencyContactService {
  _Contacts.seeded()
      : _list = const <EmergencyContact>[
          EmergencyContact(name: 'Sam Rivera', phone: '+15550000000'),
        ];

  _Contacts.empty() : _list = const <EmergencyContact>[];

  final List<EmergencyContact> _list;

  @override
  List<EmergencyContact> get contacts => _list;
}

/// Keeps the alert sound on so the tone path is exercised.
class _Settings extends Fake implements SettingsService {
  @override
  bool get sosAlertSoundEnabled => true;

  @override
  SosAlertTone get sosAlertTone => SosAlertTone.emergency;
}

/// Vibration is not part of what these tests verify, and the plugin channel is
/// absent here.
class _NoVibration extends Fake implements VibrationService {
  @override
  void vibrateSOS() {}

  @override
  void stopVibration() {}
}

/// Speech is not part of what these tests verify.
class _SilentVoice extends Fake implements VoiceService {
  @override
  void speak(String message) {}

  @override
  void speakEmergency(String message) {}

  @override
  void stop() {}
}