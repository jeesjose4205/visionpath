import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/screens/emergency_screen.dart';
import 'package:visionpath/widgets/sos_gesture.dart';

/// The global SOS gesture is a deliberate three-finger swipe from the TOP of
/// the screen downwards. These tests drive the real [SosGestureOverlay] with
/// real multi-touch pointer streams, because every safety property of the
/// gesture (exact finger count, direction, distance) lives in the raw pointer
/// bookkeeping that a synthesised single-finger drag would never exercise.
void main() {
  // 1200x2400 at dpr 3.0 => a 400x800 logical screen.
  const double screenHeight = 800;

  /// Just inside the top gesture zone (zoneHeight defaults to 140).
  const double zoneY = 60;

  /// The gate is released on a timer, so it must not leak between tests.
  tearDown(() => SosGestureOverlay.sosSwipeActive = false);

  void setPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<SosRouteObserver> pumpShell(
    WidgetTester tester, {
    Widget? home,
  }) async {
    final navKey = GlobalKey<NavigatorState>();
    final observer = SosRouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [observer],
        home: home ?? const Scaffold(body: Center(child: Text('content'))),
        builder: (context, child) => SosGestureOverlay(
          navigatorKey: navKey,
          observer: observer,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
    return observer;
  }

  /// Presses [fingers] fingers down near [startY], drags them all by [delta],
  /// then lifts them.
  ///
  /// Returns without lifting when [release] is false, so a test can inspect the
  /// mid-gesture state.
  Future<void> threeFingerSwipe(
    WidgetTester tester, {
    required int fingers,
    required double startY,
    required Offset delta,
    int steps = 6,
    bool release = true,
    List<double> startXs = const <double>[100, 200, 300],
  }) async {
    final List<TestGesture> gestures = <TestGesture>[];
    for (int i = 0; i < fingers; i++) {
      final TestGesture g =
          await tester.createGesture(pointer: 40 + i);
      await g.down(Offset(startXs[i % startXs.length], startY));
      gestures.add(g);
    }
    await tester.pump();

    for (int s = 0; s < steps; s++) {
      for (final TestGesture g in gestures) {
        await g.moveBy(delta / steps.toDouble());
      }
      await tester.pump();
    }

    if (release) {
      for (final TestGesture g in gestures) {
        await g.up();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
  }

  /// Downward travel that crosses the gate: 25% of the screen height.
  const double gate = screenHeight * 0.25;

  /// Comfortably past the gate.
  const double qualifyingTravel = gate + 60;

  // ---------------------------------------------------------------------
  // A. Global SOS gesture
  // ---------------------------------------------------------------------

  testWidgets('A1 one finger top-to-bottom does NOT open SOS', (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    await threeFingerSwipe(
      tester,
      fingers: 1,
      startY: zoneY,
      delta: Offset(0, qualifyingTravel),
    );

    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('A2 two fingers top-to-bottom does NOT open SOS', (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    await threeFingerSwipe(
      tester,
      fingers: 2,
      startY: zoneY,
      delta: Offset(0, qualifyingTravel),
    );

    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('A3 three fingers top-to-bottom opens SOS', (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(0, qualifyingTravel),
    );

    expect(find.byType(EmergencyScreen), findsOneWidget);
  });

  testWidgets('A4 three fingers bottom-to-top does NOT open SOS',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    // The old one-finger gesture. Three fingers must not resurrect it.
    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: 760,
      delta: Offset(0, -qualifyingTravel),
    );

    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('A5 three fingers dragging UP from the zone do NOT open SOS',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    // Started legally in the top zone but pulled the wrong way.
    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(0, -qualifyingTravel),
    );

    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('A6 three fingers swiping horizontally do NOT open SOS',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(qualifyingTravel, 0),
    );

    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('A7 a short three-finger downward drag does NOT open SOS',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    // Well under the 25% gate.
    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(0, 90),
    );

    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('A8 a long three-finger downward drag opens SOS',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(0, screenHeight * 0.6),
    );

    expect(find.byType(EmergencyScreen), findsOneWidget);
  });

  testWidgets('A9 four fingers down at once do NOT open SOS', (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    // A resting extra finger from the start can never form the gesture.
    await threeFingerSwipe(
      tester,
      fingers: 4,
      startY: zoneY,
      delta: Offset(0, qualifyingTravel),
    );

    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('A9b a fourth finger arriving mid-gesture aborts it',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    // Three fingers drag most of the way, stopping SHORT of the gate...
    final List<TestGesture> three = <TestGesture>[];
    for (int i = 0; i < 3; i++) {
      final TestGesture g = await tester.createGesture(pointer: 70 + i);
      await g.down(Offset(100 + i * 100, zoneY));
      three.add(g);
    }
    await tester.pump();
    for (int s = 0; s < 6; s++) {
      for (final TestGesture g in three) {
        await g.moveBy(const Offset(0, (gate - 60) / 6));
      }
      await tester.pump();
    }
    expect(find.byType(EmergencyScreen), findsNothing,
        reason: 'precondition: not past the gate yet');

    // ...and only THEN does a fourth finger touch down. The gesture must be
    // abandoned, so the continued drag below crosses the gate with a live
    // session that must already be dead.
    final TestGesture fourth = await tester.createGesture(pointer: 90);
    await fourth.down(const Offset(350, zoneY));
    await tester.pump();

    for (int s = 0; s < 6; s++) {
      for (final TestGesture g in three) {
        await g.moveBy(const Offset(0, 120 / 6));
      }
      await tester.pump();
    }

    for (final TestGesture g in three) {
      await g.up();
    }
    await fourth.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('A10 three fingers starting below the top zone do NOT open SOS',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    // Well past zoneHeight downwards, so the session never starts.
    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: 500,
      delta: Offset(0, 240),
    );

    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('A11 two fingers in the zone plus a third outside do NOT open SOS',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    final TestGesture a = await tester.createGesture(pointer: 1);
    final TestGesture b = await tester.createGesture(pointer: 2);
    final TestGesture c = await tester.createGesture(pointer: 3);
    await a.down(const Offset(100, zoneY));
    await b.down(const Offset(200, zoneY));
    await c.down(const Offset(300, 500));
    await tester.pump();

    for (int s = 0; s < 6; s++) {
      await a.moveBy(const Offset(0, qualifyingTravel / 6));
      await b.moveBy(const Offset(0, qualifyingTravel / 6));
      await c.moveBy(const Offset(0, qualifyingTravel / 6));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await c.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('A12 lifting one finger before the threshold cancels the gesture',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    final TestGesture a = await tester.createGesture(pointer: 1);
    final TestGesture b = await tester.createGesture(pointer: 2);
    final TestGesture c = await tester.createGesture(pointer: 3);
    await a.down(const Offset(100, zoneY));
    await b.down(const Offset(200, zoneY));
    await c.down(const Offset(300, zoneY));
    await tester.pump();

    // Barely any travel, then one finger leaves.
    await a.moveBy(const Offset(0, 30));
    await b.moveBy(const Offset(0, 30));
    await c.moveBy(const Offset(0, 30));
    await tester.pump();
    await a.up();
    await tester.pump();

    // The survivors drag all the way down, but the gesture is already dead.
    await b.moveBy(const Offset(0, qualifyingTravel));
    await c.moveBy(const Offset(0, qualifyingTravel));
    await tester.pump();
    await b.up();
    await c.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('A20 starting the wrong way then dragging down does NOT open SOS',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    // Three fingers go down legally in the zone but travel UPWARDS first, then
    // reverse and travel well past the qualifying distance measured from the
    // original touch-down point. That is not a deliberate SOS gesture: the hand
    // started in the wrong direction, so the session must already be dead.
    final List<TestGesture> gestures = <TestGesture>[];
    for (int i = 0; i < 3; i++) {
      final TestGesture g = await tester.createGesture(pointer: 60 + i);
      await g.down(Offset(100 + i * 100, zoneY));
      gestures.add(g);
    }
    await tester.pump();

    for (final TestGesture g in gestures) {
      await g.moveBy(const Offset(0, -50));
    }
    await tester.pump();

    // Back downwards, ending 260px below the original touch-down point.
    for (int s = 0; s < 6; s++) {
      for (final TestGesture g in gestures) {
        await g.moveBy(const Offset(0, (260.0 + 50) / 6));
      }
      await tester.pump();
    }
    for (final TestGesture g in gestures) {
      await g.up();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(EmergencyScreen), findsNothing);
  });

testWidgets('A21 SOS opens IMMEDIATELY at the threshold, before any finger lifts',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    final List<TestGesture> gestures = <TestGesture>[];
    for (int i = 0; i < 3; i++) {
      final TestGesture g = await tester.createGesture(pointer: 30 + i);
      await g.down(Offset(100 + i * 100, zoneY));
      gestures.add(g);
    }
    await tester.pump();

    // Stop short of the gate: nothing yet.
    for (final TestGesture g in gestures) {
      await g.moveBy(const Offset(0, gate - 40));
    }
    await tester.pump();
    expect(find.byType(EmergencyScreen), findsNothing);

    // Cross the gate and rebuild, WITHOUT lifting any finger.
    for (final TestGesture g in gestures) {
      await g.moveBy(const Offset(0, 60));
    }
    await tester.pump();

    expect(
      find.byType(EmergencyScreen),
      findsOneWidget,
      reason: 'SOS must appear the moment the threshold is crossed',
    );

    for (final TestGesture g in gestures) {
      await g.up();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('A22 the SOS route has no transition animation at all',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(0, qualifyingTravel),
    );
    expect(find.byType(EmergencyScreen), findsOneWidget);

    final ModalRoute<dynamic>? route =
        ModalRoute.of(tester.element(find.byType(EmergencyScreen)));

    // No slide, fade, scale or bottom-sheet: the route is already fully
    // arrived, with nothing left to animate.
    expect(route, isNotNull);
    expect(route!.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    expect(route.animation?.value, 1.0);
  });

  testWidgets('A14 SOS does not stack a second route when already open',
      (tester) async {
    setPhone(tester);
    final SosRouteObserver observer = await pumpShell(tester);

    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(0, qualifyingTravel),
    );
    expect(find.byType(EmergencyScreen), findsOneWidget);
    expect(observer.emergencyOnTop, isTrue);

    // A second gesture on top of the already-open SOS screen must be ignored.
    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(0, qualifyingTravel),
    );
    expect(find.byType(EmergencyScreen), findsOneWidget);
  });

  testWidgets('A15 the gesture does not fight a competing horizontal detector',
      (tester) async {
    setPhone(tester);
    final navKey = GlobalKey<NavigatorState>();
    final observer = SosRouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [observer],
        home: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {},
          onHorizontalDragUpdate: (_) {},
          onHorizontalDragEnd: (_) {
            if (SosGestureOverlay.sosSwipeActive) return;
            navKey.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('WRONG SCREEN')),
                ),
              ),
            );
          },
          child: const Scaffold(body: Center(child: Text('content'))),
        ),
        builder: (context, child) => SosGestureOverlay(
          navigatorKey: navKey,
          observer: observer,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );

    // Slightly diagonal three-finger drag: enough downward travel to qualify
    // and enough sideways drift for a horizontal recognizer to want it too.
    final List<TestGesture> gestures = <TestGesture>[];
    for (int i = 0; i < 3; i++) {
      final TestGesture g = await tester.createGesture(pointer: 10 + i);
      await g.down(Offset(80 + i * 60, zoneY));
      gestures.add(g);
    }
    await tester.pump();
    for (int s = 0; s < 6; s++) {
      for (final TestGesture g in gestures) {
        await g.moveBy(const Offset(6, qualifyingTravel / 6));
      }
      await tester.pump();
    }
    for (final TestGesture g in gestures) {
      await g.up();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(EmergencyScreen), findsOneWidget);
    expect(find.text('WRONG SCREEN'), findsNothing);
  });

  testWidgets('A16 returning from SOS restores the previous screen',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(0, qualifyingTravel),
    );
    expect(find.byType(EmergencyScreen), findsOneWidget);

    final NavigatorState nav =
        Navigator.of(tester.element(find.byType(EmergencyScreen)));
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(EmergencyScreen), findsNothing);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('A17 a one-finger carousel swipe still works while SOS is armed',
      (tester) async {
    setPhone(tester);
    final navKey = GlobalKey<NavigatorState>();
    final observer = SosRouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [observer],
        home: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {},
          onHorizontalDragUpdate: (_) {},
          onHorizontalDragEnd: (_) {
            if (SosGestureOverlay.sosSwipeActive) return;
            navKey.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('NEXT PAGE')),
                ),
              ),
            );
          },
          child: const Scaffold(body: Center(child: Text('content'))),
        ),
        builder: (context, child) => SosGestureOverlay(
          navigatorKey: navKey,
          observer: observer,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );

    // An ordinary single-finger horizontal swipe must be untouched by the SOS
    // layer: one finger never arms the gate.
    final TestGesture g = await tester.createGesture();
    await g.down(const Offset(320, 400));
    await tester.pump();
    for (int s = 0; s < 5; s++) {
      await g.moveBy(const Offset(-40, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('NEXT PAGE'), findsOneWidget);
    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('A18 no stuck gesture state after an interrupted gesture',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    // Cancel mid-drag rather than lifting cleanly.
    final List<TestGesture> gestures = <TestGesture>[];
    for (int i = 0; i < 3; i++) {
      final TestGesture g = await tester.createGesture(pointer: 20 + i);
      await g.down(Offset(100 + i * 100, zoneY));
      gestures.add(g);
    }
    await tester.pump();
    // Stay below the gate, then cancel rather than lifting cleanly. The
    // platform taking the gesture away must never be read as completing it.
    for (int s = 0; s < 2; s++) {
      for (final TestGesture g in gestures) {
        await g.moveBy(const Offset(0, 40));
      }
      await tester.pump();
    }
    for (final TestGesture g in gestures) {
      await g.cancel();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // The overlay must be fully reset: nothing opened, and the very next clean
    // gesture behaves normally, so no stale pointer bookkeeping survived.
    expect(find.byType(EmergencyScreen), findsNothing,
        reason: 'a cancelled pointer stream must never open SOS');

    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(0, qualifyingTravel),
    );
    expect(find.byType(EmergencyScreen), findsOneWidget);
  });

  testWidgets('A19 the gate is cleared so ordinary swipes resume afterwards',
      (tester) async {
    setPhone(tester);
    final navKey = GlobalKey<NavigatorState>();
    final observer = SosRouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [observer],
        home: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (_) {
              if (SosGestureOverlay.sosSwipeActive) return;
              navKey.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('NEXT PAGE')),
                  ),
                ),
              );
            },
            child: const Center(child: Text('content')),
          ),
        ),
        builder: (context, child) => SosGestureOverlay(
          navigatorKey: navKey,
          observer: observer,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );

    // A short three-finger drag arms and then disarms the gate.
    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(0, 90),
    );
    expect(SosGestureOverlay.sosSwipeActive, isFalse);

    // The next ordinary swipe must work, proving the gate did not stick.
    final TestGesture g = await tester.createGesture();
    await g.down(const Offset(320, 400));
    await tester.pump();
    for (int s = 0; s < 5; s++) {
      await g.moveBy(const Offset(-40, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('NEXT PAGE'), findsOneWidget);
  });

  // ---------------------------------------------------------------------
  // B. From every major screen
  //
  // The overlay is installed once, above the Navigator, by MaterialApp.builder
  // in main.dart. Each case below pushes a real screen and repeats the gesture,
  // proving the layer covers routes rather than only the initial route.
  // ---------------------------------------------------------------------

  Future<void> expectOpensFromScreen(
    WidgetTester tester,
    String label,
    Widget screen,
  ) async {
    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(0, qualifyingTravel),
    );
    expect(
      find.byType(EmergencyScreen),
      findsOneWidget,
      reason: 'three-finger swipe must open SOS from $label',
    );

    // Return to the originating screen so the next case starts clean.
    final NavigatorState nav =
        Navigator.of(tester.element(find.byType(EmergencyScreen)));
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(screen.runtimeType), findsOneWidget);
  }

  testWidgets('B1 three-finger swipe opens SOS from Home', (tester) async {
    setPhone(tester);
    await pumpShell(tester);
    await expectOpensFromScreen(
      tester,
      'Home',
      const Scaffold(body: Center(child: Text('content'))),
    );
  });

  testWidgets('B2 three-finger swipe opens SOS from a pushed screen',
      (tester) async {
    setPhone(tester);
    final navKey = GlobalKey<NavigatorState>();
    final observer = SosRouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [observer],
        home: const Scaffold(body: Center(child: Text('HOME'))),
        builder: (context, child) => SosGestureOverlay(
          navigatorKey: navKey,
          observer: observer,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );

    // Stand in for Read Text / Familiar Faces / Face Recognition / Face
    // Registration / Settings: all of them are ordinary pushed routes, so route
    // coverage is what the global layer has to get right.
    navKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/read_text'),
        builder: (_) => const Scaffold(body: Center(child: Text('READ TEXT'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('READ TEXT'), findsOneWidget);

    await expectOpensFromScreen(
      tester,
      'a pushed screen',
      const Scaffold(body: Center(child: Text('READ TEXT'))),
    );
  });

  testWidgets('B3 a deeply nested pushed screen is still covered',
      (tester) async {
    setPhone(tester);
    final navKey = GlobalKey<NavigatorState>();
    final observer = SosRouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [observer],
        home: const Scaffold(body: Center(child: Text('HOME'))),
        builder: (context, child) => SosGestureOverlay(
          navigatorKey: navKey,
          observer: observer,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );

    navKey.currentState!
      ..push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('LEVEL 1'))),
      ))
      ..push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('LEVEL 2'))),
      ));
    await tester.pumpAndSettle();
    expect(find.text('LEVEL 2'), findsOneWidget);

    await threeFingerSwipe(
      tester,
      fingers: 3,
      startY: zoneY,
      delta: Offset(0, qualifyingTravel),
    );
    expect(find.byType(EmergencyScreen), findsOneWidget);
  });
}