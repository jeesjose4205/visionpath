import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/emergency_screen.dart';

/// Route name used for the SOS/Emergency screen so the navigator observer
/// can reliably recognise when the user is already on it.
const String kSosRouteName = '/emergency';

/// Tracks whether the SOS screen is currently the top route, so the global
/// gesture cannot push a second copy of it.
class SosRouteObserver extends NavigatorObserver {
  bool _emergencyOnTop = false;

  bool get emergencyOnTop => _emergencyOnTop;

  void _update(Route<dynamic>? route) {
    _emergencyOnTop = route?.settings.name == kSosRouteName;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _update(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(previousRoute);
  }
}

/// Global SOS gesture layer wrapping the root [Navigator].
///
/// A deliberate THREE-finger swipe starting within the top gesture zone and
/// travelling downwards opens the existing [EmergencyScreen] from the top of any
/// screen.
///
/// Three fingers are required, the drag must start near the top edge and must
/// travel a quarter of the screen height. An earlier version of this layer used
/// a one-finger bottom-to-top swipe, which was far too easy to fire by accident
/// while scrolling or reaching for a control, so the finger count and the
/// direction were both tightened.
///
/// The gesture is observed with a raw [Listener] (never competing in the
/// gesture arena with the app's own recognisers) and the SOS route is pushed the
/// moment the threshold is crossed, with no transition of any kind.
class SosGestureOverlay extends StatefulWidget {
  const SosGestureOverlay({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.observer,
    this.zoneHeight = 140,
  });

  /// Exactly this many fingers must be down for the gesture to be recognised.
  ///
  /// Two fingers is deliberately not enough: it is easy to rest a second finger
  /// on the screen while scrolling, and an emergency must not fire from that.
  static const int requiredFingers = 3;

  /// True from the moment an SOS drag begins until shortly after it ends.
  ///
  /// The SOS gesture layer observes pointers with a raw [Listener], so it never
  /// competes in the gesture arena: every screen underneath ALSO receives the
  /// same pointer stream. Without this gate, a screen's own horizontal-swipe
  /// handler can resolve on the same pointer sequence and push ITS page on top
  /// of the Emergency screen. Screens check this flag in their swipe handlers and
  /// ignore the gesture while it is set.
  static bool sosSwipeActive = false;

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final SosRouteObserver observer;

  /// Height (logical px) of the top gesture zone where the gesture must begin.
  /// Large enough to be reachable without covering the whole screen.
  final double zoneHeight;

  @override
  State<SosGestureOverlay> createState() => _SosGestureOverlayState();
}

class _SosGestureOverlayState extends State<SosGestureOverlay> {
  /// Every pointer currently down anywhere on the screen.
  ///
  /// Counted rather than inferred from a single pointer so a stray extra finger
  /// (a resting palm, a second hand) can veto the gesture instead of quietly
  /// completing it.
  final Set<int> _pointers = <int>{};

  /// The subset of [_pointers] whose press began inside the top zone. All
  /// [SosGestureOverlay.requiredFingers] of them must be in here for the gesture
  /// to be recognised.
  final Set<int> _zonePointers = <int>{};

  /// Latest known position per pointer, used to track the average finger
  /// position. [PointerMoveEvent.delta] alone cannot be averaged meaningfully
  /// because the three fingers do not necessarily move together.
  final Map<int, Offset> _positions = <int, Offset>{};

  bool _sessionActive = false;
  Offset _origin = Offset.zero;
  double _travel = 0;
  double _screenHeight = 0;

  /// Watchdog for a pointer session that never terminates (a competing
  /// recognizer can claim the pointer and swallow the up/cancel). Stops a
  /// half-finished gesture from leaving stale pointer bookkeeping behind.
  Timer? _watchdog;

  /// The SOS gesture fires once the downward drag has covered a quarter of the
  /// screen height. Combined with three fingers starting at the top edge, that
  /// is a long way from any accidental gesture.
  static const double _openProgress = 0.25;

  static const Duration _watchdogTimeout = Duration(milliseconds: 2000);

  /// Minimum downward travel before the gesture is considered to have started
  /// (ignores the initial jitter of putting three fingers down).
  static const double _startThreshold = 12;

