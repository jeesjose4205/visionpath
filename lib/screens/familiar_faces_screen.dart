import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/face_detection.dart';
import '../models/app_settings.dart';
import '../services/camera_service.dart';
import '../services/face_announcement_manager.dart';
import '../services/face_detection_service.dart';
import '../services/face_embedding_service.dart';
import '../services/face_recognition_service.dart';
import '../services/familiar_face_service.dart';
import '../services/settings_service.dart';
import '../services/voice_service.dart';
import '../utils/portrait_rgba.dart';
import '../widgets/camera_preview_fit.dart';
import '../widgets/face_recognition_overlay.dart';
import '../widgets/settings_button.dart';
import 'face_registration_screen.dart';
import 'registered_faces_screen.dart';

/// Familiar Faces hub - register new people and run live recognition.
///
/// Mirrors the Navigate camera screen: the FAMILIAR FACES title card covers
/// the camera rectangle while idle and slides away when the user presses
/// RECOGNIZE, revealing the live camera with the familiar-face recognition
/// pipeline (camera -> ML Kit face detection -> MobileFaceNet embedding match
/// -> temporal confirmation -> voice announcement) running over the shared
/// camera with the same 5-FPS single-flight pump pattern. Pressing
/// STOP RECOGNITION stops the pipeline and brings the title card back.
class FamiliarFacesScreen extends StatefulWidget {
  const FamiliarFacesScreen({super.key});

  @override
  State<FamiliarFacesScreen> createState() => _FamiliarFacesScreenState();
}

