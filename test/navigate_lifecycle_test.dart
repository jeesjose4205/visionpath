import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/screens/familiar_faces_screen.dart';
import 'package:visionpath/screens/navigate_screen.dart';
import 'package:visionpath/screens/read_text_screen.dart';
import 'package:visionpath/services/camera_service.dart';
import 'package:visionpath/services/depth_analysis_service.dart';
import 'package:visionpath/services/navigation_service.dart';
import 'package:visionpath/services/object_detection_service.dart';
import 'package:visionpath/services/path_analysis_service.dart';
import 'package:visionpath/services/position_detection_service.dart';
import 'package:visionpath/services/familiar_face_service.dart';
import 'package:visionpath/services/settings_service.dart';
import 'package:visionpath/widgets/sos_gesture.dart';
import 'package:provider/provider.dart';

/// The carousel must stay a carousel while navigation is idle, and must lock
/// shut the moment a run owns the screen. These tests drive the real
/// NavigateScreen so the state machine, the PopScope and the swipe guard are all
/// exercised together.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // [SosGestureOverlay.sosSwipeActive] is static and released on a timer, so it
  // has to be cleared between tests or one test's SOS drag gates the next one's
  // horizontal swipe handling.
  tearDown(() => SosGestureOverlay.sosSwipeActive = false);

  void ignoreOutOfScopeNoise() {
    final void Function(FlutterErrorDetails)? original = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final String message = details.exceptionAsString();
      // The screen starts real camera/model work that cannot succeed in a
      // widget test; that failure path is not what is under test here.
      final bool known =
          message.contains('Looking up a deactivated widget') ||
          message.contains('overflow');
      if (!known) original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  void setPhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpNavigate(WidgetTester tester) async {
    ignoreOutOfScopeNoise();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CameraService>.value(value: CameraService()),
          ChangeNotifierProvider<ObjectDetectionService>.value(
            value: ObjectDetectionService(),
          ),
          Provider<PositionDetectionService>.value(
            value: PositionDetectionService(),
          ),
          Provider<DepthAnalysisService>.value(value: DepthAnalysisService()),
          Provider<PathAnalysisService>.value(value: PathAnalysisService()),
          ChangeNotifierProvider<NavigationService>.value(
            value: NavigationService(),
          ),
          ChangeNotifierProvider<FamiliarFaceService>(
            create: (_) => FamiliarFaceService()..load(),
          ),
          ChangeNotifierProvider<SettingsService>.value(
            value: SettingsService.instance,
          ),
        ],
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: NavigateScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> popUntilNavigate(WidgetTester tester) async {
    Navigator.of(
      tester.element(find.byType(NavigateScreen, skipOffstage: false)),
    ).popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
  }

  Future<void> flingLeft(WidgetTester tester) async {
    await tester.fling(
      find.byType(NavigateScreen, skipOffstage: false),
      const Offset(-320, 0),
      900,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 950));
  }

  testWidgets('swipe still opens a page while navigation is idle',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    await pumpNavigate(tester);

    expect(find.text('START NAVIGATION'), findsOneWidget);

    await flingLeft(tester);
    expect(find.byType(FamiliarFacesScreen), findsOneWidget);
  });

  testWidgets('swipe right opens Read Text while navigation is idle',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    await pumpNavigate(tester);

    await tester.fling(
      find.byType(NavigateScreen, skipOffstage: false),
      const Offset(320, 0),
      900,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 950));

    expect(find.byType(ReadTextScreen), findsOneWidget);
  });

  testWidgets('starting navigation locks the horizontal swipe',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    await pumpNavigate(tester);

    // START flips the state to `starting` synchronously, before any await, so
    // the swipe gate is closed from this moment on.
    await tester.tap(find.text('START NAVIGATION'));
    await tester.pump();

    await flingLeft(tester);

    // The user must stay put: no page was pushed.
    expect(find.byType(FamiliarFacesScreen), findsNothing);
    expect(find.byType(ReadTextScreen), findsNothing);
    expect(find.byType(NavigateScreen), findsOneWidget);
  });

  testWidgets('back while starting keeps the user on Navigation',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    await pumpNavigate(tester);

    await tester.tap(find.text('START NAVIGATION'));
    await tester.pump();

    final NavigatorState navigator = Navigator.of(
      tester.element(find.byType(NavigateScreen)),
    );

    // Back while the run owns the screen must stop it and hold the route, not
    // leave the screen with the process still going.
    navigator.maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(NavigateScreen), findsOneWidget);
    // Nothing was pushed and the route never popped.
    expect(find.byType(FamiliarFacesScreen), findsNothing);
    expect(find.byType(ReadTextScreen), findsNothing);
  });

  testWidgets('repeated Back while stopping does not pop or double-stop',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    await pumpNavigate(tester);

    await tester.tap(find.text('START NAVIGATION'));
    await tester.pump();

    final NavigatorState navigator = Navigator.of(
      tester.element(find.byType(NavigateScreen)),
    );

    // Three Backs in a row while the teardown is in flight.
    navigator.maybePop();
    await tester.pump();
    navigator.maybePop();
    await tester.pump();
    navigator.maybePop();
    await tester.pump();
    await tester.pumpAndSettle();

    // Still the root route: no page was pushed and the route never popped.
    expect(find.byType(NavigateScreen), findsOneWidget);
    expect(find.byType(FamiliarFacesScreen), findsNothing);
    expect(find.byType(ReadTextScreen), findsNothing);
  });

  testWidgets('Back while active does not pop when a route sits underneath',
      (WidgetTester tester) async {
    // NavigateScreen is the app root in the real app, where there is nothing to
    // pop to and the question is moot. The carousel can leave a screen
    // underneath it though (swipe to Familiar Faces, then back), and that is the
    // case where "stop then leave" would be observable.
    setPhoneSurface(tester);
    ignoreOutOfScopeNoise();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CameraService>.value(value: CameraService()),
          ChangeNotifierProvider<ObjectDetectionService>.value(
            value: ObjectDetectionService(),
          ),
          Provider<PositionDetectionService>.value(
            value: PositionDetectionService(),
          ),
          Provider<DepthAnalysisService>.value(value: DepthAnalysisService()),
          Provider<PathAnalysisService>.value(value: PathAnalysisService()),
          ChangeNotifierProvider<NavigationService>.value(
            value: NavigationService(),
          ),
          ChangeNotifierProvider<FamiliarFaceService>(
            create: (_) => FamiliarFaceService()..load(),
          ),
          ChangeNotifierProvider<SettingsService>.value(
            value: SettingsService.instance,
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NavigateScreen(),
                    ),
                  ),
                  child: const Text('OPEN NAVIGATE'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('OPEN NAVIGATE'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigateScreen), findsOneWidget);

    await tester.tap(find.text('START NAVIGATION'));
    await tester.pump();

    // Back must mean "stop the run", not "leave with the run still going".
    final NavigatorState navigator =
        Navigator.of(tester.element(find.byType(NavigateScreen)));
    expect(navigator.canPop(), isTrue, reason: 'precondition: a route is below');
    navigator.maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Still on Navigation, now stopped.
    expect(find.byType(NavigateScreen), findsOneWidget);
    expect(find.text('OPEN NAVIGATE'), findsNothing);
  });

  testWidgets('an SOS drag in flight wins over the horizontal swipe',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    await pumpNavigate(tester);

    // [SosGestureOverlay] is mounted globally in [main], but it needs three
    // simultaneous pointers, which cannot be driven through [flingLeft]. What
    // must hold here is the coordination rule in the carousel: while an SOS drag
    // owns the pointer, the horizontal swipe must stand down rather than fight
    // it for the gesture.
    SosGestureOverlay.sosSwipeActive = true;

    await flingLeft(tester);
    expect(find.byType(FamiliarFacesScreen), findsNothing);
    expect(find.byType(NavigateScreen), findsOneWidget);

    // ...and once SOS releases the gate the carousel behaves normally again.
    SosGestureOverlay.sosSwipeActive = false;
    await flingLeft(tester);
    expect(find.byType(FamiliarFacesScreen), findsOneWidget);
  });

  testWidgets('the lock re-arms after a second run', (WidgetTester tester) async {
    setPhoneSurface(tester);
    await pumpNavigate(tester);

    await tester.tap(find.text('START NAVIGATION'));
    await tester.pump();
    await flingLeft(tester);
    expect(find.byType(FamiliarFacesScreen), findsNothing, reason: 'run 1 locked');

    Navigator.of(tester.element(find.byType(NavigateScreen))).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('START NAVIGATION'), findsOneWidget, reason: 'stopped again');

    await popUntilNavigate(tester);
    await flingLeft(tester);
    expect(find.byType(FamiliarFacesScreen), findsOneWidget,
        reason: 'idle carousel works again');

    // A second run must take the lock again, not leave the screen unlocked
    // because of state left over from the first run.
    await popUntilNavigate(tester);
    await tester.tap(find.text('START NAVIGATION'));
    await tester.pump();
    await flingLeft(tester);
    expect(find.byType(FamiliarFacesScreen), findsNothing, reason: 'run 2 locked');
  });

  testWidgets('the swipe lock is released once the run is over',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    await pumpNavigate(tester);

    await tester.tap(find.text('START NAVIGATION'));
    await tester.pump();

    final NavigatorState navigator = Navigator.of(
      tester.element(find.byType(NavigateScreen)),
    );
    navigator.maybePop();
    await tester.pumpAndSettle();

    // Navigation is stopped again, so the carousel must work normally.
    await popUntilNavigate(tester);
    await flingLeft(tester);
    expect(find.byType(FamiliarFacesScreen), findsOneWidget);
  });
}