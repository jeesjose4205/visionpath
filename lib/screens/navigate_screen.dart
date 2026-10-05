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
import '../services/scene_announcer.dart';
import '../services/settings_service.dart';
import '../services/speech_capture_service.dart';
import '../services/target_navigation_service.dart';
import '../services/vibration_service.dart';
import '../services/voice_service.dart';
import '../services/voice_command_controller.dart';
import '../widgets/camera_preview_fit.dart';
import '../widgets/depth_debug_overlay.dart';
import '../widgets/detection_overlay.dart';
import '../widgets/settings_button.dart';
import '../widgets/settings_scope.dart';
import '../widgets/sos_gesture.dart';
import '../widgets/sound_mode_button.dart';
import '../widgets/target_status_chip.dart';
import '../widgets/press_and_hold_voice_region.dart';
import '../widgets/voice_search_overlay.dart';
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

  /// Set while [_stopNavigation] is tearing the run down.
  ///
  /// Its teardown is asynchronous (camera stream, depth reset), so BACK can be
  /// pressed again mid-flight. Without this guard a second press would start a
  /// second teardown on top of the first.
  bool _isStopping = false;

  /// Cached so dispose() can release the camera without touching BuildContext.
  CameraService? _cameraService;
  bool _voiceGuidance = true;
  DateTime _greetingGuardUntil = DateTime.fromMillisecondsSinceEpoch(0);

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

  // Target Object Navigation ("find a chair"). Fed from the same analysed
  // frames as the obstacle pipeline; it only decides what to say about the
  // target and never touches the camera or the model.
  final TargetNavigationService _targetNavigation = TargetNavigationService.instance;

/// Last target session this screen spoke for; a change means a new command
/// arrived and the routine queue must yield to it.
int _lastTargetSessionId = 0;

