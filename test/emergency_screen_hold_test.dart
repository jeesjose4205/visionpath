import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionpath/screens/emergency_screen.dart';
import 'package:visionpath/services/settings_service.dart';
import 'package:visionpath/services/sos_service.dart';
import 'package:visionpath/widgets/emergency_sos_button.dart';
import 'package:visionpath/widgets/sound_mode_button.dart';

/// The SOS hold must work anywhere on the SOS screen, not only on the button,
/// while every existing control on that screen keeps working normally.
///
/// These tests drive the real [EmergencyScreen], because the whole point of the
/// change is the wiring between the screen's full-surface Listener and the
/// button's shared hold controller.
void main() {
  // 400x800 logical.
  const double screenHeight = 800;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // SOS is an app-scoped singleton, so a session left active by one test
    // would otherwise leak into the next.
    addTearDown(SosService.instance.reset);
  });

  void setPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await SettingsService.instance.load();
    await tester.pumpWidget(const MaterialApp(home: EmergencyScreen()));
    // Let the screen's entrance announcement delay expire.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Presses at [at], holds for the full SOS duration, then lifts.
  Future<void> holdAt(WidgetTester tester, Offset at) async {
    final TestGesture g = await tester.createGesture();
    await g.down(at);
    await tester.pump();
    for (int i = 0; i < SosHoldController.holdSeconds; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await g.up();
    await tester.pump();
  }


  /// Asserts SOS actually started.
  ///
  /// Reads the service rather than a label, because the service is the owner of
  /// the procedure now; the pill text is presentation and must not be what
  /// proves an emergency started.
  void expectActivated(WidgetTester tester, String where) {
    expect(
      SosService.instance.session.canReset,
      isTrue,
      reason: 'holding the $where must activate SOS',
    );
  }

  testWidgets('holding the SOS button activates', (tester) async {
    setPhone(tester);
    await pumpScreen(tester);

    await holdAt(tester, tester.getCenter(find.byType(EmergencySOSButton)));
    expectActivated(tester, 'SOS button');
  });

  testWidgets('holding the centre of the screen activates', (tester) async {
    setPhone(tester);
    await pumpScreen(tester);

    await holdAt(tester, const Offset(200, 430));
    expectActivated(tester, 'centre of the screen');
  });

  testWidgets('holding the left side activates', (tester) async {
    setPhone(tester);
    await pumpScreen(tester);

    await holdAt(tester, const Offset(24, 430));
    expectActivated(tester, 'left side');
  });

  testWidgets('holding the right side activates', (tester) async {
    setPhone(tester);
    await pumpScreen(tester);

    await holdAt(tester, const Offset(376, 430));
    expectActivated(tester, 'right side');
  });

  testWidgets('holding the top area activates', (tester) async {
    setPhone(tester);
    await pumpScreen(tester);

    await holdAt(tester, const Offset(200, 70));
    expectActivated(tester, 'top area');
  });

  testWidgets('holding the bottom area activates', (tester) async {
    setPhone(tester);
    await pumpScreen(tester);

    await holdAt(tester, const Offset(200, screenHeight - 30));
    expectActivated(tester, 'bottom area');
  });

  testWidgets('a quick tap anywhere does NOT activate or announce a cancel',
      (tester) async {
    setPhone(tester);
    await pumpScreen(tester);

    // One tap on empty background, one on the SOS button.
    final TestGesture a = await tester.createGesture();
    await a.down(const Offset(200, 430));
    await tester.pump(const Duration(milliseconds: 60));
    await a.up();
    await tester.pump();

    await tester.tap(find.byType(EmergencySOSButton));
    await tester.pump();

    // Nothing activated, and no spurious "SOS cancelled." feedback.
    expect(find.text('SOS Activated'), findsNothing);
    expect(find.text('SOS cancelled.'), findsNothing);

    await tester.pump(const Duration(seconds: 7));
    expect(find.text('SOS Activated'), findsNothing);
  });

  testWidgets('the back button still navigates back', (tester) async {
    setPhone(tester);
    await SettingsService.instance.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: '/from'),
                    builder: (_) => const EmergencyScreen(),
                  ),
                ),
                child: const Text('OPEN SOS'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('OPEN SOS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(EmergencyScreen), findsOneWidget);

    // The header back arrow must still work; the new Listener observes without
    // consuming, so the control underneath is unaffected.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('OPEN SOS'), findsOneWidget);
    expect(find.byType(EmergencyScreen), findsNothing);
  });

  testWidgets('the sound mode toggle still works', (tester) async {
    setPhone(tester);
    await pumpScreen(tester);

    final Object before = SettingsService.instance.alertMode;
    await tester.tap(find.byIcon(SoundModeButton.iconFor(SettingsService.instance.alertMode)));
    await tester.pump();

    expect(SettingsService.instance.alertMode, isNot(before));
    expect(find.text('SOS Activated'), findsNothing);
  });

  testWidgets('a hold that activates SOS never offers a second Call button',
      (tester) async {
    setPhone(tester);
    await pumpScreen(tester);

    await holdAt(tester, const Offset(200, 430));
    expect(SosService.instance.session.canReset, isTrue);

    // The procedure is automatic: the user must never be asked to pick a
    // contact or press Call again.
    expect(find.text('Call'), findsNothing);
    expect(find.textContaining('Choose an emergency contact'), findsNothing);
    expect(find.text('Reset SOS'), findsOneWidget);
  });

  testWidgets('the screen no longer opens anything by horizontal swipe',
      (tester) async {
    setPhone(tester);
    await pumpScreen(tester);

    final TestGesture g = await tester.createGesture();
    await g.down(const Offset(340, 430));
    await tester.pump();
    for (int s = 0; s < 5; s++) {
      await g.moveBy(const Offset(-50, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // The drag-swallow guard must keep the user on the SOS screen.
    expect(find.byType(EmergencyScreen), findsOneWidget);
    expect(find.text('SOS Activated'), findsNothing);
  });
}

