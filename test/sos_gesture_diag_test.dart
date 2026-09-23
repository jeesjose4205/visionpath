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

    for (int i = 1; i <= 5; i++) {
      await gesture.moveBy(const Offset(0, -112));
      await tester.pump();
    }

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

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
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(EmergencyScreen), findsNothing);
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
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(EmergencyScreen), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets('vertical swipe opens SOS with competing horizontal detector', (tester) async {
    setPhone(tester);
    await pumpShell(tester, withHorizontal: true);

    final gesture = await tester.createGesture();
    await gesture.down(const Offset(200, 750));
    await tester.pump();

    for (int i = 1; i <= 5; i++) {
      await gesture.moveBy(const Offset(0, -112));
      await tester.pump();
    }

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(EmergencyScreen), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 10)));
}
