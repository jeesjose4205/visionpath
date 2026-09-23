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
/// A deliberate bottom-to-top swipe starting within the bottom gesture zone
/// reveals the existing [EmergencyScreen] from the bottom of any screen.
///
/// The gesture is observed with a raw [Listener] (never competing in the
/// gesture arena with the app's own recognisers): pointer events drive a
/// purely visual preview panel that follows the finger, and the real SOS
/// route is only pushed once the finger lifts and the swipe qualifies. This
/// avoids pushing a route mid-gesture, which the platform cancels.
class SosGestureOverlay extends StatefulWidget {
  const SosGestureOverlay({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.observer,
    this.zoneHeight = 140,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final SosRouteObserver observer;

  /// Height (logical px) of the bottom gesture zone where the gesture must
  /// begin. Large enough for one-handed/accessibility use without covering
  /// the whole screen.
  final double zoneHeight;

  @override
  State<SosGestureOverlay> createState() => _SosGestureOverlayState();
}

class _SosGestureOverlayState extends State<SosGestureOverlay>
    with SingleTickerProviderStateMixin {
  /// Revealed panel height (0 = hidden, screenHeight = full). Visual only.
  final ValueNotifier<double> _sheet = ValueNotifier<double>(0);
  AnimationController? _anim;

  bool _sessionActive = false;
  double _startX = 0;
  double _startY = 0;
  double _dragReveal = 0;
  double _screenHeight = 0;

  /// Recent pointer samples used to estimate fling velocity at pointer-up
  /// (raw pointer events carry no velocity).
  final List<({Duration t, double y})> _moves = [];

  // Opening is deliberately forgiving so a "normal" swipe works (not just a
  // full-height fling): 35% of the screen, or 12% with a quick fling.
  static const double _openProgress = 0.35;
  static const double _fastProgress = 0.12;
  static const double _fastVelocity = 650;

  /// Minimum upward travel before the preview panel appears (ignores taps).
  static const double _startThreshold = 12;

  /// Horizontal deviation beyond which the gesture is treated as a regular
  /// horizontal swipe and handed over to the app's own recognizers.
  static const double _dropSlop = 24;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_schedulePanelRebuild);
  }

  void _schedulePanelRebuild() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _anim?.dispose();
    _sheet.dispose();
    super.dispose();
  }

  void _recordMove(Duration t, double y) {
    _moves.add((t: t, y: y));
    final cutoff = t - const Duration(milliseconds: 120);
    while (_moves.isNotEmpty && _moves.first.t < cutoff) {
      _moves.removeAt(0);
    }
    if (_moves.length > 8) _moves.removeAt(0);
  }

  /// Upward speed (px/s) at pointer-up, estimated from the recent samples.
  double _flingVelocity(Duration t, double y) {
    _recordMove(t, y);
    if (_moves.length < 2) return 0;
    final first = _moves.first;
    final last = _moves.last;
    final dtMs = (last.t - first.t).inMicroseconds;
    if (dtMs <= 0) return 0;
    return (first.y - last.y) / (dtMs / 1e6);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_sessionActive || widget.observer.emergencyOnTop) return;
    final height = MediaQuery.sizeOf(context).height;
    final inZone = event.position.dy >= height - widget.zoneHeight;
    if (!inZone) return;

    _screenHeight = height;
    _startX = event.position.dx;
    _startY = event.position.dy;
    _dragReveal = 0;
    _moves.clear();
    _sessionActive = true;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_sessionActive) return;

    _recordMove(event.timeStamp, event.position.dy);

    final upward = _startY - event.position.dy;
    final horizontal = (event.position.dx - _startX).abs();

    // A mostly-horizontal drag from inside the zone belongs to the app's own
    // horizontal swipe handlers; drop the SOS session without opening.
    if (horizontal > upward.abs() && horizontal > _dropSlop) {
      _sessionActive = false;
      return;
    }

    if (upward < _startThreshold) return;

    _dragReveal = upward.clamp(0.0, _screenHeight);
    _sheet.value = _dragReveal;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_sessionActive) return;

    final upVelocity = _flingVelocity(event.timeStamp, event.position.dy);
    final progress = _screenHeight <= 0 ? 0.0 : _dragReveal / _screenHeight;
    final shouldOpen = progress >= _openProgress ||
        (progress >= _fastProgress && upVelocity >= _fastVelocity);

    _sessionActive = false;

    if (shouldOpen) {
      _openSos();
    } else {
      _snapBack();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (!_sessionActive) return;
    _sessionActive = false;
    _snapBack();
  }

  /// Pushes the real EmergencyScreen (only after the finger has lifted) with
  /// a slide-up transition, then hides the preview panel.
  void _openSos() {
    HapticFeedback.heavyImpact();
    _sheet.value = 0;
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null || widget.observer.emergencyOnTop) return;

    final route = PageRouteBuilder<void>(
      settings: const RouteSettings(name: kSosRouteName),
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const EmergencyScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.8, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    navigator.push(route);
  }

  /// Animates the preview panel back down after a cancelled/non-qualifying
  /// swipe.
  void _snapBack() {
    if (_sheet.value == 0) return;
    final from = _sheet.value;
    _anim?.dispose();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _anim!.addListener(() {
      _sheet.value =
          from * (1 - Curves.easeOutCubic.transform(_anim!.value));
    });
    _anim!.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          // Visual-only preview panel that follows the finger. IgnorePointer
          // so it never blocks the app underneath (hit tests pass straight
          // through to the Navigator).
          if (_sheet.value > 0)
            IgnorePointer(
              child: _SosPreview(sheet: _sheet, screenHeight: _screenHeight),
            ),
        ],
      ),
    );
  }
}

/// Lightweight drag-follow preview: a scrim plus a rounded panel that slides
/// up with the finger. Purely cosmetic — the real EmergencyScreen appears via
/// the route pushed on release.
class _SosPreview extends StatelessWidget {
  const _SosPreview({required this.sheet, required this.screenHeight});

  final ValueNotifier<double> sheet;
  final double screenHeight;

  @override
  Widget build(BuildContext context) {
    final height = screenHeight <= 0 ? MediaQuery.sizeOf(context).height : screenHeight;
    final reveal = sheet.value.clamp(0.0, height);
    final progress = height <= 0 ? 0.0 : reveal / height;
    final panel = height * 0.65;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Deepening scrim; never fully black.
        ColoredBox(color: Colors.black.withValues(alpha: 0.30 * progress)),
        // Rounded panel peeking up from the bottom.
        Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: panel,
            width: double.infinity,
            child: Transform.translate(
              offset: Offset(0, height - reveal),
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24 * (1 - progress)),
                ),
                child: ColoredBox(
                  color: const Color(0xFFF4F6FB),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.emergency, color: Color(0xFFD02020), size: 44),
                        SizedBox(height: 12),
                        Text(
                          'Emergency',
                          style: TextStyle(
                            color: Color(0xFF15233D),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}