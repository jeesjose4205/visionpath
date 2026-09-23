import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:visionpath/main.dart';
import 'package:visionpath/screens/familiar_faces_screen.dart';
import 'package:visionpath/screens/navigate_screen.dart';
import 'package:visionpath/screens/read_text_screen.dart';
import 'package:visionpath/screens/settings_screen.dart';
import 'package:visionpath/services/camera_service.dart';
import 'package:visionpath/services/depth_analysis_service.dart';
import 'package:visionpath/services/familiar_face_service.dart';
import 'package:visionpath/services/navigation_service.dart';
import 'package:visionpath/services/object_detection_service.dart';
import 'package:visionpath/services/path_analysis_service.dart';
import 'package:visionpath/services/position_detection_service.dart';
import 'package:visionpath/services/settings_service.dart';

void main() {
  // Some out-of-scope screens (e.g. Read Text) have pre-existing RenderFlex
  // overflow warnings in the test harness, and their error description at
  // disposal can trip the widget inspector. Keep these tests focused on the
  // Navigate screen behaviour, not that noise. The binding overwrites
  // FlutterError.onError at the start of each test body, so the filter must
  // be installed inside a test (not in setUp).
  void filterKnownOutOfScopeNoise() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final String message = details.exceptionAsString();
      final bool overflow = message.contains('A RenderFlex overflowed');
      final bool disposal =
          message.contains("Looking up a deactivated widget's ancestor is unsafe");
      if (!overflow && !disposal) {
        originalOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  // Phone-portrait surface, matching a real device.
  void setPhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    filterKnownOutOfScopeNoise();
    await tester.pumpWidget(const VisionPathApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Pump a Navigate-only shell (same providers as the real app, without a
  /// Home screen underneath) so Navigate becomes the root route.
  Future<void> pumpNavigate(WidgetTester tester) async {
    filterKnownOutOfScopeNoise();
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
          home: const NavigateScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> popUntilNavigate(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(NavigateScreen))).popUntil(
      (route) => route.isFirst,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Navigate is the root screen: swipes open pages and back',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    await pumpApp(tester);

    // App opens into the Navigate screen as the only route.
    expect(find.byType(NavigateScreen), findsOneWidget);

    // Navigate -> swipe LEFT -> Familiar Faces.
    await tester.fling(find.byType(NavigateScreen), const Offset(-320, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(FamiliarFacesScreen), findsOneWidget);

    // Familiar Faces -> swipe RIGHT -> back to Navigate.
    await tester.fling(
      find.byType(FamiliarFacesScreen),
      const Offset(320, 0),
      900,
    );
    await tester.pump();
    // Navigate holds its swipe lock for ~450ms after the pop so the popped
    // screen can tear down the shared TTS engine before the greeting speaks.
    await tester.pump(const Duration(milliseconds: 520));
    expect(find.byType(NavigateScreen), findsOneWidget);

    // Navigate -> swipe RIGHT -> Read Text.
    await tester.fling(find.byType(NavigateScreen), const Offset(320, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ReadTextScreen), findsOneWidget);

    // Read Text -> swipe LEFT -> back to Navigate.
    await tester.fling(find.byType(ReadTextScreen), const Offset(-320, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 520));
    expect(find.byType(NavigateScreen), findsOneWidget);
  });

  testWidgets('Navigate swipe navigation does not stack duplicate pages',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    await pumpNavigate(tester);

    await tester.fling(find.byType(NavigateScreen), const Offset(-320, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(FamiliarFacesScreen), findsOneWidget);

    await tester.fling(
      find.byType(FamiliarFacesScreen),
      const Offset(320, 0),
      900,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 520));
    expect(find.byType(NavigateScreen), findsOneWidget);
    expect(find.byType(FamiliarFacesScreen, skipOffstage: false), findsNothing);

    await tester.fling(find.byType(NavigateScreen), const Offset(320, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ReadTextScreen), findsOneWidget);

    await tester.fling(find.byType(ReadTextScreen), const Offset(-320, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 520));
    expect(find.byType(NavigateScreen), findsOneWidget);
    expect(find.byType(ReadTextScreen, skipOffstage: false), findsNothing);

    // Re-enter Familiar Faces: the stack never accumulates stale copies.
    await tester.fling(find.byType(NavigateScreen), const Offset(-320, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(FamiliarFacesScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('edge swipes are ignored so pages stay on screen',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    await pumpNavigate(tester);

    // On Familiar Faces, a LEFT swipe (no page defined past it) does nothing.
    await tester.fling(find.byType(NavigateScreen), const Offset(-320, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(FamiliarFacesScreen), findsOneWidget);

    await tester.fling(
      find.byType(FamiliarFacesScreen),
      const Offset(-320, 0),
      900,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(FamiliarFacesScreen), findsOneWidget);

    // On Read Text, a RIGHT swipe (no page defined past it) does nothing.
    await popUntilNavigate(tester);
    await tester.fling(find.byType(NavigateScreen), const Offset(320, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ReadTextScreen), findsOneWidget);

    await tester.fling(find.byType(ReadTextScreen), const Offset(320, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ReadTextScreen), findsOneWidget);
  });

  testWidgets('Settings opens the existing Settings screen from Navigate',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    await pumpNavigate(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(SettingsScreen), findsOneWidget);

    await popUntilNavigate(tester);
    expect(find.byType(NavigateScreen), findsOneWidget);
  });
}