  /// Horizontal deviation beyond which the gesture is treated as a regular
  /// horizontal swipe and handed over to the app's own recognizers.
  static const double _dropSlop = 24;

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_watchdogTimeout, () {
      if (!_sessionActive || !mounted) return;
      debugPrint('SOS gesture watchdog: session stalled with fingers down.');
      // Never yank the UI mid-hold: simply end the session so the pointer
      // handling loop restarts cleanly. Whatever is on screen is resolved by
      // the next pointer-down/up.
      _sessionActive = false;
    });
  }

  void _clearWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  /// Mean position of the fingers participating in the gesture.
  Offset _averagePosition() {
    if (_zonePointers.isEmpty) return _origin;
    double x = 0;
    double y = 0;
    var count = 0;
    for (final int pointer in _zonePointers) {
      final Offset? position = _positions[pointer];
      if (position == null) continue;
      x += position.dx;
      y += position.dy;
      count++;
    }
    if (count == 0) return _origin;
    return Offset(x / count, y / count);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.observer.emergencyOnTop) return;

    _pointers.add(event.pointer);
    _positions[event.pointer] = event.position;

    final height = MediaQuery.sizeOf(context).height;
    if (event.position.dy <= widget.zoneHeight) {
      _zonePointers.add(event.pointer);
    }

    // A fourth finger means this is not the deliberate three-finger gesture.
    if (_pointers.length > SosGestureOverlay.requiredFingers) {
      _abortSession();
      return;
    }

    if (_sessionActive) {
      _startWatchdog();
      return;
    }

    // The session begins the moment exactly three fingers are down, and only
    // when all three of them started inside the top zone. Starting two fingers
    // somewhere else and then adding a third near the top never qualifies.
    if (_pointers.length == SosGestureOverlay.requiredFingers &&
        _zonePointers.length == SosGestureOverlay.requiredFingers) {
      _startSession(height);
    }
  }

  void _startSession(double height) {
    // Always start a fresh session: if a previous pointer-up/cancel was never
    // delivered, stale bookkeeping must never permanently block the gesture.
    SosGestureOverlay.sosSwipeActive = true;
    _screenHeight = height;
    _origin = _averagePosition();
    _travel = 0;
    _sessionActive = true;
    _startWatchdog();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_positions.containsKey(event.pointer)) {
      _positions[event.pointer] = event.position;
    }
    if (!_sessionActive) return;

    // Any progress (or hover) resets the stall watchdog.
    _startWatchdog();

    // A finger leaving or joining mid-gesture changes the shape of it, so the
    // gesture is abandoned rather than completed with a different count.
    if (_pointers.length != SosGestureOverlay.requiredFingers ||
        _zonePointers.length != SosGestureOverlay.requiredFingers) {
      _abortSession();
      return;
    }

    final Offset delta = _averagePosition() - _origin;
    final double downward = delta.dy;
    final double horizontal = delta.dx.abs();

    // A mostly-sideways drag belongs to the app's own carousel swipes.
    if (horizontal > _dropSlop && horizontal > downward.abs()) {
      _abortSession();
      return;
    }

    // Upward is the old, far-too-easy gesture and must never open anything.
    if (downward < -_startThreshold) {
      _abortSession();
      return;
    }

    if (downward < _startThreshold) return;

    _travel = downward.clamp(0.0, _screenHeight);

    // The SOS screen appears the instant the threshold is crossed. The gesture
    // is unambiguous by this point (three fingers, from the top edge, a quarter
    // of the screen down), so waiting for the fingers to lift would only delay
    // an emergency.
    if (_travel / _screenHeight >= _openProgress) {
      _openSos();
    }
  }

  /// A finger lifting. Nothing is decided here any more: the route was pushed
  /// mid-drag, so this only tidies up the pointer bookkeeping and the gate.
  void _onPointerUp(PointerUpEvent event) {
    _resolvePointer(event);
  }

  /// A cancelled pointer stream means the platform took the sequence away —
  /// another recognizer won the arena, the app was backgrounded, a system sheet
  /// was pulled down. Any in-flight session is abandoned.
  void _onPointerCancel(PointerCancelEvent event) {
    _resolvePointer(event, cancelled: true);
  }

  void _resolvePointer(PointerEvent event, {bool cancelled = false}) {
    final bool wasTracked = _pointers.remove(event.pointer);
    _positions.remove(event.pointer);
    _zonePointers.remove(event.pointer);
    if (!wasTracked) return;

    _clearWatchdog();
    _sessionActive = false;

    // Deliberately NOT releasing the carousel gate before the fingers are off
    // the glass: the screen underneath is mid-teardown and must not be allowed
    // to resolve a swipe on the tail of the SOS gesture.
    _releaseSwipeGate();
  }

  /// Drops the session mid-gesture without opening anything.
  ///
  /// The swipe gate is deliberately left up: the fingers are still on the
  /// screen, so the carousel underneath must stay suppressed until they lift.
  void _abortSession() {
    if (!_sessionActive) return;
    _clearWatchdog();
    _sessionActive = false;
  }

  /// Clears [SosGestureOverlay.sosSwipeActive] after a short delay.
  ///
  /// The gate must stay up through the whole pointer-up dispatch, because a
  /// screen's own swipe recognizer resolves and pushes in the SAME event turn
  /// (after the overlay's raw listener). Clearing here is deferred so that late
  /// cross-screen navigations are still suppressed, while normal swipes resume
  /// right away.
  void _releaseSwipeGate() {
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      SosGestureOverlay.sosSwipeActive = false;
    });
  }

  /// Pushes the existing EmergencyScreen with no transition of any kind.
  ///
  /// No slide, fade, scale or bottom-sheet: the SOS screen simply appears. The
  /// route name is kept so [SosRouteObserver] can still recognise the screen and
  /// refuse to stack a second copy of it.
  void _openSos() {
    if (_sessionActive) {
      _sessionActive = false;
      _clearWatchdog();
    }
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null || widget.observer.emergencyOnTop) return;

    HapticFeedback.heavyImpact();
    navigator.push(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: kSosRouteName),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const EmergencyScreen(),
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) => child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A plain Listener with no overlay on top: there is no preview panel and no
    // transition, so nothing here may intercept or defer a hit test.
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}