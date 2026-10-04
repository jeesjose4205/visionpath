import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/widgets/emergency_sos_button.dart';

/// The SOS hold lives in exactly one place ([SosHoldController]) and the button
/// is only a view onto it. These tests drive the real controller through a
/// Listener wired the same way [EmergencyScreen] wires it, and check both the
/// state machine and the button's unchanged progress feedback.
void main() {
  void setPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  late SosHoldController hold;
  late int activated;
  late int cancelled;
  late int resets;
  late List<int> ticks;

  /// ChangeNotifier throws on a second dispose, and one test disposes early to
  /// simulate the screen being torn down mid-countdown.
  bool holdDisposed = false;

  /// Mirrors the real screen: a full-surface Listener feeding one controller,
  /// with the button rendering it.
  Future<void> pumpSurface(WidgetTester tester) async {
    activated = 0;
    cancelled = 0;
    resets = 0;
    ticks = <int>[];
    holdDisposed = false;
    hold = SosHoldController(
      onActivated: () => activated++,
      onTick: (int remaining) => ticks.add(remaining),
      onCancelled: () => cancelled++,
      onReset: () => resets++,
    );
    addTearDown(() {
      if (!holdDisposed) hold.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Exactly how EmergencyScreen wires it: the Listener is an ANCESTOR
          // of the button, so it observes every press without consuming it.
          body: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: hold.pointerDown,
            onPointerMove: hold.pointerMove,
            onPointerUp: hold.pointerUp,
            onPointerCancel: hold.pointerCancel,
            child: Center(child: EmergencySOSButton(controller: hold)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Offset centre(WidgetTester tester) =>
      tester.getCenter(find.byType(EmergencySOSButton));

  testWidgets('a single quick tap does NOT activate', (tester) async {
    setPhone(tester);
    await pumpSurface(tester);

    final TestGesture g = await tester.createGesture();
    await g.down(centre(tester));
    await tester.pump(const Duration(milliseconds: 80));
    await g.up();
    await tester.pump();

    // A tap is not an abandoned hold, so it must stay silent too.
    expect(cancelled, 0);

    // Let the whole hold duration elapse: a tap must never fire later.
    await tester.pump(const Duration(seconds: 7));
    expect(activated, 0);
    expect(find.text('SOS Activated'), findsNothing);
  });

  testWidgets('holding to the threshold activates exactly once', (tester) async {
    setPhone(tester);
    await pumpSurface(tester);

    final TestGesture g = await tester.createGesture();
    await g.down(centre(tester));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(activated, 1);
    expect(ticks, <int>[5, 4, 3, 2, 1]);

    // Still holding well past the threshold must not fire a second time.
    await tester.pump(const Duration(seconds: 4));
    expect(activated, 1);
    await g.up();
    await tester.pump();
    expect(activated, 1);
  });

  testWidgets('a genuine hold released early cancels with feedback',
      (tester) async {
    setPhone(tester);
    await pumpSurface(tester);

    final TestGesture g = await tester.createGesture();
    await g.down(centre(tester));
    await tester.pump(const Duration(seconds: 2));
    expect(ticks, isNotEmpty, reason: 'countdown should be running');

    await g.up();
    await tester.pump();

    expect(cancelled, 1);
    expect(activated, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(activated, 0, reason: 'a cancelled hold must not fire later');
  });

  testWidgets('a second finger cannot hijack or abort the hold',
      (tester) async {
    setPhone(tester);
    await pumpSurface(tester);

    final Offset c = centre(tester);
    final TestGesture primary = await tester.createGesture(pointer: 1);
    final TestGesture second = await tester.createGesture(pointer: 2);
    await primary.down(c);
    await tester.pump(const Duration(seconds: 1));

    await second.down(c + const Offset(1, 1));
    await tester.pump(const Duration(milliseconds: 200));
    await second.up();
    await tester.pump(const Duration(milliseconds: 200));

    expect(cancelled, 0,
        reason: 'the extra finger must not abort the real hold');

    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(activated, 1);
  });

  testWidgets('sliding away cancels the hold', (tester) async {
    setPhone(tester);
    await pumpSurface(tester);

    final TestGesture g = await tester.createGesture();
    await g.down(centre(tester));
    await tester.pump(const Duration(seconds: 2));
    expect(ticks, isNotEmpty);

    // Drag well clear of the press without lifting.
    await g.moveBy(const Offset(0, 140));
    await tester.pump();

    expect(cancelled, 1);
    // Even with the finger still down and time passing, it must not fire.
    await tester.pump(const Duration(seconds: 5));
    expect(activated, 0);
  });

  testWidgets('finger wobble during a hold does NOT cancel', (tester) async {
    setPhone(tester);
    await pumpSurface(tester);

    final TestGesture g = await tester.createGesture();
    await g.down(centre(tester));
    await tester.pump(const Duration(seconds: 1));

    // A few px of tremor, then back: well under the cancel slop.
    await g.moveBy(const Offset(4, 3));
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveBy(const Offset(-4, -3));
    await tester.pump(const Duration(milliseconds: 100));

    expect(cancelled, 0);

    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(activated, 1);
  });

  testWidgets('repeated holds do not duplicate an activation', (tester) async {
    setPhone(tester);
    await pumpSurface(tester);

    final Offset c = centre(tester);

    final TestGesture first = await tester.createGesture();
    await first.down(c);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await first.up();
    await tester.pump();
    expect(activated, 1);

    // A second long hold on the already-activated button must be inert.
    final TestGesture second = await tester.createGesture();
    await second.down(c);
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await second.up();
    await tester.pump();

    expect(activated, 1, reason: 'activation must fire exactly once');
  });

  testWidgets('a cancelled hold can be retried and then succeeds',
      (tester) async {
    setPhone(tester);
    await pumpSurface(tester);

    final Offset c = centre(tester);

    // Aborted first attempt, held long enough to count as a real hold.
    final TestGesture attempt = await tester.createGesture();
    await attempt.down(c);
    await tester.pump(const Duration(seconds: 1));
    await attempt.up();
    await tester.pump();
    expect(cancelled, 1);
    expect(activated, 0);

    // The button must return to a clean ready state.
    expect(find.text('Press & hold for 5 seconds'), findsOneWidget);

    final TestGesture retry = await tester.createGesture();
    await retry.down(c);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await retry.up();
    await tester.pump();

    expect(activated, 1);
    expect(cancelled, 1);
  });

  testWidgets('the existing progress ring and label appear while holding',
      (tester) async {
    setPhone(tester);
    await pumpSurface(tester);

    final TestGesture g = await tester.createGesture();
    await g.down(centre(tester));
    await tester.pump(const Duration(seconds: 2));

    // Existing activation feedback, not new UI.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Keep holding... releasing cancels'), findsOneWidget);

    await g.up();
    await tester.pump();
  });

  testWidgets('the button still renders its activated state and resets',
      (tester) async {
    setPhone(tester);
    await pumpSurface(tester);

    final TestGesture g = await tester.createGesture();
    await g.down(centre(tester));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await g.up();
    await tester.pump();

    expect(find.text('SOS Activated'), findsOneWidget);
    expect(find.text('Reset SOS'), findsOneWidget);

    await tester.tap(find.text('Reset SOS'));
    await tester.pump();

    expect(resets, 1);
    expect(find.text('Press & hold for 5 seconds'), findsOneWidget);
  });

  testWidgets('disposing mid-hold never activates', (tester) async {
    setPhone(tester);
    await pumpSurface(tester);

    final TestGesture g = await tester.createGesture();
    await g.down(centre(tester));
    await tester.pump(const Duration(seconds: 2));

    // Tear the screen down mid-countdown. The real EmergencyScreen owns the
    // controller and disposes it with the route, which is what must stop the
    // countdown from firing against a dead screen.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    hold.dispose();
    holdDisposed = true;
    await tester.pump(const Duration(seconds: 6));

    expect(activated, 0);
    expect(tester.takeException(), isNull);
  });
}