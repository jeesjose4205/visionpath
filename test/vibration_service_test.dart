import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionpath/services/settings_service.dart';
import 'package:visionpath/services/vibration_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
  });

  tearDown(() {
    VibrationService.instance.stopVibration();
    VibrationService.debugPulse = null;
  });

  List<int> attachPulseCounter() {
    final pulses = <int>[];
    VibrationService.debugPulse = () => pulses.add(1);
    return pulses;
  }

  test('vibrateOnce emits exactly one pulse', () async {
    final pulses = attachPulseCounter();
    VibrationService.instance.vibrateOnce();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(pulses, hasLength(1));
  });

  test('vibrateNavigation emits exactly two pulses (pulse, pause, pulse)',
      () async {
    final pulses = attachPulseCounter();
    VibrationService.instance.vibrateNavigation();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(pulses, hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(pulses, hasLength(2));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(pulses, hasLength(2));
  });

  test('vibrateFamiliarFace emits exactly three pulses', () async {
    final pulses = attachPulseCounter();
    VibrationService.instance.vibrateFamiliarFace();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(pulses, hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(pulses, hasLength(3));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(pulses, hasLength(3));
  });

  test('vibrateSOS buzzes for approximately two seconds then stops', () async {
    final pulses = attachPulseCounter();
    VibrationService.instance.vibrateSOS();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(pulses.length, greaterThanOrEqualTo(1));
    expect(pulses.length, lessThan(4));
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    final total = pulses.length;
    expect(total, greaterThanOrEqualTo(12));
    expect(total, lessThanOrEqualTo(14));
    // The pattern has stopped: no additional pulses afterwards.
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(pulses.length, total);
  });

  test('stopVibration cancels a running SOS pattern', () async {
    final pulses = attachPulseCounter();
    VibrationService.instance.vibrateSOS();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    VibrationService.instance.stopVibration();
    final atStop = pulses.length;
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(pulses.length, atStop);
  });

  test('a new pattern replaces the previous one', () async {
    final pulses = attachPulseCounter();
    VibrationService.instance.vibrateSOS();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final before = pulses.length;
    VibrationService.instance.vibrateOnce();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // exactly one extra pulse from the new pattern...
    expect(pulses.length, before + 1);
    final atOnce = pulses.length;
    // ...and the old SOS pattern is no longer running.
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    expect(pulses.length, atOnce);
  });

  test('vibration is suppressed when haptics are disabled', () async {
    final pulses = attachPulseCounter();
    await SettingsService.instance.setHapticFeedback(false);
    VibrationService.instance.vibrateOnce();
    VibrationService.instance.vibrateNavigation();
    VibrationService.instance.vibrateFamiliarFace();
    VibrationService.instance.vibrateSOS();
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(pulses, isEmpty);
    await SettingsService.instance.setHapticFeedback(true);
  });
}