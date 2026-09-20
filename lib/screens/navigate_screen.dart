import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/detected_object.dart';
import '../models/navigation_decision.dart';
import '../models/path_analysis.dart';
import '../models/app_settings.dart';
import '../services/camera_service.dart';
import '../services/depth_analysis_service.dart';
import '../services/instruction_manager.dart';
import '../services/navigation_service.dart';
import '../services/object_detection_service.dart';
import '../services/path_analysis_service.dart';
import '../services/position_detection_service.dart';
import '../services/settings_service.dart';
import '../services/voice_service.dart';
import '../widgets/camera_preview_fit.dart';
import '../widgets/detection_overlay.dart';

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

class _NavigateScreenState extends State<NavigateScreen> {
  _NavState _navState = _NavState.idle;
  bool _voiceGuidance = true;

  String _detectionStatus = '';
  String _detectedObject = 'No objects detected';
  String _inferenceStatus = 'Initializing...';

  // Frame sampling
  Timer? _inferenceTimer;
  bool _inferenceInProgress = false;
  int _inferenceTicks = 0;
  int _framesObserved = 0;

  CameraImage? _latestCameraImage;

  // Pipeline services (stateful pieces owned by this screen).
  final InstructionManager _instructionManager = InstructionManager();
  final VoiceService _voiceService = VoiceService();

  ObjectDetectionService? _objectDetectionService;
  NavigationService? _navigationService;

  @override
  void initState() {
    super.initState();
    _applySettings();
    SettingsService.instance.addListener(_applySettings);
    _voiceService.setEnabled(_voiceGuidance);
    _initializeObjectDetection();
  }

  /// Applies persisted settings to this screen's live services.
  void _applySettings() {
    final s = SettingsService.instance;
    _voiceGuidance = s.voiceGuidanceEnabled &&
        s.navigationVoiceEnabled &&
        s.detectionVoiceEnabled;
    setState(() {});
    _voiceService.setEnabled(_voiceGuidance);
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
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_applySettings);
    _inferenceTimer?.cancel();
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
  // START NAVIGATION
  // ------------------------------------------------------------

  Future<void> _startNavigation() async {
    print('NAVIGATE_START_PRESSED');
    if (_navState == _NavState.starting) return;

    setState(() => _navState = _NavState.starting);

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

    setState(() {
      _navState = _NavState.cameraReady;
      _detectionStatus = '';
      _detectedObject = 'No objects detected';
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

    if (!mounted) return;

    // Confidence filtering already applied via predict's confidenceThreshold.

    // Position analysis (LEFT / CENTER / RIGHT) - model independent.
    final PositionDetectionService positionService =
        Provider.of<PositionDetectionService>(context, listen: false);
    detections = positionService.analyze(detections);

    // Approximate proximity/depth analysis.
    final DepthAnalysisService depthService =
        Provider.of<DepthAnalysisService>(context, listen: false);
    detections = depthService.analyze(detections);

    // Path analysis: is the walking path obstructed?
    final PathAnalysisService pathService =
        Provider.of<PathAnalysisService>(context, listen: false);
    final PathAnalysisResult path = pathService.analyze(detections);

    // Navigation decision.
    nav.decide(path, detections);
    final NavigationDecision decision = nav.lastDecision;

    // Instruction Manager: suppress repeated messages.
    final bool speak = _instructionManager.shouldSpeak(decision);
    if (speak &&
        _voiceGuidance &&
        _allowAnnouncement(decision, path.primaryBlocker)) {
      _voiceService.speak(nav.lastSpokenMessage);
    }

    if (!mounted) return;

    setState(() {
      _inferenceTicks++;
      _navState = _mapDecisionToState(decision);
      _updateDetectionFields(detections);
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

    _inferenceTimer?.cancel();

    _instructionManager.reset();
    _voiceService.stop();

    final CameraService cameraService =
        Provider.of<CameraService>(context, listen: false);
    await cameraService.stopImageStream();

    _objectDetectionService?.stop();
    _navigationService?.reset();
    _latestCameraImage = null;

    if (!mounted) return;

    setState(() {
      _navState = _NavState.stopped;
      _detectionStatus = '';
      _detectedObject = 'No objects detected';
    });
  }

  // ------------------------------------------------------------
  // VOICE TOGGLE
  // ------------------------------------------------------------

  void _toggleVoiceGuidance() {
    setState(() {
      _voiceGuidance = !_voiceGuidance;
    });
    _voiceService.setEnabled(_voiceGuidance);
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

    return Scaffold(
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
                      child: _buildCameraPreview(),
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
          ],
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
          _HeaderButton(
            icon: Icons.arrow_back,
            onTap: () {
              if (_navState != _NavState.idle &&
                  _navState != _NavState.stopped) {
                _stopNavigation();
              }
              Navigator.pop(context);
            },
          ),

          const SizedBox(width: 12),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Navigate',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF182230),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Camera-based path assistance',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),

          // Voice status toggle
          _HeaderButton(
            icon: _voiceGuidance
                ? Icons.volume_up_outlined
                : Icons.volume_off_outlined,
            onTap: _toggleVoiceGuidance,
          ),
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

  const _HeaderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
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