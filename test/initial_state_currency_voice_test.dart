import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:visionpath/screens/currency_recognition_screen.dart';
import 'package:visionpath/screens/familiar_faces_screen.dart';
import 'package:visionpath/screens/navigate_screen.dart';
import 'package:visionpath/screens/read_text_screen.dart';
import 'package:visionpath/services/camera_service.dart';
import 'package:visionpath/services/depth_analysis_service.dart';
import 'package:visionpath/services/familiar_face_service.dart';
import 'package:visionpath/services/navigation_service.dart';
import 'package:visionpath/services/object_detection_service.dart';
import 'package:visionpath/services/path_analysis_service.dart';
import 'package:visionpath/services/position_detection_service.dart';
import 'package:visionpath/services/settings_service.dart';
import 'package:visionpath/services/target_navigation_service.dart';
import 'package:visionpath/services/voice_command_controller.dart';
import 'package:visionpath/services/vibration_service.dart';

/// CameraService that never touches a platform channel, tuned for the three
/// main screens: the flows under test only need the async start/stop hooks to
/// succeed. `isInitialized` deliberately stays false so no screen tries to
/// build a preview around a null CameraController.
class StreamFakeCameraService extends CameraService {
  int startCalls = 0;
  int stopCalls = 0;
  bool failStart = false;

  @override
  bool get isInitialized => false;

  @override
  CameraController? get controller => null;

  @override
  String? get errorMessage => failStart ? 'camera unavailable' : null;

  @override
  int get imageRotationQuarterTurns => 0;

  @override
  Future<bool> initializeController() async => !failStart;

  @override
  Future<bool> startImageStream() async {
    if (failStart) return false;
    startCalls++;
    return true;
  }

  @override
  Future<bool> stopImageStream() async {
    stopCalls++;
    return true;
  }

  @override
  void setOnFrameAvailable(OnFrameAvailable callback) {}
}

/// VoiceCommandController with the recognizer replaced by a script: a real
/// press-and-hold still drives beginHold/endHold through the region's gesture,
/// and releasing hands the canned transcript to the screen's onCommand exactly
/// as the speech engine would.
class ScriptedVoiceController extends VoiceCommandController {
  String script = '';
  int beginCalls = 0;
  int endCalls = 0;

  @override
  Future<void> beginHold() async {
    beginCalls++;
    debugSetHoldState(holding: true);
  }

  @override
  Future<void> endHold() async {
    endCalls++;
    debugSetHoldState();
    final String words = script;
    if (words.isEmpty) {
      onFailure?.call(VoiceCommandFailure.nothingHeard);
      return;
    }
    onCommand?.call(words);
  }

  @override
  Future<void> cancel() async => debugSetHoldState();

  /// A repeated recognizer callback for a transcript already routed.
  void deliver(String transcript) => onCommand?.call(transcript);
}

/// Counts routes pushed on the harness navigator, so a command that fires
/// twice can be shown to open the screen exactly once.
class PushRecorder extends NavigatorObserver {
  final List<Route<dynamic>> pushes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {}

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {}

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {}
}

const String _currencyWords = 'Open currency recognition';