class _FamiliarFacesScreenState extends State<FamiliarFacesScreen>
    with SingleTickerProviderStateMixin {
  static const Color _green = Color(0xFF1E8E3E);
  static const Color _unknownColor = Color(0xFF8A5660);

  final VoiceService _voice = VoiceService();
  final FaceDetectionService _detector = FaceDetectionService();
  final FaceRecognitionService _recognition = FaceRecognitionService();
  final FaceAnnouncementManager _annMgr = FaceAnnouncementManager(
    unknownAnnouncements: false,
  );

  // Cached from the provider tree (read outside build from the pump timer).
  late final FamiliarFaceService _faceService;

  bool _voiceEnabled = true;
  bool _unknownEnabled = false;

  // ------------------------------------------------------------
  // INTRODUCTORY TITLE CARD (same pattern as Navigate)
  // ------------------------------------------------------------
  //
  // The title card covers the camera rectangle when the screen is opened and
  // again after each STOP RECOGNITION, and fades out to reveal the live
  // camera when RECOGNIZE is pressed.

  bool _showTitleCard = true;
  late final AnimationController _introController;

  // ------------------------------------------------------------
  // RECOGNITION PIPELINE STATE
  // ------------------------------------------------------------

  bool _recognizing = false;
  CameraService? _cameraService;
  CameraImage? _latestFrame;
  Timer? _pumpTimer;
  bool _busyFrame = false;

  // Latest frame results for the overlay + status.
  List<FaceOverlayEntry> _overlay = [];
  String _statusLine = 'Watching for known faces…';
  String _statusName = '';
  bool _waitingForCamera = true;

  // ------------------------------------------------------------
  // SWIPE NAVIGATION: return to Look & Navigate (Home)
  // ------------------------------------------------------------

  double _swipeDx = 0;
  bool _swipeNavLocked = false;

  void _onSwipeStart(DragStartDetails details) {
    _swipeDx = 0;
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    _swipeDx += details.delta.dx;
  }

  void _onSwipeEnd(DragEndDetails details) {
    if (_swipeNavLocked || !mounted) return;

    final velocity = details.primaryVelocity ?? 0;
    final distance = _swipeDx;

    // Ignore tiny horizontal movements and accidental vertical gestures.
    if (velocity.abs() < 300 && distance.abs() < 80) return;

    // Only a deliberate RIGHT swipe returns to Look & Navigate. There is no
    // screen defined to the LEFT of Familiar Faces, so LEFT swipes do nothing.
    final direction = velocity != 0 ? velocity : distance;
    if (direction <= 0) return;

    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return;

    _swipeNavLocked = true;
    navigator.pop();
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _swipeNavLocked = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _faceService = context.read<FamiliarFaceService>();
    _applySettings();
    SettingsService.instance.addListener(_applySettings);
    // The registry is provided and pre-loaded by the app; load if not ready.
    Future<void>.microtask(() {
      if (!_faceService.loaded) {
        _faceService.load();
      }
    });
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final count = _faceService.people.length;
        final message = count == 0
            ? 'No people registered yet. Press add to register someone.'
            : '$count ${count == 1 ? 'person is' : 'people are'} registered.';
        _voice.speak(
          'Familiar Faces. Recognize familiar faces around you with '
          'intelligent camera assistance. $message',
        );
      }
    });
  }

  /// Applies persisted settings to this screen's live services.
  void _applySettings() {
    final s = SettingsService.instance;
    _voiceEnabled = s.familiarFacesEnabled &&
        s.familiarFaceVoice &&
        s.voiceGuidanceEnabled &&
        !s.globalVoiceMuted;
    setState(() {});
    _voice.setEnabled(_voiceEnabled);
    _unknownEnabled = s.unknownPersonAnnouncements;
    _annMgr.unknownAnnouncements = _unknownEnabled;
    _annMgr.announceCooldown =
        Duration(seconds: s.familiarFaceCooldownSeconds);
  }

  /// Recognition threshold mapped from the user-facing sensitivity.
  double get _mlThreshold {
    switch (SettingsService.instance.familiarFaceSensitivity) {
      case FamiliarFaceSensitivity.conservative:
        return 0.60;
      case FamiliarFaceSensitivity.balanced:
        return 0.55;
      case FamiliarFaceSensitivity.sensitive:
        return 0.50;
    }
  }

  /// Stops the image pump and the shared image stream. Idempotent, so both
  /// [dispose] and STOP RECOGNITION can share it without double-stopping.
  void _shutdownPipeline() {
    _pumpTimer?.cancel();
    _pumpTimer = null;
    _cameraService?.setOnFrameAvailable((_) {});
    final service = _cameraService;
    _cameraService = null;
    _latestFrame = null;
    if (service != null) {
      unawaited(service.stopImageStream());
    }
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_applySettings);
    _shutdownPipeline();
    _introController.dispose();
    _voice.dispose();
    _detector.close();
    super.dispose();
  }

  // ------------------------------------------------------------
  // INTRO CARD ANIMATION (same pattern as Navigate)
  // ------------------------------------------------------------

  void _dismissIntroCard() {
    if (!_showTitleCard) return;
    _introController.reverse().whenComplete(() {
      // Only remove the card if no new appearance started while fading out.
      if (mounted && _showTitleCard) {
        setState(() => _showTitleCard = false);
      }
    });
  }

  void _presentIntroCard() {
    if (_showTitleCard) {
      _introController.forward();
      return;
    }
    setState(() => _showTitleCard = true);
    _introController.forward();
  }

  // ------------------------------------------------------------
  // START / STOP RECOGNITION
  // ------------------------------------------------------------

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    _voice.speak(message);
  }

  Future<void> _startRecognition() async {
    print('FAMILIAR_FACES_START_PRESSED');
    if (_recognizing) return;
    _dismissIntroCard();
    setState(() => _recognizing = true);

    // 1. Ensure the camera is initialized (single controller).
    final cameraService = context.read<CameraService>();
    _cameraService = cameraService;

    if (!cameraService.isInitialized) {
      final bool ok = await cameraService.initializeController();
      if (!ok || !mounted || !_recognizing) {
        if (mounted) {
          _revertFromCameraFailure(
              'Camera could not be started: ${cameraService.errorMessage}');
        }
        return;
      }
    }

    if (!mounted || !_recognizing) return;

    // 2. Attach the frame callback BEFORE starting the stream.
    cameraService.setOnFrameAvailable(_onFrame);
    final bool started = await cameraService.startImageStream();
    if (!mounted || !_recognizing) {
      if (mounted) _revertFromCameraFailure('Recognition stopped.');
      return;
    }
    if (!started) {
      _revertFromCameraFailure(
          'Image stream failed: ${cameraService.errorMessage}');
      return;
    }

    // 3. Reset per-session state and begin the 200ms single-flight pump.
    setState(() {
      _waitingForCamera = false;
      _overlay = [];
      _statusLine = 'Watching for known faces…';
      _statusName = '';
    });

    _pumpTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_recognizing || !mounted) {
        _pumpTimer?.cancel();
        return;
      }
      if (_busyFrame) return;
      final frame = _latestFrame;
      if (frame == null) return;
      _busyFrame = true;
      _pump(frame).whenComplete(() => _busyFrame = false);
    });
    print('FACE_RECOGNITION_CAMERA_READY');
  }

  void _revertFromCameraFailure(String message) {
    _shutdownPipeline();
    setState(() {
      _recognizing = false;
      _waitingForCamera = true;
      _overlay = [];
      _statusLine = 'Watching for known faces…';
      _statusName = '';
    });
    _presentIntroCard();
    _showError(message);
  }

  void _stopRecognition() {
    _shutdownPipeline();
    if (!mounted) return;
    setState(() {
      _recognizing = false;
      _waitingForCamera = true;
      _overlay = [];
      _statusLine = 'Watching for known faces…';
      _statusName = '';
    });
    _presentIntroCard();
  }

  void _onFrame(CameraImage image) {
    _latestFrame = image;
  }

  Future<void> _pump(CameraImage image) async {
    final converted = convertFrameToPortraitRgba(
      image,
      _cameraService?.imageRotationQuarterTurns ?? 0,
    );
    if (converted == null) return;

    final faces = await _detector.detectRgba(
      converted.rgba,
      converted.width,
      converted.height,
    );

    final people = _faceService.people;
    final occurrences = <FaceOccurrence>[];
    final overlayEntries = <FaceOverlayEntry>[];
    String status = 'Watching for known faces…';
    String name = '';

    for (final face in faces) {
      if (!face.isUpright || face.width < 0.08 || face.height < 0.10) {
        continue;
      }

      // Primary: MobileFaceNet embedding (learned, far more discriminative).
      FaceRecognitionResult match;
      if (FaceEmbeddingService.instance.isReady) {
        final mlEmb = await FaceEmbeddingService.instance.embeddingFor(
          converted.rgba,
          converted.width,
          converted.height,
          face,
        );
        if (mlEmb == null) continue;
        final ml = FaceEmbeddingService.instance.identify(
          mlEmb,
          people,
          threshold: _mlThreshold,
        );
        match = ml == null
            ? const FaceRecognitionResult.unknown()
            : FaceRecognitionResult.known(
                personId: ml.person.id,
                personName: ml.person.name,
                similarity: ml.similarity,
              );
      } else {
        // Fallback: geometric recognizer (only matches when both the probe
        // and the stored record are geometric; handles mixed-storage).
        final emb = _recognition.generateEmbedding(face);
        if (emb == null) continue;
        match = _recognition.identify(emb, people);
      }

      final occ = FaceOccurrence(
        identityKey: match.personId ?? 'UNKNOWN',
        name: match.personName,
        position: face.position,
        similarity: match.similarity,
        isUnknown: !match.isKnown,
        cx: face.centerX,
        cy: face.centerY,
      );
      occurrences.add(occ);

      overlayEntries.add(
        FaceOverlayEntry(
          box: face.boundingBox,
          label: match.isKnown ? match.personName! : 'Unknown',
          color: match.isKnown ? _green : _unknownColor,
          subtitle:
              match.isKnown ? '${(match.similarity * 100).toInt()}%' : null,
        ),
      );
      if (match.isKnown) {
        status = '${match.personName ?? 'Person'}\u00a0\u00b7\u00a0'
            '${(match.similarity * 100).toInt()}%';
        name = match.personName ?? '';
      } else {
        status = 'Unknown person';
      }
    }

    final now = DateTime.now();
    final lines = _annMgr.update(occurrences, now);
    for (final line in lines) {
      _voice.speak(line);
    }

    if (!mounted || !_recognizing) return;
    setState(() {
      _overlay = overlayEntries;
      _statusLine = status;
      _statusName = name;
    });
  }

  void _toggleVoice() {
    SettingsService.instance.setGlobalVoiceMuted(
      !SettingsService.instance.globalVoiceMuted,
    );
  }

  Future<void> _openRegistration() async {
    _voice.stop();
    final registered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const FaceRegistrationScreen()),
    );
    if (registered == true && mounted) {
      final count = _faceService.people.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Registration saved.'
                : 'Registration saved. '
                    '$count ${count == 1 ? 'person is' : 'people are'} registered.',
          ),
        ),
      );
    }
  }

  Future<void> _openRegisteredFaces() {
    _voice.stop();
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisteredFacesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool compact = size.height < 700;
    final bool unavailable =
        !_waitingForCamera && _cameraService?.controller == null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onSwipeStart,
      onHorizontalDragUpdate: _onSwipeUpdate,
      onHorizontalDragEnd: _onSwipeEnd,

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
                              // Live camera, revealed when the title card is
                              // dismissed (same rectangle as Navigate).
                              ExcludeSemantics(
                                excluding: _showTitleCard,
                                child: _buildCameraStage(),
                              ),

                              if (_showTitleCard)
                                _FfTitleCard(animation: _introController),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: compact ? 8 : 12),

                      _buildAddPersonCard(compact),

                      SizedBox(height: compact ? 8 : 12),

                      _buildRegisteredFacesCard(compact),

                      SizedBox(height: compact ? 8 : 12),

                      _buildNextActionCard(compact, unavailable),

                      SizedBox(height: compact ? 8 : 12),

                      _buildBottomControls(compact),
                    ],
                  ),
                ),
              ),
            ],
          ),
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

          // Voice toggle (speaker).
          _HeaderButton(
            icon: _voiceEnabled
                ? Icons.volume_up_outlined
                : Icons.volume_off_outlined,
            label: 'Speaker',
            onTap: _toggleVoice,
          ),

          const SizedBox(width: 10),

          const SettingsButton(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // CAMERA STAGE (same rectangle/proportions as Navigate)
  // ------------------------------------------------------------

  Widget _buildCameraStage() {
    final controller = _cameraService?.controller;

    return Semantics(
      label: 'Familiar Faces camera',
      container: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFF20252B),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(22),
              bottom: Radius.circular(22),
            ),
          ),
          child: controller != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    // Single camera preview (same controller as the stream).
                    CameraPreviewFit(controller: controller),

                    // Existing face boxes + name labels.
                    FaceRecognitionOverlay(entries: _overlay),

                    // Scan frame corners.
                    Positioned.fill(
                      child: CustomPaint(
                        painter: const _FfFramePainter(),
                      ),
                    ),

                    // Camera/AI status pill (top-left).
                    Positioned(
                      top: 14,
                      left: 14,
                      child: _buildAIPill(),
                    ),

                    // Recognition status (bottom-left).
                    Positioned(
                      left: 14,
                      bottom: 14,
                      child: _buildDetectionStatus(),
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.face_retouching_natural,
                        color: Colors.white70,
                        size: 58,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _waitingForCamera
                            ? 'Starting camera…'
                            : _statusLine,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// Status pill matching Navigate's camera status indicator. The dot is
  /// green while the shared stream is delivering frames, white otherwise.
  Widget _buildAIPill() {
    final active = _cameraService?.isImageStreamActive ?? false;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? Colors.greenAccent : Colors.white54,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            active ? 'RECOGNIZING' : 'CAMERA READY',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Recognition status (bottom-left), mirroring Navigate's detected-object
  /// readout. Shows the live recognition state from the last processed frame.
  Widget _buildDetectionStatus() {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.62,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        _statusLine,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // ADD PERSON CARD
  // ------------------------------------------------------------

  Widget _buildAddPersonCard(bool compact) {
    return Semantics(
      button: true,
      label: 'Add Person. Register a new face to recognize.',
      child: Opacity(
        opacity: _recognizing ? 0.45 : 1,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE4E7EC)),
          ),
          child: InkWell(
            onTap: _recognizing ? null : _openRegistration,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 18,
                vertical: compact ? 10 : 13,
              ),
              child: Row(
                children: [
                  Container(
                    width: compact ? 40 : 46,
                    height: compact ? 40 : 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF5FF),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.person_add_alt_1_rounded,
                      color: const Color(0xFF175CD3),
                      size: compact ? 21 : 24,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Person',
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
                          'Register a new face to recognize',
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

                  const SizedBox(width: 8),

                  Icon(
                    Icons.chevron_right_rounded,
                    color: const Color(0xFF98A2B3),
                    size: compact ? 22 : 24,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // REGISTERED FACES CARD
  // ------------------------------------------------------------

  Widget _buildRegisteredFacesCard(bool compact) {
    return Consumer<FamiliarFaceService>(
      builder: (context, faceService, child) {
        final count = faceService.people.length;
        return Semantics(
          button: true,
          label: 'Registered Faces. $count '
              '${count == 1 ? 'person is' : 'people are'} registered.',
          child: Opacity(
            opacity: _recognizing ? 0.45 : 1,
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFFE4E7EC)),
              ),
              child: InkWell(
                onTap: _recognizing ? null : _openRegisteredFaces,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 14 : 18,
                    vertical: compact ? 10 : 13,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: compact ? 40 : 46,
                        height: compact ? 40 : 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF5FF),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          Icons.people_outline_rounded,
                          color: const Color(0xFF175CD3),
                          size: compact ? 21 : 24,
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Registered Faces',
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
                              count == 0
                                  ? 'No one registered yet'
                                  : '$count '
                                      '${count == 1 ? 'person is' : 'people are'} '
                                      'recognizable',
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

                      const SizedBox(width: 8),

                      if (count > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF5FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF175CD3),
                            ),
                          ),
                        ),

                      const SizedBox(width: 8),

                      Icon(
                        Icons.chevron_right_rounded,
                        color: const Color(0xFF98A2B3),
                        size: compact ? 22 : 24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // NEXT ACTION CARD
  // ------------------------------------------------------------

  Widget _buildNextActionCard(bool compact, bool unavailable) {
    final String message;
    if (unavailable) {
      message = 'Camera unavailable';
    } else if (_recognizing) {
      if (_statusName.isNotEmpty) {
        message = '$_statusName recognized';
      } else if (_statusLine == 'Unknown person') {
        message = 'Unknown person';
      } else {
        message = 'Look toward the camera';
      }
    } else {
      message = 'Press RECOGNIZE';
    }

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
              Icons.face_retouching_natural_rounded,
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
                  message,
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
  // PRIMARY BUTTON (RECOGNIZE <-> STOP RECOGNITION)
  // ------------------------------------------------------------

  Widget _buildBottomControls(bool compact) {
    return SizedBox(
      width: double.infinity,
      height: compact ? 48 : 54,
      child: ElevatedButton.icon(
        onPressed: _recognizing ? _stopRecognition : _startRecognition,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              _recognizing ? const Color(0xFFD92D20) : const Color(0xFF175CD3),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: Icon(
          _recognizing ? Icons.stop_circle_outlined : Icons.face_rounded,
          size: 25,
        ),
        label: Text(
          _recognizing ? 'STOP RECOGNITION' : 'RECOGNIZE',
          style: TextStyle(
            fontSize: compact ? 14 : 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HEADER BUTTON
// ============================================================

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
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
// FAMILIAR FACES TITLE CARD
// ============================================================
//
// Covers the camera rectangle while idle, like Navigate's intro title card.
// Slides/fades away on RECOGNIZE and returns after STOP RECOGNITION.

class _FfTitleCard extends StatelessWidget {
  const _FfTitleCard({required this.animation});

  /// Drives the entrance (fade in + very slight scale) and the departure
  /// when the user presses RECOGNIZE.
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
      label: 'VisionPath AI. Familiar Faces. Recognize familiar faces around '
          'you with intelligent camera assistance.',
      child: ExcludeSemantics(
        child: FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: const _FfTitleCardContent(),
          ),
        ),
      ),
    );
  }
}

class _FfTitleCardContent extends StatelessWidget {
  const _FfTitleCardContent();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
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
            child: _FfGlowBlob(size: 230, color: const Color(0xFF2E7CF6)),
          ),
          Positioned(
            bottom: -90,
            left: -70,
            child: _FfGlowBlob(size: 260, color: const Color(0xFF7C5BFF)),
          ),
          Positioned(
            bottom: 120,
            right: -50,
            child: _FfGlowBlob(size: 180, color: const Color(0xFF4C8DFF)),
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
                          _FfLogoMark(size: short ? 56 : 68),
                          const SizedBox(height: 14),
                          _FfBrandTitle(fontSize: short ? 22 : 27),
                          const SizedBox(height: 8),
                          const _FfFeatureTitle(),
                          const SizedBox(height: 6),
                          const _FfDescription(),
                          const SizedBox(height: 10),
                          Container(
                            width: 46,
                            height: 3,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF2E7CF6),
                                  Color(0xFF7C5BFF),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const _FfReadyPanel(),
                          const SizedBox(height: 20),
                          const _FfPageDots(),
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

class _FfLogoMark extends StatelessWidget {
  const _FfLogoMark({required this.size});

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
      child: Icon(
        Icons.face_retouching_natural,
        color: Colors.white,
        size: size * 0.48,
      ),
    );
  }
}

class _FfBrandTitle extends StatelessWidget {
  const _FfBrandTitle({required this.fontSize});

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

class _FfFeatureTitle extends StatelessWidget {
  const _FfFeatureTitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'FAMILIAR FACES',
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

class _FfDescription extends StatelessWidget {
  const _FfDescription();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Recognize familiar faces around you\nwith intelligent camera assistance',
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

class _FfReadyPanel extends StatelessWidget {
  const _FfReadyPanel();

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
            Icons.face_rounded,
            color: Color(0xFF9FC6FF),
            size: 22,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Camera ready to recognize',
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

class _FfPageDots extends StatelessWidget {
  const _FfPageDots();

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
            color: i == 2
                ? const Color(0xFF9FC6FF)
                : Colors.white.withValues(alpha: 0.28),
          ),
        );
      }),
    );
  }
}

class _FfGlowBlob extends StatelessWidget {
  const _FfGlowBlob({required this.size, required this.color});

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
// RECOGNITION FRAME PAINTER
// ============================================================
//
// The same scan-frame corner styling used by the Navigate camera rectangle.

class _FfFramePainter extends CustomPainter {
  const _FfFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
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