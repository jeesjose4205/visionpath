import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/detected_object.dart';
import '../models/depth_scene.dart';
import '../models/navigation_decision.dart';
import '../models/path_analysis.dart';
import '../models/app_settings.dart';
import '../models/rgb_frame.dart';
import '../services/camera_service.dart';
import '../services/depth/depth_engine.dart';
import '../services/depth_analysis_service.dart';
import '../services/instruction_manager.dart';
import '../services/navigation_service.dart';
import '../services/object_detection_service.dart';
import '../services/path_analysis_service.dart';
import '../services/position_detection_service.dart';
import '../services/settings_service.dart';
import '../services/vibration_service.dart';
import '../services/voice_service.dart';
import '../services/visora/visora_config.dart';
import '../services/visora/visora_session.dart';
import '../services/visora/visora_wake_word.dart';
import '../widgets/camera_preview_fit.dart';
import '../widgets/depth_debug_overlay.dart';
import '../widgets/detection_overlay.dart';
import '../widgets/settings_button.dart';
import '../widgets/sos_gesture.dart';
import '../widgets/sound_mode_button.dart';
import '../widgets/visora/visora_overlay.dart';
import 'familiar_faces_screen.dart';
import 'read_text_screen.dart';

/// Navigate screen - camera-based visual navigation assistance.
///
/// Pipeline per frame:
/// CameraImage -> frame sampling (5 FPS) -> YUV->RGB -> YOLO predict ->
/// DetectedObject -> position analysis -> depth analysis -> path analysis ->
/// navigation decision -> instruction manager -> voice -> UI.
enum _NavState {
  idle('Ready to navigate', 'Press START NAVIGATION'),
  starting('Starting navigation...', 'Preparing camera and model'),
  cameraReady('Camera ready', 'Scanning for objects...'),
  analyzing('Analyzing path', 'Monitoring your surroundings'),
  clear('Path appears clear', 'Continue forward'),
  obstacle('Obstacle detected', 'Use the instruction below'),
  danger('Danger - slow down', 'Proceed with extreme caution'),
  stopped('Navigation stopped', 'Press START NAVIGATION');

  const _NavState(this.status, this.instruction);

  final String status;
  final String instruction;
}

