import 'dart:async';

import 'package:flutter/material.dart';

/// Visual phases of the SOS hold.
enum SosHoldPhase { ready, countdown, activated }

/// The single owner of the SOS press-and-hold state machine.
///
/// Extracted so that the SOS screen can accept the hold anywhere on its surface
/// while the SOS button keeps rendering exactly the same progress it always
/// did. There is deliberately ONE countdown, ONE timer and ONE activation path:
/// the button is a view onto this controller, not a second implementation of
/// it. Anything that wants to accept the hold (today the whole screen) simply
/// forwards raw pointer events to [pointerDown]/[pointerMove]/[pointerUp].
class SosHoldController extends ChangeNotifier {
  SosHoldController({
    required this.onActivated,
    this.onTick,
    this.onCancelled,
    this.onReset,
  });

  /// Fired once the button has been held for the full [holdSeconds].
  final VoidCallback onActivated;

  /// Fired on each countdown tick with the remaining seconds.
  final ValueChanged<int>? onTick;

  /// Fired when a hold that got under way is released or cancelled before
  /// activation.
  final VoidCallback? onCancelled;

  /// Fired when the user resets an activation.
  final VoidCallback? onReset;

  /// Existing SOS hold duration.
  static const int holdSeconds = 5;

  /// Travel beyond which the hold counts as abandoned.
  ///
  /// Slightly larger than the platform touch slop so ordinary finger wobble
  /// while holding does not cancel an intentional press.
  static const double cancelSlop = 28;

  /// How long a press must last before releasing it counts as a cancelled hold.
  ///
  /// Now that the whole screen accepts the hold, every tap on Back, a contact
  /// card or Call would otherwise be treated as an abandoned SOS hold and
  /// announce "SOS cancelled". A press shorter than this is just a tap, so it
  /// resets silently and leaves the control it landed on untouched.
  static const Duration meaningfulHold = Duration(milliseconds: 500);

  Timer? _timer;
  Timer? _intentTimer;
  bool _heldLongEnough = false;
  int? _pointer;
  Offset? _origin;
  SosHoldPhase _phase = SosHoldPhase.ready;
  int _remaining = holdSeconds;

  SosHoldPhase get phase => _phase;
  int get secondsRemaining => _remaining;
  bool get isCountdown => _phase == SosHoldPhase.countdown;
  bool get isActivated => _phase == SosHoldPhase.activated;

  /// 0..1 fill for the progress ring.
  double get progress => switch (_phase) {
    SosHoldPhase.ready => 0.0,
    SosHoldPhase.countdown => (holdSeconds - _remaining) / holdSeconds,
    SosHoldPhase.activated => 1.0,
  };

  void pointerDown(PointerDownEvent event) {
    // One finger owns the hold. A second finger must not restart the countdown
    // or take over the pointer that is already holding.
    if (_pointer != null) return;
    if (_phase == SosHoldPhase.activated) return;
    _pointer = event.pointer;
    _origin = event.position;
    _beginIntentWindow();
    _startCountdown();
  }

  void pointerMove(PointerMoveEvent event) {
    if (_pointer != event.pointer) return;
    final Offset? origin = _origin;
    if (origin == null) return;
    // Sliding well clear of the press is a cancellation, not a hold. Without
    // this a finger that drifts away still runs the countdown to activation.
    if ((event.position - origin).distance > cancelSlop) {
      _releasePointer();
      _cancelCountdown();
    }
  }

  void pointerUp(PointerEvent event) {
    // Ignore pointers that never owned the hold.
    if (_pointer != event.pointer) return;
    final bool meaningful = _heldLongEnough;
    _releasePointer();
    if (_phase != SosHoldPhase.countdown) return;
    _cancelCountdown(announce: meaningful);
  }

  /// Opens the window in which a press counts as a real hold attempt.
  ///
  /// Once [meaningfulHold] has elapsed the press is no longer "just a tap", so
  /// abandoning it afterwards deserves the existing cancel feedback. A timer is
  /// used rather than measuring elapsed time directly so the window follows the
  /// same clock the countdown does.
  void _beginIntentWindow() {
    _intentTimer?.cancel();
    _heldLongEnough = false;
    _intentTimer = Timer(meaningfulHold, () {
      _heldLongEnough = true;
    });
  }

  /// Called on pointer cancel as well, where the intent is always to abandon.
  void pointerCancel(PointerEvent event) => pointerUp(event);

  void reset() {
    if (_phase != SosHoldPhase.activated) return;
    _releasePointer();
    _setPhase(SosHoldPhase.ready);
    onReset?.call();
  }

  void _startCountdown() {
    if (_phase != SosHoldPhase.ready) return;
    _setPhase(SosHoldPhase.countdown);
    onTick?.call(holdSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      final int next = _remaining - 1;
      if (next <= 0) {
        timer.cancel();
        _timer = null;
        // Releasing the pointer here is what makes activation fire exactly
        // once: any further up/cancel from this finger is ignored.
        _releasePointer();
        _setPhase(SosHoldPhase.activated);
        onActivated();
        return;
      }
      _remaining = next;
      notifyListeners();
      onTick?.call(next);
    });
  }

  void _cancelCountdown({bool announce = true}) {
    if (_phase != SosHoldPhase.countdown) {
      _heldLongEnough = false;
      return;
    }
    _timer?.cancel();
    _timer = null;
    _heldLongEnough = false;
    _setPhase(SosHoldPhase.ready);
    if (announce) onCancelled?.call();
  }

  void _setPhase(SosHoldPhase phase) {
    _phase = phase;
    _remaining = phase == SosHoldPhase.ready ? holdSeconds : _remaining;
    if (phase == SosHoldPhase.activated) _remaining = 0;
    notifyListeners();
  }

  void _releasePointer() {
    _pointer = null;
    _origin = null;
    _intentTimer?.cancel();
    _intentTimer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _intentTimer?.cancel();
    _intentTimer = null;
    super.dispose();
  }
}

/// A large press-and-hold SOS control with a polished animated design.
///
/// The button owns no logic of its own: the hold, the countdown and the
/// activation all live in the shared [SosHoldController], which the SOS screen
/// drives from its own full-surface Listener. Holding the button and holding
/// anywhere else on the screen are therefore literally the same code path.
class EmergencySOSButton extends StatefulWidget {
  const EmergencySOSButton({
    super.key,
    required this.controller,
  });

  final SosHoldController controller;

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

  SosHoldController get _hold => widget.controller;

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
    _pulse.dispose();
    super.dispose();
  }

  double get _pulseAmplitude {
    switch (_hold.phase) {
      case SosHoldPhase.ready:
        return 0.018;
      case SosHoldPhase.countdown:
        return 0.045;
      case SosHoldPhase.activated:
        return 0.06;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Rebuild on the pulse AND on any hold-state change.
      listenable: Listenable.merge([_pulse, _hold]),
      builder: (context, _) {
        final bool isCountdown = _hold.isCountdown;
        final bool isActivated = _hold.isActivated;
        final double progress = _hold.progress;

        final label = isActivated
            ? 'SOS Activated'
            : isCountdown
            ? 'Keep holding... releasing cancels'
            : 'Press & hold for ${SosHoldController.holdSeconds} seconds';
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
                  : 'SOS button. Press and hold for '
                        '${SosHoldController.holdSeconds} seconds to activate.',
              toggled: isActivated,
              button: true,
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
                                '${_hold.secondsRemaining}',
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
                      onTap: _hold.reset,
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
                            Icon(
                              Icons.refresh_rounded,
                              size: 16,
                              color: _mainRed,
                            ),
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
      },
    );
  }
}