/// A point over the title/camera area, clear of every button on all three
/// screens, where a press-and-hold hits the assistant's own region.
const Offset _holdPoint = Offset(180, 140);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Tap feedback must not reach the platform vibrator in widget tests.
    VibrationService.debugImpact = () {};
    VibrationService.debugSelectionClick = () {};
  });

  tearDown(() {
    VibrationService.debugImpact = null;
    VibrationService.debugSelectionClick = null;
  });

  void filterKnownNoise() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final String message = details.exceptionAsString();
      final bool overflow = message.contains('A RenderFlex overflowed');
      final bool disposal =
          message.contains("Looking up a deactivated widget's ancestor is unsafe");
      final bool silentTts = message.contains('VOICE_') ||
          message.contains('MissingPluginException');
      if (!overflow && !disposal && !silentTts) {
        originalOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  void setPhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpNavigateHome(
    WidgetTester tester, {
    required StreamFakeCameraService camera,
    required ScriptedVoiceController voice,
    PushRecorder? recorder,
  }) async {
    filterKnownNoise();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CameraService>.value(value: camera),
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
          navigatorObservers: [?recorder],
          home: NavigateScreen(voiceCommand: voice),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpFamiliarFacesHome(
    WidgetTester tester, {
    required StreamFakeCameraService camera,
    required ScriptedVoiceController voice,
    PushRecorder? recorder,
  }) async {
    filterKnownNoise();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CameraService>.value(value: camera),
          ChangeNotifierProvider<FamiliarFaceService>(
            create: (_) => FamiliarFaceService()..load(),
          ),
          ChangeNotifierProvider<SettingsService>.value(
            value: SettingsService.instance,
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorObservers: [?recorder],
          home: FamiliarFacesScreen(voiceCommand: voice),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> pumpReadTextHome(
    WidgetTester tester, {
    required StreamFakeCameraService camera,
    required ScriptedVoiceController voice,
    PushRecorder? recorder,
  }) async {
    filterKnownNoise();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CameraService>.value(value: camera),
          ChangeNotifierProvider<SettingsService>.value(
            value: SettingsService.instance,
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorObservers: [?recorder],
          home: ReadTextScreen(voiceCommand: voice),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Press, hold past the threshold, release: the region opens the microphone
  /// (the scripted controller records it) and the release delivers [words] to
  /// the screen exactly as the recognizer would.
  Future<void> holdAndSay(
    WidgetTester tester,
    ScriptedVoiceController voice,
    String words,
  ) async {
    voice.script = words;
    final TestGesture gesture = await tester.startGesture(_holdPoint);
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Replaces the whole tree, which disposes the screens (and every timer they
  /// own) the way leaving the app would.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets(
      'navigation main screen opens Currency Recognition from a hold '
      'before START NAVIGATION', (WidgetTester tester) async {
    setPhoneSurface(tester);
    final camera = StreamFakeCameraService();
    final voice = ScriptedVoiceController();
    await pumpNavigateHome(tester, camera: camera, voice: voice);

    // Precondition: the initial (inactive) main state, run never started.
    expect(find.text('START NAVIGATION'), findsOneWidget);
    expect(camera.startCalls, 0);

    await holdAndSay(tester, voice, _currencyWords);

    // The hold really opened the assistant, and the release routed the command.
    expect(voice.beginCalls, 1);
    expect(voice.endCalls, 1);
    expect(
      find.byType(CurrencyRecognitionScreen, skipOffstage: false),
      findsOneWidget,
    );
    // No navigation run existed, so nothing had to be stopped first.
    expect(camera.stopCalls, 0);

    await unmount(tester);
  });

  testWidgets(
      'familiar faces main screen opens Currency Recognition from a hold '
      'before RECOGNIZE', (WidgetTester tester) async {
    setPhoneSurface(tester);
    final camera = StreamFakeCameraService();
    final voice = ScriptedVoiceController();
    await pumpFamiliarFacesHome(tester, camera: camera, voice: voice);

    // Precondition: the initial (inactive) main state, never started.
    expect(find.text('RECOGNIZE'), findsOneWidget);
    expect(camera.startCalls, 0);

    await holdAndSay(tester, voice, _currencyWords);

    expect(voice.beginCalls, 1);
    expect(
      find.byType(CurrencyRecognitionScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(camera.stopCalls, 0);

    await unmount(tester);
  });

  testWidgets(
      'read text main screen opens Currency Recognition from a hold '
      'before START READING', (WidgetTester tester) async {
    setPhoneSurface(tester);
    final camera = StreamFakeCameraService();
    final voice = ScriptedVoiceController();
    await pumpReadTextHome(tester, camera: camera, voice: voice);

    // Precondition: the initial (inactive) main state, reading never started.
    expect(find.text('START READING'), findsOneWidget);
    expect(camera.startCalls, 0);

    await holdAndSay(tester, voice, _currencyWords);

    expect(voice.beginCalls, 1);
    expect(
      find.byType(CurrencyRecognitionScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(camera.stopCalls, 0);

    await unmount(tester);
  });

  testWidgets(
      'a command the recognizer reports twice opens only one '
      'Currency Recognition route', (WidgetTester tester) async {
    setPhoneSurface(tester);
    final camera = StreamFakeCameraService();
    final voice = ScriptedVoiceController();
    final recorder = PushRecorder();
    await pumpNavigateHome(
      tester,
      camera: camera,
      voice: voice,
      recorder: recorder,
    );

    final int pushesBefore = recorder.pushes.length;

    // The recognizer can deliver the same sentence twice in a row; both
    // callbacks must collapse into a single navigation.
    voice.deliver(_currencyWords);
    await tester.pump();
    voice.deliver(_currencyWords);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(recorder.pushes.length, pushesBefore + 1,
        reason: 'the repeated command must push exactly one route');
    expect(
      find.byType(CurrencyRecognitionScreen, skipOffstage: false),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets(
      'after Start Navigation the previous voice commands still work',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    final camera = StreamFakeCameraService();
    final voice = ScriptedVoiceController();
    await pumpNavigateHome(tester, camera: camera, voice: voice);

    await tester.tap(find.text('START NAVIGATION'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The run owns the screen now.
    expect(find.text('STOP NAVIGATION'), findsOneWidget);
    expect(camera.startCalls, greaterThanOrEqualTo(1));
    expect(TargetNavigationService.instance.isActive, isFalse);

    // "find a chair" is a pre-existing voice command: it must still start a
    // target search rather than being mistaken for a currency request.
    await holdAndSay(tester, voice, 'find a chair');

    expect(TargetNavigationService.instance.isActive, isTrue);
    expect(
      TargetNavigationService.instance.targetName.toLowerCase(),
      'chair',
    );
    expect(find.byType(CurrencyRecognitionScreen), findsNothing);

    // Back while active stops the run without popping (the PopScope rule),
    // which also releases the timers the run owns.
    final navigator =
        Navigator.of(tester.element(find.byType(NavigateScreen)));
    navigator.maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NavigateScreen), findsOneWidget);
    expect(TargetNavigationService.instance.isActive, isFalse);

    await unmount(tester);
  });

  testWidgets(
      'a running recognition hands the camera over and Currency Recognition '
      'still opens', (WidgetTester tester) async {
    setPhoneSurface(tester);
    final camera = StreamFakeCameraService();
    final voice = ScriptedVoiceController();
    await pumpFamiliarFacesHome(tester, camera: camera, voice: voice);

    await tester.tap(find.text('RECOGNIZE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The run owns the shared camera now.
    expect(find.text('STOP RECOGNITION'), findsOneWidget);
    expect(camera.startCalls, greaterThanOrEqualTo(1));

    await holdAndSay(tester, voice, _currencyWords);

    // The assistant stays available while the feature runs, and the camera
    // stream is released before Currency Recognition takes it over.
    expect(
      find.byType(CurrencyRecognitionScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(camera.stopCalls, greaterThanOrEqualTo(1));
    expect(voice.isHolding, isFalse, reason: 'the hold session was closed');

    await unmount(tester);
  });

  testWidgets(
      'a running reading session is ended before Currency Recognition opens',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    final camera = StreamFakeCameraService();
    final voice = ScriptedVoiceController();
    await pumpReadTextHome(tester, camera: camera, voice: voice);

    await tester.tap(find.text('START READING'));
    await tester.pump();
    // Past the intro-card fade (460 ms), which is when the gate leaves the
    // tree, exactly as on the device.
    await tester.pump(const Duration(milliseconds: 600));

    // The reading session owns the camera now.
    expect(camera.startCalls, greaterThanOrEqualTo(1));
    expect(find.text('START READING'), findsNothing);

    await holdAndSay(tester, voice, _currencyWords);

    // _newScan() returned the screen to its initial gate and released the
    // stream before the push.
    expect(
      find.byType(CurrencyRecognitionScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(camera.stopCalls, greaterThanOrEqualTo(1));
    expect(find.text('START READING'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets(
      'closing Currency Recognition returns to a working main screen',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    final camera = StreamFakeCameraService();
    final voice = ScriptedVoiceController();
    await pumpFamiliarFacesHome(tester, camera: camera, voice: voice);

    await tester.tap(find.text('RECOGNIZE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('STOP RECOGNITION'), findsOneWidget);

    await holdAndSay(tester, voice, _currencyWords);
    expect(
      find.byType(CurrencyRecognitionScreen, skipOffstage: false),
      findsOneWidget,
    );

    // Close Currency Recognition: the previous screen comes back with its
    // lifecycle intact (the run was stopped, so the title card gate is back).
    final navigator = Navigator.of(
      tester.element(
        find.byType(CurrencyRecognitionScreen, skipOffstage: false),
      ),
    );
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(CurrencyRecognitionScreen, skipOffstage: false),
        findsNothing);
    expect(
      find.byType(FamiliarFacesScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('RECOGNIZE'), findsOneWidget);

    // The assistant must still work after the round trip: a second hold opens
    // Currency Recognition again (and again only once).
    await holdAndSay(tester, voice, _currencyWords);
    expect(voice.beginCalls, 2);
    expect(
      find.byType(CurrencyRecognitionScreen, skipOffstage: false),
      findsOneWidget,
    );

    await unmount(tester);
  });
}
