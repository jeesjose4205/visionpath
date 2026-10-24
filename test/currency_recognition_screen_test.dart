import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:visionpath/models/currency_recognition.dart';
import 'package:visionpath/screens/currency_recognition_screen.dart';
import 'package:visionpath/services/camera_service.dart';
import 'package:visionpath/services/currency_recognition_service.dart';
import 'package:visionpath/services/settings_service.dart';
import 'package:visionpath/widgets/press_and_hold_voice_region.dart';

/// CameraService that never touches a platform channel.
///
/// The screen only needs "initialized, stream started, here is my frame
/// callback", so the faked surface is a controller-free stream that the test
/// drives by hand.
class FakeCameraService extends CameraService {
  int startCalls = 0;
  int stopCalls = 0;
  OnFrameAvailable? callback;
  bool failStart = false;

  @override
  bool get isInitialized => !failStart;

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
  void setOnFrameAvailable(OnFrameAvailable cb) {
    callback = cb;
  }
}

/// CurrencyRecognitionService with canned outcomes, so widget tests do not
/// depend on bundled models (this build ships none).
class FakeCurrencyService extends CurrencyRecognitionService {
  FakeCurrencyService({
    this.available = true,
    this.result,
  });

  bool available;
  CurrencyInferenceResult? result;
  int analyzeCalls = 0;
  Set<CurrencyKind>? lastKinds;

  @override
  bool get anyModelAvailable => available;

  @override
  bool get hasBanknoteModel => available;

  @override
  bool get hasCoinModel => available;

  @override
  String? get loadError =>
      available ? null : 'No currency recognition model is bundled with this build.';

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<void> reload() async {}

  @override
  Future<CurrencyInferenceResult> analyze(
    Uint8List rgba,
    int width,
    int height, {
    Set<CurrencyKind>? kinds,
  }) async {
    analyzeCalls++;
    lastKinds = kinds;
    return result ??
        const CurrencyInferenceResult.uncertain(reason: 'test frame');
  }
}

/// A minimal upright YUV420 frame.
CameraImage yuvFrame({int width = 4, int height = 4}) {
  final Uint8List y = Uint8List(width * height);
  final Uint8List u = Uint8List((width ~/ 2) * (height ~/ 2));
  final Uint8List v = Uint8List((width ~/ 2) * (height ~/ 2));
  return CameraImage.fromPlatformInterface(
    CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
      planes: <CameraImagePlane>[
        CameraImagePlane(bytes: y, bytesPerRow: width, bytesPerPixel: 1),
        CameraImagePlane(bytes: u, bytesPerRow: width ~/ 2, bytesPerPixel: 1),
        CameraImagePlane(bytes: v, bytesPerRow: width ~/ 2, bytesPerPixel: 1),
      ],
      width: width,
      height: height,
    ),
  );
}

const CurrencyRecognition hundredNote = CurrencyRecognition(
  kind: CurrencyKind.banknote,
  denomination: 100,
  confidence: 0.93,
  reliable: true,
);

void main() {
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

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeCameraService camera,
    required FakeCurrencyService service,
    Future<CameraPermissionOutcome> Function()? permission,
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
          home: CurrencyRecognitionScreen(
            service: service,
            requestCameraPermission: permission ??
                () async => CameraPermissionOutcome.granted,
            analysisInterval: Duration.zero,
          ),
        ),
      ),
    );
    // Let _loadModels complete and the intro card animation run.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('shows the model-unavailable error with a retry button',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    final FakeCameraService camera = FakeCameraService();
    final FakeCurrencyService service = FakeCurrencyService(available: false);
    await pumpScreen(tester, camera: camera, service: service);

    expect(find.textContaining('model'), findsWidgets);
    expect(find.text('RETRY'), findsWidgets);

    // A screen without models must never have started a camera stream.
    expect(camera.startCalls, 0);
  });

  testWidgets('START SCANNING starts the camera stream', (WidgetTester tester) async {
    setPhoneSurface(tester);
    final FakeCameraService camera = FakeCameraService();
    final FakeCurrencyService service = FakeCurrencyService();
    await pumpScreen(tester, camera: camera, service: service);

    // Two buttons can carry the same label (intro card + controls); the first
    // one tapped is enough.
    await tester.tap(find.text('START SCANNING').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(camera.startCalls, greaterThanOrEqualTo(1));
    // The status card switches to the scanning phase ('Analyzing'); the
    // SCANNING pill itself only renders on top of a real camera preview.
    expect(find.text('Analyzing'), findsOneWidget);
    expect(find.byType(PressAndHoldVoiceRegion), findsOneWidget);
  });

  testWidgets('two agreeing frames lock the result card', (WidgetTester tester) async {
    setPhoneSurface(tester);
    final FakeCameraService camera = FakeCameraService();
    final FakeCurrencyService service = FakeCurrencyService(
      result: const CurrencyInferenceResult.recognized(hundredNote),
    );
    await pumpScreen(tester, camera: camera, service: service);

    await tester.tap(find.text('START SCANNING').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final OnFrameAvailable? frame = camera.callback;
    expect(frame, isNotNull);

    // First frame: checking, not locked in.
    frame!(yuvFrame());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('₹100 Banknote'), findsNothing);
    expect(find.text('Checking... hold steady.'), findsOneWidget);

    // Second agreeing frame locks the result.
    frame(yuvFrame());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('₹100 Banknote'), findsOneWidget);
    expect(find.textContaining('Identified'), findsWidgets);
    expect(service.analyzeCalls, 2);

    // The mode defaults to Both, so both kinds are allowed through.
    expect(service.lastKinds, contains(CurrencyKind.banknote));
    expect(service.lastKinds, contains(CurrencyKind.coin));
  });

  testWidgets('a denied camera permission blocks the scan with an explanation',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    final FakeCameraService camera = FakeCameraService();
    final FakeCurrencyService service = FakeCurrencyService();
    await pumpScreen(
      tester,
      camera: camera,
      service: service,
      permission: () async => CameraPermissionOutcome.denied,
    );

    await tester.tap(find.text('START SCANNING').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(camera.startCalls, 0);
    expect(find.textContaining('Camera permission is required'), findsOneWidget);
    expect(find.text('ALLOW CAMERA & RETRY'), findsOneWidget);
  });

  testWidgets('disposing the screen clears the frame callback',
      (WidgetTester tester) async {
    setPhoneSurface(tester);
    final FakeCameraService camera = FakeCameraService();
    final FakeCurrencyService service = FakeCurrencyService();
    await pumpScreen(tester, camera: camera, service: service);

    await tester.tap(find.text('START SCANNING').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(camera.callback, isNotNull);
    final int before = service.analyzeCalls;

    // Unmount the whole app tree.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));

    // The callback the screen leaves behind is a no-op: feeding it a frame
    // must not reach the service after disposal.
    camera.callback!(yuvFrame());
    await tester.pump(const Duration(milliseconds: 50));
    expect(service.analyzeCalls, before);
    expect(camera.stopCalls, greaterThanOrEqualTo(1));
  });
}