class NavigateScreen extends StatefulWidget {
  const NavigateScreen({super.key});

  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen>
    with SingleTickerProviderStateMixin {
  // Carousel paging transition: the route keeps these exact timings, and the
  // return-greeting below waits them out too — a shorter wait would let the
  // popped screen's dispose() -> _voice.stop() cut the greeting mid-word.
  static const _kPushDuration = Duration(milliseconds: 800);
  static const _kReverseDuration = Duration(milliseconds: 680);

  _NavState _navState = _NavState.idle;
  bool _voiceGuidance = true;
  DateTime _greetingGuardUntil = DateTime.fromMillisecondsSinceEpoch(0);

  // Visora assistant: wake-word detector armed while this screen is live.
  VisoraWakeWordDetector? _wakeWord;

  // ------------------------------------------------------------
  // INTRODUCTORY TITLE CARD
  // ------------------------------------------------------------
  //
  // The title card covers the camera rectangle when the screen is opened and
  // again after each STOP NAVIGATION, and fades out to reveal the live
  // preview when START NAVIGATION is pressed.

  bool _showIntroCard = true;
  late final AnimationController _introController;

  String _detectionStatus = '';
  String _detectedObject = 'No objects detected';
  String _inferenceStatus = 'Initializing...';

  // Frame sampling
  Timer? _inferenceTimer;
  bool _inferenceInProgress = false;
  int _inferenceTicks = 0;
  int _framesObserved = 0;

  // Guards late in-flight inferences that are still awaiting when the user
  // stops navigation: a finished blob must never flip the UI back into a
  // running state, speak, or refresh results after STOP.
  int _runGeneration = 0;

  CameraImage? _latestCameraImage;

  // Pipeline services (stateful pieces owned by this screen).
  final InstructionManager _instructionManager = InstructionManager();
  final VoiceService _voiceService = VoiceService();

  ObjectDetectionService? _objectDetectionService;
  NavigationService? _navigationService;

  // Depth analysis (relative, on-device). `_depthStatusText` drives the small
  // DEPTH chip over the preview; `_activeDepthScene` feeds the debug overlay.
  DepthAnalysisService? _depthService;
  String _depthStatusText = 'DEPTH OFF';
  DepthScene? _activeDepthScene;

  // ------------------------------------------------------------
  // SWIPE NAVIGATION (this screen is the main/centre page)
  // ------------------------------------------------------------
  //
  // Swipe LEFT  -> Familiar Faces
  // Swipe RIGHT -> Read Text
  // Both pages pop back here, and Android back returns to Home underneath.

  double _swipeDx = 0;
  bool _swipeNavLocked = false;

  void _onSwipeStart(DragStartDetails details) {
    _swipeDx = 0;
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    _swipeDx += details.delta.dx;
  }

  void _onSwipeEnd(DragEndDetails details) {
    if (_swipeNavLocked || SosGestureOverlay.sosSwipeActive || !mounted) return;

    final velocity = details.primaryVelocity ?? 0;
    final distance = _swipeDx;

    // Ignore tiny horizontal movements and accidental vertical gestures.
    if (velocity.abs() < 300 && distance.abs() < 80) return;

    final direction = velocity != 0 ? velocity : distance;
    _pushSide(direction < 0);
  }

  /// Opens the page on the chosen side with a subtle horizontal slide.
  /// Locked while a page is up so one swipe can never trigger twice.
  Future<void> _pushSide(bool fromRight) async {
    if (_swipeNavLocked || SosGestureOverlay.sosSwipeActive || !mounted) return;

    final Widget screen = fromRight
        ? const FamiliarFacesScreen()
        : const ReadTextScreen();

    _swipeNavLocked = true;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: _kPushDuration,
        reverseTransitionDuration: _kReverseDuration,
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        // Carousel: the screens move together on a single horizontal track, like a
        // photo pager. The incoming screen tracks in from the swipe side while
        // the outgoing screen slides away in the same direction; the same
        // motion plays in reverse when swiping/backing out of the opened screen.
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final side = fromRight ? 1.0 : -1.0;
          return AnimatedBuilder(
            animation: Listenable.merge([animation, secondaryAnimation]),
            child: child,
            builder: (context, child) {
              final t = Curves.easeInOutCubic.transform(animation.value);
              final s = Curves.easeInOutCubic.transform(secondaryAnimation.value);
              // Covered route (t=1): slides out opposite to the incoming side.
              // Incoming route (s=0): slides in from the incoming side to rest.
              final dx = side * (1 - t - s);
              return FractionalTranslation(
                translation: Offset(dx, 0),
                child: child,
              );
            },
          );
        },
      ),
    );
    // The pop future resolves the instant the route is popped, but the popped
    // screen is only unmounted (running dispose() -> _voice.stop()) after its
    // exit animation finishes. flutter_tts shares ONE native engine, so that
    // late stop would cut the greeting off mid-word ("nav..."). Hold the swipe
    // lock and announce only after the old screen has fully torn down.
    await Future<void>.delayed(_kReverseDuration);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _swipeNavLocked = false;
    if (mounted) _speakNavigationGreeting();
  }

  void _speakNavigationGreeting() {
    // The greeting announces which screen is open. It follows the global
    // voice switch (and the on-screen speaker mute) exactly like Read Text
    // and Familiar Faces, NOT the Navigation/Detection voice sub-toggles.
    if (!_voiceService.enabled) return;
    // Give the greeting the floor briefly so live guidance can't cut it off
    // the instant the screen opens or is returned to.
    _greetingGuardUntil =
        DateTime.now().add(const Duration(milliseconds: 5000));
    _voiceService.speak(
      'Navigation. Navigate safely with real-time obstacle detection '
      'and voice guidance.',
    );
  }

  @override
  void initState() {
    super.initState();
    _applySettings();
    SettingsService.instance.addListener(_applySettings);
    _initializeObjectDetection();
    _initializeDepthAnalysis();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    )..forward();
    _initVisora();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Pre-warm the camera controller so START NAVIGATION reveals a live
      // preview immediately instead of a frozen black rectangle while the
      // camera wakes up (~1-2s on a cold start).
      unawaited(
        Provider.of<CameraService>(context, listen: false).initializeController(),
      );
      _speakNavigationGreeting();
    });
  }

  // ------------------------------------------------------------
  // VISORA ASSISTANT (wake word + web speech host)
  // ------------------------------------------------------------

  void _initVisora() {
    // Widget tests have no platform plugins and no native speech stack;
    // the loopback HTTP server for the hidden WebView also leaves timers
    // that fail the test harness. Skip the whole assistant bootstrap there.
    if (Platform.environment['FLUTTER_TEST'] != null) return;
    // The hidden Google speech WebView (hosted at the bottom of the body)
    // must be bound to its loopback server once, or its recognizer never
    // becomes ready inside the assistant overlay.
    unawaited(VisoraSession.instance.webEngine.start());
    if (!VisoraConfig.instance.wakeWordEnabled) return;
    _wakeWord = VisoraWakeWordDetector();
    _wakeWord!.onWake = () => unawaited(_openVisora(autoListen: true));
    unawaited(_wakeWord!.start());
  }

  /// Open the Visora assistant as an overlay above this screen.
  Future<void> _openVisora({bool autoListen = false}) async {
    if (!mounted) return;
    // Hands-free activation hands the microphone to the assistant; the wake
    // word pauses while they talk and resumes when the overlay closes.
    await _wakeWord?.stop();
    if (!mounted) return;
    await VisoraOverlay.show(context, autoListen: autoListen);
    if (mounted) {
      final w = _wakeWord;
      if (w != null) unawaited(w.start());
    }
  }

  /// Applies persisted settings to this screen's live services.
  void _applySettings() {
    final s = SettingsService.instance;
    // Navigation/Detection voice toggles gate LIVE obstacle guidance only;
    // the on-screen greeting still respects the global voice switch.
    _voiceGuidance = s.voiceGuidanceEnabled &&
        s.navigationVoiceEnabled &&
        s.detectionVoiceEnabled;
    setState(() {});
    _voiceService.setEnabled(
        s.voiceGuidanceEnabled && !s.globalVoiceMuted);
    final ods = _objectDetectionService;
    if (ods != null) {
      ods.confidenceThreshold = s.detectionConfidenceThreshold;
    }
    switch (s.guidanceMode) {
      case GuidanceMode.balanced:
        _instructionManager.repeatCooldown = const Duration(milliseconds: 3000);
        break;
      case GuidanceMode.moreFrequent:
        _instructionManager.repeatCooldown = const Duration(milliseconds: 1500);
        break;
      case GuidanceMode.minimal:
        _instructionManager.repeatCooldown = const Duration(milliseconds: 6000);
        break;
    }
    final DepthAnalysisService? depth = _depthService;
    if (depth != null) {
      _depthStatusText = _depthStatusLabel(depth);
    }
  }

  /// Status text for the DEPTH chip over the camera preview.
  String _depthStatusLabel(DepthAnalysisService depth) {
    if (!SettingsService.instance.depthAnalysisEnabled) return 'DEPTH OFF';
    if (depth.engineStatus == DepthEngineStatus.ready) return 'DEPTH ACTIVE';
    if (depth.engineStatus == DepthEngineStatus.loading) return 'DEPTH LOADING';
    return 'DEPTH FALLBACK';
  }

  /// Accent color for the DEPTH chip.
  Color get _depthStatusColor {
    switch (_depthStatusText) {
      case 'DEPTH ACTIVE':
        return const Color(0xFF198754);
      case 'DEPTH LOADING':
        return const Color(0xFF175CD3);
      case 'DEPTH OFF':
        return const Color(0xFF475467);
      default:
        return const Color(0xFFE8590C);
    }
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_applySettings);
    _inferenceTimer?.cancel();
    _introController.dispose();
    _wakeWord?.dispose();
    _instructionManager.reset();
    _voiceService.stop();
    super.dispose();
  }

  // ------------------------------------------------------------
  // INITIALIZE OBJECT DETECTION
  // ------------------------------------------------------------

  Future<void> _initializeObjectDetection() async {
    print('NAVIGATE_INIT_OBJECT_DETECTION_START');

    _objectDetectionService =
        Provider.of<ObjectDetectionService>(context, listen: false);
    _navigationService =
        Provider.of<NavigationService>(context, listen: false);

    if (_objectDetectionService == null || _navigationService == null) {
      print('NAVIGATE_INIT_SERVICES_MISSING');
      return;
    }

    // Apply the persisted Detection sensitivity to the YOLO confidence
    // threshold before the model processes any frame.
    _objectDetectionService!.confidenceThreshold =
        SettingsService.instance.detectionConfidenceThreshold;

    if (!mounted) return;
    setState(() {
      _inferenceStatus = 'Loading YOLO26n model...';
    });

    final bool success = await _objectDetectionService!.initialize();
    print('NAVIGATE_INIT_OBJECT_DETECTION_COMPLETE: success=$success');

    if (!mounted) return;
    setState(() {
      _inferenceStatus = success
          ? 'YOLO26n loaded'
          : 'Model load failed: ${_objectDetectionService!.errorMessage}';
    });
  }

  // ------------------------------------------------------------
  // INITIALIZE DEPTH ANALYSIS
  // ------------------------------------------------------------

  Future<void> _initializeDepthAnalysis() async {
    print('NAVIGATE_INIT_DEPTH_START');
    _depthService = Provider.of<DepthAnalysisService>(context, listen: false);
    if (_depthService == null) return;

    final bool ok = await _depthService!.initialize();
    print('NAVIGATE_INIT_DEPTH_COMPLETE: success=$ok');
    if (!mounted) return;
    setState(() {
      _depthStatusText = _depthStatusLabel(_depthService!);
    });
  }

  // ------------------------------------------------------------
  // START NAVIGATION
  // ------------------------------------------------------------

  /// Hides the introductory title card with a smooth fade + scale-down so the
  /// live camera preview is revealed beneath it. Guarded so a later
  /// [_presentIntroCard] during the fade-out is never cancelled afterwards.
  void _dismissIntroCard() {
    if (!_showIntroCard) return;
    _introController.reverse().whenComplete(() {
      // Only remove the card if no new appearance started while fading out.
      if (mounted && _showIntroCard) {
        setState(() => _showIntroCard = false);
      }
    });
  }

  /// Brings the introductory title card back (e.g. after STOP NAVIGATION)
  /// using the same fade + scale entrance as when the screen opens.
  void _presentIntroCard() {
    if (_showIntroCard) {
      _introController.forward();
      return;
    }
    setState(() => _showIntroCard = true);
    _introController.forward();
  }

  Future<void> _startNavigation() async {
    print('NAVIGATE_START_PRESSED');
    if (_navState == _NavState.starting) return;
    _dismissIntroCard();

    setState(() => _navState = _NavState.starting);
    _runGeneration++;

    // 1. Ensure camera is initialized (single controller).
    final CameraService cameraService =
        Provider.of<CameraService>(context, listen: false);

    if (!cameraService.isInitialized) {
      final bool ok = await cameraService.initializeController();
      if (!ok || !mounted) {
        _showError('Camera could not be started: ${cameraService.errorMessage}');
        setState(() => _navState = _NavState.idle);
        return;
      }
    }

    if (!mounted) return;

    // 2. Attach the navigation frame callback BEFORE starting the stream so a
    //    frame can never arrive without a receiver.
    cameraService.setOnFrameAvailable(_onNavigateFrame);
    print('CAMERA_STREAM_START');
    final bool streamStarted = await cameraService.startImageStream();
    print('CAMERA_STREAM_STARTED: $streamStarted');
    if (!streamStarted) {
      _showError('Image stream failed: ${cameraService.errorMessage}');
      setState(() => _navState = _NavState.idle);
      return;
    }

    if (!mounted) return;

    // 3. Reset per-run pipeline state.
    _instructionManager.reset();
    _latestCameraImage = null;
    _inferenceTicks = 0;
    _framesObserved = 0;
    _inferenceInProgress = false;
    Provider.of<DepthAnalysisService>(context, listen: false).reset();

    setState(() {
      _navState = _NavState.cameraReady;
      _detectionStatus = '';
      _detectedObject = 'No objects detected';
      _activeDepthScene = null;
      _depthStatusText = _depthStatusLabel(
        Provider.of<DepthAnalysisService>(context, listen: false),
      );
    });

    // 4. Begin the 5 FPS sampling loop with single-flight inference.
    _startInferenceLoop();
    print('NAVIGATE_INFERENCE_LOOP_STARTED');
  }

  // ------------------------------------------------------------
  // NAVIGATE FRAME CALLBACK
  // ------------------------------------------------------------

  void _onNavigateFrame(CameraImage image) {
    print('NAVIGATE_FRAME_CALLBACK_RECEIVED');
    _latestCameraImage = image;
    _framesObserved++;
    print('LATEST_CAMERA_IMAGE_SET: frame=$_framesObserved ${image.width}x${image.height}');
  }

  // ------------------------------------------------------------
  // INFERENCE LOOP (frame sampling ~5 FPS, single-flight)
  // ------------------------------------------------------------

  void _startInferenceLoop() {
    _inferenceTimer?.cancel();

    _inferenceTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_navState == _NavState.stopped ||
          _navState == _NavState.idle ||
          !mounted) {
        timer.cancel();
        return;
      }

      // Never overlap inference calls.
      if (_inferenceInProgress) {
        print('NAVIGATE_SKIPPED: inference in progress');
        return;
      }

      final CameraImage? image = _latestCameraImage;
      if (image == null) {
        print('NAVIGATE_TICK_NO_IMAGE: cameraService.latestImage not set yet');
        return;
      }

      _inferenceInProgress = true;
      _runInference(image).whenComplete(() {
        _inferenceInProgress = false;
      });
    });
  }

  // ------------------------------------------------------------
  // INFERENCE PIPELINE
  // ------------------------------------------------------------

  Future<void> _runInference(CameraImage image) async {
    final ObjectDetectionService? ods = _objectDetectionService;
    final NavigationService? nav = _navigationService;
    final CameraService cameraService =
        Provider.of<CameraService>(context, listen: false);

    if (ods == null || nav == null || !mounted) return;

    // Capture the run this inference belongs to; results are dropped when
    // the user starts/stops navigation while the awaits are in flight.
    final int run = _runGeneration;
    bool stale() => !mounted || run != _runGeneration ||
        _navState == _NavState.stopped || _navState == _NavState.idle;

    // Transition CAMERA_READY -> ANALYZING on the first processed frame.
    if (_navState == _NavState.cameraReady) {
      setState(() => _navState = _NavState.analyzing);
    }

    _inferenceTicks++;
    print('NAVIGATE_TICK: $_inferenceTicks framesObserved=$_framesObserved');

    List<DetectedObject> detections;
    try {
      // CameraImage -> YOLO predict -> DetectedObject
      detections = await ods.detectCameraImage(
        image,
        inputRotationQuarterTurns: cameraService.imageRotationQuarterTurns,
      );
    } catch (e, stack) {
      print('NAVIGATE_INFERENCE_ERROR: $e');
      print('NAVIGATE_INFERENCE_STACK: $stack');
      return;
    }

    if (stale()) return;

    // Confidence filtering already applied via predict's confidenceThreshold.

    // Position analysis (LEFT / CENTER / RIGHT) - model independent.
    final PositionDetectionService positionService =
        Provider.of<PositionDetectionService>(context, listen: false);
    detections = positionService.analyze(detections);

    // Depth analysis: real relative-depth scene when the engine is usable,
    // otherwise the legacy box-area heuristic. Never blocks the stream.
    final DepthAnalysisService depthService =
        Provider.of<DepthAnalysisService>(context, listen: false);
    final RgbFrame? frame = ods.lastRgbFrame;

    PathAnalysisResult path;
    DepthScene? scene;
    if (depthService.engineUsable && frame != null) {
      scene = await depthService.analyzeScene(frame, detections);
      detections = scene.enrichedObjects;

      final PathAnalysisService pathService =
          Provider.of<PathAnalysisService>(context, listen: false);
      path = pathService.analyzeWithDepth(scene.objectsWithDepth, scene);
    } else {
      detections = depthService.analyze(detections);

      final PathAnalysisService pathService =
          Provider.of<PathAnalysisService>(context, listen: false);
      path = pathService.analyze(detections);
    }

    if (stale()) return;

    // Feed the final (enriched) detections back to the overlay so every
    // bounding box shows the object's own calibrated distance.
    ods.setResults(detections);

    // Navigation decision.
    nav.decide(path, detections);
    final NavigationDecision decision = nav.lastDecision;

    // Instruction Manager: suppress repeated messages.
    final bool speak = _instructionManager.shouldSpeak(decision);
    final bool greetingActive =
        DateTime.now().isBefore(_greetingGuardUntil);
    if (speak &&
        !greetingActive &&
        _allowAnnouncement(decision, path.primaryBlocker) &&
        !stale()) {
      if (SettingsService.instance.vibrateMode) {
        // Ringer in vibrate mode: haptics replace the spoken guidance.
        VibrationService.instance.vibrateNavigation();
      } else if (_voiceGuidance) {
        _voiceService.speak(nav.lastSpokenMessage);
      }
    }

    if (!mounted || stale()) return;

    setState(() {
      _inferenceTicks++;
      _navState = _mapDecisionToState(decision);
      _updateDetectionFields(detections);
      _activeDepthScene = scene;
      _depthStatusText = _depthStatusLabel(depthService);
    });
  }

  _NavState _mapDecisionToState(NavigationDecision decision) {
    switch (decision) {
      case NavigationDecision.forward:
        return _NavState.clear;
      case NavigationDecision.left:
      case NavigationDecision.right:
        return _NavState.obstacle;
      case NavigationDecision.slow:
        return _NavState.danger;
      case NavigationDecision.stop:
        return _NavState.danger;
    }
  }

  /// Whether a navigation message for [blocker] should be spoken, honoring
  /// the Detection category toggles and close-obstacle warnings setting.
  bool _allowAnnouncement(NavigationDecision decision, DetectedObject? blocker) {
    final s = SettingsService.instance;
    if ((decision == NavigationDecision.stop ||
            decision == NavigationDecision.slow) &&
        !s.closeObstacleWarnings) {
      return false;
    }
    if (blocker == null) return true;
    final cls = blocker.className.toLowerCase();
    if (cls == 'person') return s.peopleAnnouncements;
    if (_vehicleClasses.contains(cls)) return s.vehicleAnnouncements;
    if (_animalClasses.contains(cls)) return s.animalAnnouncements;
    if (_furnitureClasses.contains(cls)) return s.furnitureAnnouncements;
    return s.obstacleAnnouncements;
  }

  static const Set<String> _vehicleClasses = {
    'car',
    'truck',
    'bus',
    'bicycle',
    'motorcycle',
    'train',
    'airplane',
  };

  static const Set<String> _animalClasses = {
    'cat',
    'dog',
    'bird',
    'horse',
    'sheep',
    'cow',
    'elephant',
    'bear',
    'zebra',
    'giraffe',
  };

  static const Set<String> _furnitureClasses = {
    'chair',
    'sofa',
    'couch',
    'table',
    'bench',
    'bed',
    'refrigerator',
    'tv',
    'microwave',
    'oven',
    'toaster',
    'sink',
    'potted plant',
    'book',
    'clock',
    'vase',
    'bottle',
    'bowl',
    'cup',
    'umbrella',
    'backpack',
    'handbag',
    'suitcase',
    'laptop',
    'remote',
    'keyboard',
    'cell phone',
    'mouse',
    'teddy bear',
    'wine glass',
    'knife',
    'spoon',
    'fork',
    'banana',
    'apple',
    'sandwich',
    'orange',
    'broccoli',
    'carrot',
    'pizza',
    'donut',
    'cake',
  };

  void _updateDetectionFields(List<DetectedObject> detections) {
    print('NAVIGATE_RESULTS_UI: ${detections.length} objects');
    if (detections.isEmpty) {
      _detectionStatus = '';
      _detectedObject = 'No objects detected';
      return;
    }

    final StringBuffer sb = StringBuffer();
    for (final d in detections) {
      sb.write('${d.displayName} ${d.horizontalPosition} ${(d.confidence * 100).toInt()}%');
      if (d.proximity != null) sb.write(' ${d.proximity!.label}');
      sb.write(' | ');
    }
    _detectionStatus = sb.toString().replaceFirst(RegExp(r' \| $'), '');
    _detectedObject = '${detections.length} object${detections.length > 1 ? 's' : ''} detected';
  }

  // ------------------------------------------------------------
  // STOP NAVIGATION
  // ------------------------------------------------------------

  Future<void> _stopNavigation() async {
    print('NAVIGATE_STOP_PRESSED');

    // Marks any in-flight inference belonging to the old run as stale BEFORE
    // any await, so it cannot re-enable the pipeline, speak, or overwrite the
    // stopped state once it finally returns.
    _runGeneration++;
    _inferenceTimer?.cancel();

    _instructionManager.reset();
    _voiceService.stop();
    VibrationService.instance.stopVibration();

    if (!mounted) return;

    setState(() {
      _navState = _NavState.stopped;
      _latestCameraImage = null;
      _activeDepthScene = null;
      _detectionStatus = '';
      _detectedObject = 'No objects detected';
    });

    final CameraService cameraService =
        Provider.of<CameraService>(context, listen: false);
    await cameraService.stopImageStream();

    _objectDetectionService?.stop();
    _navigationService?.reset();
    Provider.of<DepthAnalysisService>(context, listen: false).reset();

    if (!mounted) return;

    _presentIntroCard();
  }

  // ------------------------------------------------------------
  // ERROR HANDLING
  // ------------------------------------------------------------

  void _showError(String message) {
    print('NAVIGATE_ERROR: $message');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFD92D20),
      ),
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool compact = size.height < 700;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onSwipeStart,
      onHorizontalDragUpdate: _onSwipeUpdate,
      onHorizontalDragEnd: _onSwipeEnd,

      child: PopScope(
        // The removed header back arrow used to stop navigation before
        // leaving; mirror that with the system back gesture so a running
        // session never leaks its camera stream.
        canPop: _navState == _NavState.idle || _navState == _NavState.stopped,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (_navState != _NavState.idle && _navState != _NavState.stopped) {
            await _stopNavigation();
          }
          // This screen is the app's root route: once navigation has been
          // stopped there is nothing to pop back to, and popping the root
          // throws. Only pop when a screen actually sits underneath.
          if (!mounted) return;
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
        },

        child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFD),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(compact),

              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 18,
                    8,
                    compact ? 14 : 18,
                    compact ? 10 : 16,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        flex: 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildCameraPreview(),
                              if (_showIntroCard)
                                _IntroTitleCard(animation: _introController),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: compact ? 8 : 12),

                      _buildStatusCard(compact),

                      SizedBox(height: compact ? 8 : 12),

                      _buildInstructionCard(compact),

                      SizedBox(height: compact ? 8 : 12),

                      _buildBottomControls(compact),
                    ],
                  ),
                ),
              ),
              _visoraWebViewHost(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Visora's hidden Google speech WebView: 1x1, no paint, no input. It must
  /// stay mounted while this screen is open so the session's recognizer is
  /// ready the moment the assistant overlay asks for the microphone.
  Widget _visoraWebViewHost() {
    // Widget tests set FLUTTER_TEST; the native InAppWebView has no platform
    // channel there, so skip hosting it (the recognizer is unused in tests).
    if (Platform.environment['FLUTTER_TEST'] != null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0,
        child: IgnorePointer(
          child: ClipRect(child: VisoraSession.instance.webEngine.build()),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // HEADER
  // ------------------------------------------------------------

  Widget _buildHeader(bool compact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 18,
        compact ? 8 : 14,
        compact ? 12 : 18,
        4,
      ),
      child: Row(
        children: [
          // Persistent app title, top-left.
          Expanded(
            child: Semantics(
              header: true,
              label: 'VisionPath AI',
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'VisionPath '),
                    TextSpan(
                      text: 'AI',
                      style: const TextStyle(color: Color(0xFF1769E0)),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 20 : 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: const Color(0xFF182230),
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Visora AI assistant
          _HeaderButton(
            icon: Icons.auto_awesome_rounded,
            label: 'Visora AI assistant',
            onTap: () => unawaited(_openVisora()),
          ),

          const SizedBox(width: 10),

          // Ringer switch: sound -> vibrate -> muted.
          SoundModeButton(),

          const SizedBox(width: 10),

          const SettingsButton(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // CAMERA PREVIEW + DETECTION OVERLAY
  // ------------------------------------------------------------

  Widget _buildCameraPreview() {
    return Consumer<CameraService>(
      builder: (context, cameraService, child) {
        final bool initialized = cameraService.isInitialized;

        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF20252B),
              borderRadius: BorderRadius.circular(22),
            ),
            child: initialized
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Single camera preview (same controller as the stream).
                      CameraPreviewFit(controller: cameraService.controller!),

                      // Detection overlay with bounding boxes + labels.
                      if (_navState != _NavState.idle &&
                          _navState != _NavState.stopped &&
                          _objectDetectionService != null)
                        Consumer<ObjectDetectionService>(
                          builder: (context, ods, child) {
                            print('OVERLAY_CONSUMER_OBJECT_COUNT: ${ods.currentResults.length}');
                            return DetectionOverlay(
                              previewSize: MediaQuery.of(context).size,
                              inputSize: displayPreviewSize(
                                cameraService.controller!,
                              ),
                              results: ods.currentResults,
                            );
                          },
                        ),

                      // Scan frame corners.
                      Positioned.fill(
                        child: CustomPaint(painter: _NavigationFramePainter()),
                      ),

                      // AI status pill.
                      Positioned(
                        top: 14,
                        left: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: cameraService.isImageStreamActive
                                      ? Colors.greenAccent
                                      : Colors.white54,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                cameraService.isImageStreamActive
                                    ? 'AI ANALYZING'
                                    : 'CAMERA READY',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Depth status chip (top-right, mirrors the AI pill).
                      Positioned(
                        top: 14,
                        right: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _depthStatusColor.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _depthStatusText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),

                      // Depth debug overlay (opt-in, troubleshooting only).
                      if (SettingsService.instance.depthDebugOverlay &&
                          _activeDepthScene != null)
                        DepthDebugOverlay(scene: _activeDepthScene!),

                      // Detection status (bottom-left).
                      Positioned(
                        left: 14,
                        bottom: 14,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.62,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.60),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _detectionStatus.isNotEmpty
                                ? _detectionStatus
                                : _detectedObject,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.videocam_outlined,
                          color: Colors.white70,
                          size: 58,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Camera Preview',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _inferenceStatus,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // STATUS CARD
  // ------------------------------------------------------------

  Widget _buildStatusCard(bool compact) {
    final bool running = _navState.index >= _NavState.cameraReady.index &&
        _navState != _NavState.stopped;
    final bool danger =
        _navState == _NavState.danger;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 10 : 13,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 46,
            height: compact ? 40 : 46,
            decoration: BoxDecoration(
              color: danger
                  ? const Color(0xFFFDE8E8)
                  : running
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              danger
                  ? Icons.warning_amber_rounded
                  : running
                      ? Icons.radar
                      : Icons.navigation_outlined,
              color: danger
                  ? const Color(0xFFD92D20)
                  : running
                      ? const Color(0xFF198754)
                      : const Color(0xFF475467),
              size: compact ? 21 : 24,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _navState.status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 14 : 15,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF182230),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _navigationService?.lastReason.isNotEmpty ?? false
                      ? _navigationService!.lastReason
                      : 'Monitoring your path',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    color: const Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // INSTRUCTION CARD
  // ------------------------------------------------------------

  Widget _buildInstructionCard(bool compact) {
    // direction icon based on the most recent decision
    IconData directionIcon;
    switch (_navigationService?.lastDecision ?? NavigationDecision.forward) {
      case NavigationDecision.left:
        directionIcon = Icons.arrow_back;
        break;
      case NavigationDecision.right:
        directionIcon = Icons.arrow_forward;
        break;
      case NavigationDecision.slow:
        directionIcon = Icons.slow_motion_video;
        break;
      case NavigationDecision.stop:
        directionIcon = Icons.stop_circle_outlined;
        break;
      case NavigationDecision.forward:
        directionIcon = Icons.arrow_upward;
        break;
    }

    final String instructionText =
        _navigationService?.lastSpokenMessage.isNotEmpty ?? false
            ? _navigationService!.lastSpokenMessage
            : _navState.instruction;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E5FF)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 44 : 50,
            height: compact ? 44 : 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              directionIcon,
              color: const Color(0xFF175CD3),
              size: compact ? 24 : 27,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEXT ACTION',
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF667085),
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  instructionText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF182230),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // BOTTOM CONTROLS
  // ------------------------------------------------------------

  Widget _buildBottomControls(bool compact) {
    final bool running = _navState.index >= _NavState.cameraReady.index &&
        _navState != _NavState.stopped;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: compact ? 48 : 54,
          child: ElevatedButton.icon(
            onPressed: running ? _stopNavigation : _startNavigation,
            style: ElevatedButton.styleFrom(
              backgroundColor: running
                  ? const Color(0xFFD92D20)
                  : const Color(0xFF175CD3),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: Icon(
              running ? Icons.stop_circle_outlined : Icons.play_arrow_rounded,
              size: 25,
            ),
            label: Text(
              running ? 'STOP NAVIGATION' : 'START NAVIGATION',
              style: TextStyle(
                fontSize: compact ? 14 : 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// HEADER BUTTON
// ============================================================

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? label;

  const _HeaderButton({
    required this.icon,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF344054),
              size: 21,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// INTRODUCTORY TITLE CARD
// ============================================================
//
// Rendered inside the camera-preview rectangle with the same dimensions,
// position and rounded corners. It covers the preview until the user presses
// START NAVIGATION, then fades and scales away to reveal the live camera.

class _IntroTitleCard extends StatelessWidget {
  const _IntroTitleCard({required this.animation});

  /// Drives the entrance (fade in + very slight scale) and the departure
  /// when the user presses START NAVIGATION.
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Semantics(
      container: true,
      label: 'VisionPath AI. Camera-based path assistance.',
      child: ExcludeSemantics(
        child: FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: const _IntroCardContent(),
          ),
        ),
      ),
    );
  }
}

class _IntroCardContent extends StatelessWidget {
  const _IntroCardContent();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0B1424),
            Color(0xFF14203F),
            Color(0xFF1B2A5E),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Soft abstract glow shapes (blue + violet accents).
          Positioned(
            top: -70,
            right: -60,
            child: _GlowBlob(size: 230, color: const Color(0xFF2E7CF6)),
          ),
          Positioned(
            bottom: -90,
            left: -70,
            child: _GlowBlob(size: 260, color: const Color(0xFF7C5BFF)),
          ),
          Positioned(
            bottom: 120,
            right: -50,
            child: _GlowBlob(size: 180, color: const Color(0xFF4C8DFF)),
          ),

          // Hairline border for a premium sheen.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0x1FFFFFFF)),
              ),
            ),
          ),

          // Content, auto-fitted to any camera rectangle size.
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, cons) {
                final bool short = cons.maxHeight < 300;
                final bool narrow = cons.maxWidth < 300;
                final double padH = narrow ? 20 : 28;
                final double padV = short ? 14 : 20;
                final double innerWidth =
                    (cons.maxWidth - padH * 2).clamp(160.0, 420.0);

                return Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: padH, vertical: padV),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: innerWidth),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LogoMark(size: short ? 56 : 68),
                          const SizedBox(height: 14),
                          _BrandTitle(fontSize: short ? 22 : 27),
                          const SizedBox(height: 8),
                          const _Tagline(),
                          const SizedBox(height: 10),
                          Container(
                            width: 46,
                            height: 3,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2E7CF6), Color(0xFF7C5BFF)],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const _SupportMessage(),
                          const SizedBox(height: 24),
                          const _CameraReadyPanel(),
                          const SizedBox(height: 20),
                          const _PageDots(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.30),
          width: 1.4,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E7CF6), Color(0xFF6E5BFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF60A5FF).withValues(alpha: 0.45),
            blurRadius: 26,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(Icons.visibility_rounded, color: Colors.white, size: size * 0.48),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'VisionPath ',
            style: TextStyle(
              fontSize: fontSize,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: Colors.white,
            ),
          ),
          TextSpan(
            text: 'AI',
            style: TextStyle(
              fontSize: fontSize,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: const Color(0xFF8FB6FF),
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'NAVIGATION',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.4,
        color: Color(0xFFDCE7FF),
      ),
    );
  }
}

class _SupportMessage extends StatelessWidget {
  const _SupportMessage();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Navigate safely with real-time\nobstacle detection and voice guidance',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.45,
        fontWeight: FontWeight.w500,
        color: Color(0xCCFFFFFF),
      ),
    );
  }
}

class _CameraReadyPanel extends StatelessWidget {
  const _CameraReadyPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.center_focus_strong_rounded,
            color: Color(0xFF9FC6FF),
            size: 22,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Camera guidance',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Real-time assistance, ready to begin',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: Color(0xB3FFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i == 1
                ? const Color(0xFF9FC6FF)
                : Colors.white.withValues(alpha: 0.28),
          ),
        );
      }),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.55),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// NAVIGATION FRAME PAINTER
// ============================================================

class _NavigationFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.75)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final double left = size.width * 0.12;
    final double right = size.width * 0.88;
    final double top = size.height * 0.18;
    final double bottom = size.height * 0.82;

    const double corner = 28;

    canvas.drawLine(Offset(left, top), Offset(left + corner, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left, top + corner), paint);
    canvas.drawLine(Offset(right, top), Offset(right - corner, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + corner), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left + corner, bottom), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - corner), paint);
    canvas.drawLine(Offset(right, bottom), Offset(right - corner, bottom), paint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - corner), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}