import 'dart:async';

import 'package:flutter/material.dart';

enum _SosPhase { ready, countdown, activated }

/// A large press-and-hold SOS control with a polished animated design.
///
/// The button owns its [Timer] so that releasing the pointer or disposing the
/// widget always cancels the countdown. Activation only fires after holding
/// for 5 full seconds.
class EmergencySOSButton extends StatefulWidget {
  const EmergencySOSButton({
    super.key,
    required this.onActivated,
    this.onTick,
    this.onCancelled,
    this.onReset,
  });

  /// Fired when the button has been held for the full 5 seconds.
  final VoidCallback onActivated;

  /// Fired on each countdown tick with the remaining seconds (5, 4, 3, 2, 1).
  final ValueChanged<int>? onTick;

  /// Fired when the pointer is released or cancelled before activation.
  final VoidCallback? onCancelled;

  /// Fired when the user confirms resetting after an activation.
  final VoidCallback? onReset;

  @override
  State<EmergencySOSButton> createState() => _EmergencySOSButtonState();
}

class _EmergencySOSButtonState extends State<EmergencySOSButton>
    with SingleTickerProviderStateMixin {
  static const Color _ink = Color(0xFF15233D);
  static const Color _mainRed = Color(0xFFD92D20);
  static const Color _amber = Color(0xFFB26A00);
  static const Color _amberLight = Color(0xFFFFE082);

  late final AnimationController _pulse;
  _SosPhase _phase = _SosPhase.ready;
  int _secondsRemaining = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pulse.dispose();
    super.dispose();
  }

  double get _pulseAmplitude {
    switch (_phase) {
      case _SosPhase.ready:
        return 0.018;
      case _SosPhase.countdown:
        return 0.045;
      case _SosPhase.activated:
        return 0.06;
    }
  }

  void _startCountdown() {
    if (_phase != _SosPhase.ready) return;
    setState(() {
      _phase = _SosPhase.countdown;
      _secondsRemaining = 5;
    });
    widget.onTick?.call(5);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = _secondsRemaining - 1;
      if (next <= 0) {
        timer.cancel();
        _timer = null;
        if (!mounted) return;
        setState(() {
          _phase = _SosPhase.activated;
          _secondsRemaining = 0;
        });
        widget.onActivated();
        return;
      }
      if (!mounted) return;
      setState(() => _secondsRemaining = next);
      widget.onTick?.call(next);
    });
  }

  void _cancelCountdown() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    if (!mounted) return;
    setState(() {
      _phase = _SosPhase.ready;
      _secondsRemaining = 5;
    });
    widget.onCancelled?.call();
  }

  void _pointerDown() {
    switch (_phase) {
      case _SosPhase.ready:
      case _SosPhase.countdown:
        _startCountdown();
      case _SosPhase.activated:
        break;
    }
  }

  void _pointerUp() {
    switch (_phase) {
      case _SosPhase.ready:
      case _SosPhase.activated:
        break;
      case _SosPhase.countdown:
        _cancelCountdown();
    }
  }

  void _reset() {
    if (_phase != _SosPhase.activated) return;
    setState(() {
      _phase = _SosPhase.ready;
      _secondsRemaining = 5;
    });
    widget.onReset?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isCountdown = _phase == _SosPhase.countdown;
    final isActivated = _phase == _SosPhase.activated;
    final progress = isActivated
        ? 1.0
        : isCountdown
            ? (5 - _secondsRemaining) / 5
            : 0.0;

    final label = isActivated
        ? 'SOS Activated'
        : isCountdown
            ? 'Keep holding... releasing cancels'
            : 'Press & hold for 5 seconds';
    final labelColor =
        isActivated ? _mainRed : isCountdown ? _amber : _ink;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        final scale = 1 + t * _pulseAmplitude;
        final glow =
            14 + t * (isActivated ? 26.0 : 12).toDouble();

        final circle = Semantics(
          label: isActivated
              ? 'SOS activated. Tap reset to return to ready.'
              : 'SOS button. Press and hold for 5 seconds to activate.',
          toggled: isActivated,
          button: true,
          child: Listener(
            onPointerDown: (_) => _pointerDown(),
            onPointerUp: (_) => _pointerUp(),
            onPointerCancel: (_) => _pointerUp(),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFF5C63),
                      _mainRed,
                      Color(0xFF9B1C12),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white,
                    width: isActivated ? 3 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _mainRed.withValues(
                        alpha: isActivated ? 0.5 : 0.34,
                      ),
                      blurRadius: glow,
                      spreadRadius: glow * 0.25,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isCountdown || isActivated)
                      SizedBox(
                        width: 148,
                        height: 148,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 5,
                          strokeCap: StrokeCap.round,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isCountdown ? _amberLight : Colors.white,
                          ),
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActivated
                              ? Icons.emergency_share_rounded
                              : Icons.sos_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        if (isCountdown) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '$_secondsRemaining',
                              style: const TextStyle(
                                color: _mainRed,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                        if (isActivated) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'ACTIVATED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            circle,
            const SizedBox(height: 14),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: labelColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isActivated) ...[
              const SizedBox(height: 10),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  onTap: _reset,
                  customBorder: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE8EDF4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 16, color: _mainRed),
                        SizedBox(width: 6),
                        Text(
                          'Reset SOS',
                          style: TextStyle(
                            color: _mainRed,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}