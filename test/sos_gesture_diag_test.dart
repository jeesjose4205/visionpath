import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/screens/emergency_screen.dart';
import 'package:visionpath/widgets/sos_gesture.dart';

void main() {
  void setPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpShell(WidgetTester tester, {bool withHorizontal = false}) async {
    final navKey = GlobalKey<NavigatorState>();
    final observer = SosRouteObserver();
    Widget home = const Scaffold(body: Center(child: Text('content')));
    if (withHorizontal) {
      home = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {},
        onHorizontalDragUpdate: (_) {},
        onHorizontalDragEnd: (_) {},
        child: home,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [observer],
        home: home,
        builder: (context, child) => SosGestureOverlay(
          navigatorKey: navKey,
          observer: observer,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  testWidgets('vertical swipe from bottom opens SOS', (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    expect(find.byType(EmergencyScreen), findsNothing);

    final gesture = await tester.createGesture();
    await gesture.down(const Offset(200, 750));
    await tester.pump();

    for (int i = 1; i <= 6; i++) {
      await gesture.moveBy(const Offset(0, -112));
      await tester.pump();
    }

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(EmergencyScreen), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets('short weak swipe does not open SOS', (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    expect(find.byType(EmergencyScreen), findsNothing);

    final gesture = await tester.createGesture();
    await gesture.down(const Offset(200, 750));
    await tester.pump();

    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(EmergencyScreen), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets(
      'sub-threshold (70%) swipe springs the panel back and does not open SOS',
      (tester) async {
    setPhone(tester);
    await pumpShell(tester);

    final gesture = await tester.createGesture();
    await gesture.down(const Offset(200, 750));
    await tester.pump();

    // 70% of the 800px screen height = 560px, just under the 80% gate.
    for (int i = 1; i <= 5; i++) {
      await gesture.moveBy(const Offset(0, -112));
      await tester.pump();
    }

    await gesture.up();
    await tester.pump();

    // The preview must animate away completely so the previous screen is
    // shown again, well inside the hard fallback deadline.
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(EmergencyScreen), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_SosPreview'),
      findsNothing,
    );
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets('horizontal swipe does not open SOS', (tester) async {
    setPhone(tester);
    await pumpShell(tester, withHorizontal: true);

    final gesture = await tester.createGesture();
    await gesture.down(const Offset(200, 750));
    await tester.pump();

    for (int i = 1; i <= 5; i++) {
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
    }

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(EmergencyScreen), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets('vertical swipe opens SOS with competing horizontal detector', (tester) async {
    setPhone(tester);
    await pumpShell(tester, withHorizontal: true);

    final gesture = await tester.createGesture();
    await gesture.down(const Offset(200, 750));
    await tester.pump();

    for (int i = 1; i <= 6; i++) {
      await gesture.moveBy(const Offset(0, -112));
      await tester.pump();
    }

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(EmergencyScreen), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets('SOS swipe suppresses an underlying screen pushing its own page',
      (tester) async {
    setPhone(tester);
    final navKey = GlobalKey<NavigatorState>();
    final observer = SosRouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [observer],
        // Mimics a real screen: a horizontal-swipe handler that, without the
        // SOS gate, would push its OWN page on the same pointer sequence.
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

    // Fast, slightly diagonal swipe from the zone: enough vertical travel to
    // qualify (81% > 80%) and enough sideways drift to let the horizontal
    // recognizer win the arena too.
    final gesture = await tester.createGesture();
    await gesture.down(const Offset(200, 750));
    await tester.pump();

    for (int i = 1; i <= 6; i++) {
      await gesture.moveBy(const Offset(8, -108));
      await tester.pump();
    }

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(EmergencyScreen), findsOneWidget);
    expect(find.text('WRONG SCREEN'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 10)));
}
