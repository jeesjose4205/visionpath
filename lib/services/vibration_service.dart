import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import 'settings_service.dart';

/// Emits the haptic patterns for the global ringer-style feedback switch
/// (SPEAKER / VIBRATE / MUTE).
///
/// Uses the native `vibration` plugin to run the real vibration motor with a
/// clearly perceptible pulse duration, falling back to Flutter's
/// [HapticFeedback] if the plugin is unavailable (and to nothing if the
/// accessibility "haptic feedback" switch is off). Starting a new pattern
/// always cancels the previous one so overlapping alerts never stack.
///
/// Exact patterns:
///   * [vibrateOnce]          — READ TEXT      → ONE pulse
///   * [vibrateNavigation]    — NAVIGATION     → exactly TWO pulses
///   * [vibrateFamiliarFace]  — FAMILIAR FACES → THREE pulses
///   * [vibrateSOS]           — SOS            → ~2 s continuous vibration
class VibrationService {
  VibrationService._();

  static final VibrationService instance = VibrationService._();

  /// Test hook: when set, every pulse is routed here instead of the platform
  /// so unit tests can count pattern pulses without platform channels.
  @visibleForTesting
  static void Function()? debugPulse;

  static const Duration _pulseGap = Duration(milliseconds: 200);
  static const Duration _sosTick = Duration(milliseconds: 160);
  static const int _sosTicks = 12;

  static const int _pulseMs = 150;
  static const int _amplitude = 255;

  Timer? _timer;

  bool get _allowed => SettingsService.instance.hapticFeedback;

  /// Trigger one motor pulse (native when possible, haptic fallback otherwise).
  static void _pulse() {
    final hook = debugPulse;
    if (hook != null) {
      hook();
      return;
    }
    unawaited(_emitPulse());
  }

  static Future<void> _emitPulse() async {
    try {
      await Vibration.vibrate(
        duration: _pulseMs,
        amplitude: _amplitude,
      );
    } on Object {
      // No vibrator / plugin failure: degrade to a haptic tap.
      await HapticFeedback.heavyImpact();
    }
  }

  /// Cancel any running pattern so a stale delayed result can never vibrate.
  void stopVibration() {
    _timer?.cancel();
    _timer = null;
    unawaited(Vibration.cancel().catchError((Object _) {}));
  }

  /// READ TEXT: a single short pulse.
  void vibrateOnce() {
    if (!_allowed) return;
    stopVibration();
    _pulse();
  }

  /// NAVIGATION: exactly two pulses — pulse, short pause, pulse.
  void vibrateNavigation() {
    if (!_allowed) return;
    stopVibration();
    _pulse();
    int pending = 1;
    _timer = Timer.periodic(_pulseGap, (Timer t) {
      if (pending <= 0) {
        t.cancel();
        _timer = null;
        return;
      }
      pending--;
      _pulse();
    });
  }

  /// FAMILIAR FACES: exactly three pulses — pulse, pause, pulse, pause, pulse.
  void vibrateFamiliarFace() {
    if (!_allowed) return;
    stopVibration();
    _pulse();
    int pending = 2;
    _timer = Timer.periodic(_pulseGap, (Timer t) {
      if (pending <= 0) {
        t.cancel();
        _timer = null;
        return;
      }
      pending--;
      _pulse();
    });
  }

  /// SOS: continuous vibration for approximately 2 seconds.
  void vibrateSOS() {
    if (!_allowed) return;
    stopVibration();
    int pending = _sosTicks;
    _pulse();
    _timer = Timer.periodic(_sosTick, (Timer t) {
      if (pending <= 0) {
        t.cancel();
        _timer = null;
        return;
      }
      pending--;
      _pulse();
    });
  }
}