/// Press-and-hold voice assistant. Owns the hold gesture, the microphone and the
/// transcript; this screen only routes what was said into the target navigator.
final VoiceCommandController _voiceCommand = VoiceCommandController();

  /// True while the assistant is acting on the transcript a hold produced.
  bool _commandInFlight = false;

  ObjectDetectionService? _objectDetectionService;
  NavigationService? _navigationService;
  DepthAnalysisService? _depthAnalysisService;

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

  /// True while the navigation process owns this screen.
  ///
  /// Derived from the existing [_navState] rather than a second flag, so it can
  /// never disagree with the state the UI is showing. `starting` counts as
  /// active: the user must not be able to swipe away while the camera and model
  /// are still being prepared, and neither may they during `stopped`'s async
  /// teardown.
  ///
  /// A target search can only run inside a live pipeline, so it is covered here
  /// too; the explicit check keeps that guarantee visible.
  bool get _navigationActive =>
      !(_navState == _NavState.idle || _navState == _NavState.stopped) ||
      _targetNavigation.isActive ||
      _isStopping;

  /// Horizontal paging is only for the carousel. While navigation is running the
  /// user must stay put, so the swipe is rejected and nothing is pushed.
  bool get _horizontalSwipeEnabled => !_navigationActive;

  void _onSwipeStart(DragStartDetails details) {
    _swipeDx = 0;
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    _swipeDx += details.delta.dx;
  }

  void _onSwipeEnd(DragEndDetails details) {
    // Rejected, not queued: the screen simply does not change and navigation
    // keeps running untouched.
    if (!_horizontalSwipeEnabled) return;
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
    // Checked again here because this is the only path that actually leaves the
    // screen, and it can be reached from the drag handlers above.
    if (!_horizontalSwipeEnabled) return;
    if (_swipeNavLocked || SosGestureOverlay.sosSwipeActive || !mounted) return;

    final Widget screen = fromRight
        ? const FamiliarFacesScreen()
        : const ReadTextScreen();

    // Reduced Animations collapses the swipe transition to an instant cut. The
    // post-pop delay below is kept regardless, because it exists to let the
    // outgoing screen's TTS teardown finish, not to pace the animation.
    final bool reduceMotion = SettingsScope.of(context).reduceAnimations;
    final Duration pushDuration =
        reduceMotion ? Duration.zero : _kPushDuration;
    final Duration reverseDuration =
        reduceMotion ? Duration.zero : _kReverseDuration;

    _swipeNavLocked = true;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: pushDuration,
        reverseTransitionDuration: reverseDuration,
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
    await Future<void>.delayed(reverseDuration);
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
    _targetNavigation.addListener(_onTargetNavigationChanged);
    // The controller reports the hold opening and closing, which is exactly when
    // the object announcements must stop and start again.
    _voiceCommand.addListener(_syncSceneVoiceSuppression);
    _initializeObjectDetection();
    _initializeDepthAnalysis();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    )..forward();
    _initVoiceCommands();
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
  // VOICE COMMANDS (press-and-hold + hidden web speech host)
  // ------------------------------------------------------------

  void _initVoiceCommands() {
    // Widget tests have no platform plugins and no native speech stack;
    // the loopback HTTP server for the hidden WebView also leaves timers
    // that fail the test harness. Skip the whole speech bootstrap there.
    if (Platform.environment['FLUTTER_TEST'] != null) return;
    // The hidden Google speech WebView (hosted at the bottom of the body)
    // must be bound to its loopback server once, or its recognizer never
    // becomes ready for a press-and-hold command.
    unawaited(SpeechCaptureService.instance.webEngine.start());
    // No wake-word or always-on listener here on purpose. Either would own a
    // second speech-recognition session and seize the microphone the instant a
    // hold ended, so the two engines would compete for the same audio.
  }

  /// Applies persisted settings to this screen's live services.
  void _applySettings() {
    final s = SettingsService.instance;
    // Navigation/Detection voice toggles gate LIVE obstacle guidance only.
    // The global Voice Guidance / Global Voice Mute combination is enforced
    // centrally by VoiceService, so it is deliberately NOT duplicated here.
    _voiceGuidance = s.navigationVoiceEnabled && s.detectionVoiceEnabled;
    setState(() {});
    // Feature intent only ("navigation wants to speak"), never the global
    // mute, so this screen cannot re-enable what the user turned off.
    _voiceService.setEnabled(true);
    final ods = _objectDetectionService;
    if (ods != null) {
      ods.confidenceThreshold = s.detectionConfidenceThreshold;
    }
    // Guidance Frequency (1.5/3/6 s) and Announcement Frequency (2/3/5/8 s) both
    // mean "don't interrupt faster than this", so the effective cooldown is the
    // more restrictive of the two. See [InstructionManager] for the rationale.
    final Duration guidanceCooldown;
    switch (s.guidanceMode) {
      case GuidanceMode.moreFrequent:
        guidanceCooldown = const Duration(milliseconds: 1500);
        break;
      case GuidanceMode.balanced:
        guidanceCooldown = const Duration(milliseconds: 3000);
        break;
      case GuidanceMode.minimal:
        guidanceCooldown = const Duration(milliseconds: 6000);
        break;
    }
    final Duration announcementCooldown = Duration(
      seconds: s.announcementCooldownSeconds,
    );
    _instructionManager.repeatCooldown =
        guidanceCooldown > announcementCooldown
        ? guidanceCooldown
        : announcementCooldown;
    _instructionManager.repeatEnabled = s.repeatInstruction;
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
    _targetNavigation.removeListener(_onTargetNavigationChanged);
    _voiceCommand.removeListener(_syncSceneVoiceSuppression);
    // The screen that owns the voice channel goes away with its target.
_targetNavigation.setPipelineActive(false);
_targetNavigation.drainMessages();
    // The hold gesture must not outlive the screen, and neither may the
    // microphone it opened.
_voiceCommand.dispose();
    // Invalidate in-flight work before releasing anything, so a frame that
    // returns after the screen is gone cannot speak, vibrate, or revive the
    // pipeline. The PopScope above normally guarantees the route cannot be
    // disposed while a run is live; this is the backstop for any other removal.
    _runGeneration++;
    _inferenceTimer?.cancel();
    unawaited(_cameraService?.stopImageStream());
    _objectDetectionService?.stop();
    _depthAnalysisService?.reset();
    _introController.dispose();
    _instructionManager.reset();
    _voiceService.stop();
    super.dispose();
  }

  // ------------------------------------------------------------
  // TARGET OBJECT NAVIGATION
  // ------------------------------------------------------------
  //
  // "Find a chair" arrives by press-and-hold (or typed); this screen is the
  // only place that owns the voice channel, so it speaks the target lines and
  // repaints the small status chip over the preview.

  void _onTargetNavigationChanged() {
    if (!mounted) return;
    // Starting or ending a target run changes who owns the voice channel, so the
    // object announcements follow it.
    _syncSceneVoiceSuppression();
    // An explicit command outranks whatever the environment had queued, so the
    // answer to "find a chair" is the first thing heard.
    final int session = _targetNavigation.sessionId;
    if (session != _lastTargetSessionId) {
      _lastTargetSessionId = session;
      _voiceService.clearSpeechQueue();
    }
    // Live guidance obeys the same switches as obstacle guidance; the global
    // mute is already folded into `_voiceService.enabled`.
    if (_voiceGuidance && _voiceService.enabled) {
      for (final String message in _targetNavigation.drainMessages()) {
        // Queued, never interrupting: a target update waits for the sentence
        // before it instead of cutting it off. A refusal here means the
        // sentence is blank or already spoken, and there is deliberately no
        // fallback to speak() -- that path interrupts whatever is playing and
        // would reintroduce overlapping speech.
        _voiceService.enqueueSpeech(message);
      }
    } else {
      _targetNavigation.drainMessages();
    }
    setState(() {});
  }

  // ------------------------------------------------------------
  // PRESS-AND-HOLD VOICE ASSISTANT
  // ------------------------------------------------------------
  //
  // The microphone belongs to the one session in the app. Press-and-hold is a
  // deliberate gesture, so nothing runs in the background between holds: the
  // recognizer is opened on press and closed on release.

  /// True from the moment a hold is recognized until the command it produced has
  /// been dealt with, and for the whole of a target search.
  ///
  /// The microphone owns the floor during a hold, and once a target is being
  /// tracked its guidance is the only thing the user needs to hear, so the
  /// generic object sentences stay out of the way until it is reached or
  /// cancelled.
  bool get _sceneAnnouncementsSuppressed =>
      _voiceCommand.isHolding || _commandInFlight || _targetNavigation.isActive;

  /// The one place the detected-object voice is switched off.
  ///
  /// Kept as a single method because the rule has to hold no matter what starts
  /// or stops the hold. Target navigation keeps the generic object sentences
  /// suppressed for its whole run, which is what keeps its guidance audible.
  void _syncSceneVoiceSuppression() {
    // Nullable until the first frame resolves it from Provider.
    _navigationService?.sceneVoiceMuted = _sceneAnnouncementsSuppressed;
  }

  void _startAlwaysOnListening() {
    _voiceCommand
      ..onCommand = _onVoiceCommand
      ..onFailure = _onVoiceCommandFailure;
  }

  void _stopAlwaysOnListening() {
    _voiceCommand
      ..onCommand = null
      ..onFailure = null;
    unawaited(_voiceCommand.cancel());
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
    // Cached rather than looked up during teardown: dispose() must not touch
    // BuildContext, and stopNavigation() runs after async gaps.
    _cameraService = Provider.of<CameraService>(context, listen: false);
    _depthAnalysisService =
        Provider.of<DepthAnalysisService>(context, listen: false);
    // A hold cannot have started yet, but the run's initial state still has to
    // be applied to the freshly resolved service.
    _syncSceneVoiceSuppression();

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
    // The card is removed in whenComplete, so the fade is load-bearing: it must
    // still run (or be skipped outright) for the camera to be revealed. Reduced
    // animations therefore skip the fade instead of muting its ticker.
    if (!SettingsScope.of(context).animationsEnabled) {
      setState(() => _showIntroCard = false);
      return;
    }
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
    // A previous teardown is still releasing the camera. Starting now would
    // race it and can leave two image streams behind.
    if (_isStopping) return;
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
    // A new run starts from a clean scene: no pending announcement and no
    // object history carried over from the previous run.
    _navigationService?.reset();
    // Nothing from a previous run may still be waiting to be spoken.
    _voiceService.clearSpeechQueue();
// A target request only makes sense while frames are being analysed.
_targetNavigation.setPipelineActive(true, runId: _runGeneration);
    // "Find a chair" has to work out loud, with no button: the microphone
    // reopens by itself for as long as this run lasts.
    _startAlwaysOnListening();

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
    nav.decide(path, detections, includeObject: _allowObjectAnnouncement);
    final NavigationDecision decision = nav.lastDecision;

    // Instruction Manager: suppress repeated messages.
    //
    // Routine guidance is driven by scene change alone: the same unchanged
    // scene is announced once and then stays silent. Safety decisions keep the
    // existing cooldown so a hazard is still re-stated periodically.
    final bool cooldownSpoken = _instructionManager.shouldSpeak(decision);
    final bool sceneChanged = nav.announcementChanged;
    final bool urgent = decision == NavigationDecision.stop ||
        decision == NavigationDecision.slow;
    final bool speak = urgent ? cooldownSpoken : sceneChanged;
    final bool greetingActive =
        DateTime.now().isBefore(_greetingGuardUntil);
    if (speak &&
        !greetingActive &&
        _allowAnnouncement(decision, path.primaryBlocker) &&
        !stale()) {
      if (SettingsService.instance.vibrateMode) {
        // Ringer in vibrate mode: haptics replace the spoken guidance.
        VibrationService.instance.vibrateNavigation();
        nav.commitAnnouncement();
      } else if (_voiceGuidance) {
        if (urgent) {
          // A safety warning must not wait behind a queued scene sentence.
          _instructionManager.noteSpoken(<String>[nav.lastSpokenMessage]);
          _voiceService.speak(nav.lastSpokenMessage);
          nav.commitAnnouncement();
        } else {
          // Each object becomes its own queued sentence. The queue plays them
          // one at a time, so nothing is cut off and an unchanged scene cannot
          // pile up duplicates.
          final List<String> sentences = nav.pendingSentences;
          _instructionManager.noteSpoken(sentences);
          for (final String sentence in sentences) {
            _voiceService.enqueueSpeech(sentence);
          }
          nav.commitAnnouncement();
        }
      }
    }

    // Target Object Navigation: the same frame, the same detections and the
    // same safety decision. The target navigator holds its own guidance back
    // while an obstacle is being reported, so safety always speaks first.
    if (!stale()) {
      _targetNavigation.updateFrame(
        detections: detections,
        decision: decision,
        runId: run,
      );
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
    return _allowObjectAnnouncement(blocker);
  }

  /// Whether this single object may be named out loud.
  ///
  /// The same per-category switches that already gate the primary blocker are
  /// applied to every object in a multi-object announcement, so turning
  /// "person announcements" off really does keep people out of the sentence.
  bool _allowObjectAnnouncement(DetectedObject object) {
    final s = SettingsService.instance;
    final cls = object.className.toLowerCase();
    if (cls == SceneAnnouncer.ghostClass) return s.obstacleAnnouncements;
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
    // Idempotent: STOP and BACK can both arrive while a teardown is running.
    if (_isStopping) return;
    _isStopping = true;

    try {
      await _teardownNavigation();
    } finally {
      _isStopping = false;
      // Both the back lock and the swipe gate are read while building, so
      // releasing this guard has to rebuild or the screen would stay locked
      // after the run has already stopped.
      if (mounted) setState(() {});
    }
  }

  /// Release everything the run owns, then return to the stopped screen.
  Future<void> _teardownNavigation() async {
    // Marks any in-flight inference belonging to the old run as stale BEFORE
    // any await, so it cannot re-enable the pipeline, speak, or overwrite the
    // stopped state once it finally returns.
    _runGeneration++;
    _inferenceTimer?.cancel();

    _instructionManager.reset();
    // Cuts the sentence in flight as well as the queue, so no "Chair on your
    // left..." keeps talking after the run is over.
    _voiceService.stop();
    VibrationService.instance.stopVibration();
    // Any target session ends with the run, silently: navigation owns the
    // voice channel again from here. This also ends the search itself, so no
    // target tracking survives in the background.
    _targetNavigation.setPipelineActive(false);
    // Nothing is being analysed any more, so the microphone closes too.
    _stopAlwaysOnListening();

    if (!mounted) return;

    setState(() {
      _navState = _NavState.stopped;
      _latestCameraImage = null;
      _activeDepthScene = null;
      _detectionStatus = '';
      _detectedObject = 'No objects detected';
    });

    await _cameraService?.stopImageStream();

    _objectDetectionService?.stop();
    _navigationService?.reset();
    _depthAnalysisService?.reset();

    if (!mounted) return;

    _presentIntroCard();
    _confirmNavigationStopped();
  }

  /// Tell the user the run is over, using whichever feedback channel is active.
  ///
  /// Silence would leave a blind user with no way of knowing the Back press
  /// landed, so this follows the same switch the live guidance uses.
  void _confirmNavigationStopped() {
    if (SettingsService.instance.vibrateMode) {
      VibrationService.instance.vibrateNavigation();
      return;
    }
    if (!_voiceGuidance || !_voiceService.enabled) return;
    _voiceService.enqueueSpeech('Navigation stopped.');
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
        // Back means "stop the current navigation process", not "leave while it
        // keeps running". While the run owns the screen the route is held shut,
        // so the process is always fully stopped before the user can go
        // anywhere. A second Back, once stopped, behaves as it always did.
        canPop: !_navigationActive,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || !mounted) return;
          // Reaching here means canPop was false, i.e. navigation was active.
          // Stop it and stay on this screen in its normal stopped state; the
          // swipe lock is released by _navigationActive once _navState settles.
          await _stopNavigation();
        },

        child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFD),
        body: _buildVoiceActivationArea(
          SafeArea(
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
                              if (_targetNavigation.isActive)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: TargetStatusChip(
                                    state: _targetNavigation.state,
                                  ),
                                ),
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
              _speechWebViewHost(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }

  // ------------------------------------------------------------
  // PRESS-AND-HOLD VOICE ACTIVATION
  // ------------------------------------------------------------
  //
  // The entire navigation surface is the activation target, so a user never has
  // to find a button. [PressAndHoldVoiceRegion] owns the gesture itself,
  // including the threshold that keeps a short tap from opening the assistant.

  Widget _buildVoiceActivationArea(Widget navigation) {
    return PressAndHoldVoiceRegion(
      controller: _voiceCommand,
      enabled: _voiceActivationEnabled,
      child: Stack(
        children: <Widget>[
          navigation,
          // Above everything, transparent, purely decorative.
          Positioned.fill(
            child: VoiceSearchOverlay(controller: _voiceCommand),
          ),
        ],
      ),
    );
  }

  /// Press-and-hold only makes sense with a running camera behind it, so the
  /// assistant stays out of the way on the idle and stopped screens.
  bool get _voiceActivationEnabled =>
      _navState != _NavState.idle && _navState != _NavState.stopped;

  /// Route the recognized transcript. Target commands drive the target
  /// navigator. Anything else falls through to the barge-in words below.
  ///
  /// The object announcements stay muted for as long as this takes, so the
  /// answer to the command is never buried under "Person detected." The target
  /// navigator takes over the mute on its own once a search starts.
  void _onVoiceCommand(String transcript) {
    _commandInFlight = true;
    _syncSceneVoiceSuppression();
    try {
      if (_targetNavigation.handleCommand(transcript)) return;
      // Not a device command. "Stop." / "shut up." only mean "be quiet" when no
      // target search is running; while one is active they belong to the target
      // navigator above, so they never cancel a search by accident.
      final String lower = transcript.trim().toLowerCase();
      if (!_targetNavigation.isActive &&
          (lower == 'stop' ||
              lower == 'cancel' ||
              lower == 'nevermind' ||
              lower.contains('shut up'))) {
        _voiceService.stop();
        return;
      }
      // "Repeat that." re-announces the instruction the user just heard. The
      // Repeat Last Instruction setting owns this: when it is off the request is
      // silently declined rather than partially honoured.
      if (_repeatRequested(lower)) {
        // Repeat the sentences that were actually delivered, not the live
        // scene: the current frame may describe something the cooldown
        // suppressed, and replaying that would say something the user never
        // heard.
        if (_instructionManager.repeatLast() && _voiceGuidance) {
          for (final String sentence in _instructionManager.lastSpokenSentences) {
            _voiceService.enqueueSpeech(sentence);
          }
        } else {
          _voiceService.enqueueSpeech('Repeat is turned off in Settings.');
        }
      }
    } finally {
      _commandInFlight = false;
      _syncSceneVoiceSuppression();
    }
  }

  /// Whether a transcript is a request to repeat the last instruction.
  ///
  /// Deliberately narrow: only phrases that clearly ask for a repeat, so an
  /// ordinary scene sentence containing the word "again" cannot re-trigger it.
  bool _repeatRequested(String lower) {
    return lower == 'repeat' ||
        lower == 'repeat that' ||
        lower == 'say that again' ||
        lower == 'repeat please' ||
        lower == 'again please';
  }

  /// Speak the reason the hold produced nothing usable.
  void _onVoiceCommandFailure(VoiceCommandFailure failure) {
    final String message =
        VoiceCommandController.isPermissionProblem(failure)
            ? VoiceCommandController.permissionDeniedMessage
            : VoiceCommandController.nothingHeardMessage;
    _voiceService.enqueueSpeech(message);
  }

  /// The hidden Google speech WebView: 1x1, no paint, no input. It must stay
  /// mounted while this screen is open so the recognizer is ready the moment a
  /// press-and-hold command asks for the microphone.
  Widget _speechWebViewHost() {
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
          child: ClipRect(child: SpeechCaptureService.instance.webEngine.build()),
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

          // The voice assistant is no longer a button: the whole screen is the
          // press-and-hold target, so a user never has to find a small icon.

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
