import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/detected_object.dart';
import '../models/live_assistant_state.dart';
import '../models/look_and_detect.dart';
import '../models/object_position.dart';
import '../models/proximity_level.dart';
import '../services/camera_service.dart';
import '../services/depth_analysis_service.dart';
import '../services/face_detection_service.dart';
import '../services/face_embedding_service.dart';
import '../services/familiar_face_service.dart';
import '../services/look_and_detect_engine.dart';
import '../services/object_detection_service.dart';
import '../services/position_detection_service.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../services/voice_input.dart';
import '../services/voice_service.dart';
import '../services/web_speech_engine.dart';
import '../utils/portrait_rgba.dart';
import '../widgets/camera_preview_fit.dart';
import '../widgets/detection_overlay.dart';

/// Look & Detect — a live, voice-first visual assistant integrated with the
/// existing VisionPath AI camera + YOLO + face-recognition services.
///
/// Interaction loop (LOOK -> UNDERSTAND -> RESPOND -> SPEAK):
///  1. Tap the microphone and ask a question (speech-to-text).
///  2. The latest camera frame is run through the existing YOLO detector,
///     position and depth analysis, and (optionally) familiar-face matching.
///  3. The on-device assistant engine answers with natural spatial language.
///  4. The answer is shown on a glass response card and spoken aloud.
///
/// Continuous detection can be enabled so meaningful scene changes are
/// announced without being asked. Frames are throttled (single-flight,
/// milliseconds) so the camera stays smooth and the battery/CPU stay sane.
/// Video and detections stay on-device; speech is recognized either offline
/// (Vosk) or, when reachable, by Google's speech service over the network.
class LookAndDetectScreen extends StatefulWidget {
  const LookAndDetectScreen({super.key});

  @override
  State<LookAndDetectScreen> createState() => _LookAndDetectScreenState();
}

class _LookAndDetectScreenState extends State<LookAndDetectScreen> {
  final LookAndDetectEngine _engine = LookAndDetectEngine();
  final VoiceService _voice = VoiceService();
  final WebSpeechEngine _web = WebSpeechEngine();
  final SpeechService _vosk = SpeechService();
  final FaceDetectionService _faceDetector = FaceDetectionService();

  /// Preferred recognizer is Google's Web Speech engine; Vosk (offline) is
  /// used automatically whenever Google is unavailable or fails to start.
  bool _usingWeb = true;

  VoiceInput get _voiceInput => _usingWeb ? _web : _vosk;

  FamiliarFaceService? _faceService;
  CameraService? _cameraService;
  CameraImage? _latestFrame;
  Timer? _pumpTimer;
  bool _busyFrame = false;
  int _faceTick = 0;

  LiveAssistantState _state = LiveAssistantState.idle;
  String _stateMessage = '';
  String _response = '';
  String _liveTranscript = '';
  bool _cameraOn = true;
  bool _continuousDetect = true;
  bool _voiceEnabled = true;
  bool _familiarScan = false;
  bool _cameraReady = false;
  bool _cameraFailed = false;
  String _cameraError = '';
  bool _speechAvailable = true;
  bool _speechFailed = false;

  List<SceneObject> _overlayObjects = const [];

  @override
  void initState() {
    super.initState();
    _faceService = context.read<FamiliarFaceService>();
    _applyVoiceSettings();
    SettingsService.instance.addListener(_applyVoiceSettings);
    unawaited(FaceEmbeddingService.instance.ensureLoaded());
    unawaited(_web.start());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _startCamera();
    });
  }

  bool get _effectiveVoice => _voiceEnabled;

  void _applyVoiceSettings() {
    final s = SettingsService.instance;
    final gate = s.voiceGuidanceEnabled && s.detectionVoiceEnabled;
    setState(() => _voiceEnabled = gate);
    _voice.setEnabled(gate);
    if (gate) {
      _voice.onSpeakCompleted = _onSpeakCompleted;
    }
    _familiarScan = s.familiarFacesEnabled;
  }

  void _onSpeakCompleted() {
    if (!mounted) return;
    // Return to idle unless the user already started something new.
    if (_state == LiveAssistantState.speaking) {
      setState(() => _state = LiveAssistantState.idle);
    }
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_applyVoiceSettings);
    _pumpTimer?.cancel();
    _pumpTimer = null;
    _cameraService?.setOnFrameAvailable((_) {});
    final camera = _cameraService;
    _cameraService = null;
    _latestFrame = null;
    if (camera != null) {
      unawaited(camera.stopImageStream());
    }
    _voice.onSpeakCompleted = null;
    _voice.dispose();
    unawaited(_web.dispose());
    unawaited(_vosk.dispose());
    _faceDetector.close();
    _engine.reset();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Camera lifecycle
  // ------------------------------------------------------------------

  Future<void> _startCamera() async {
    final service = context.read<CameraService>();
    final ods = context.read<ObjectDetectionService>();
    _cameraService = service;
    service.setOnFrameAvailable(_onFrame);

    // Load the YOLO26n model in parallel with camera boot so the first frame
    // can actually run inference (without this, detect() short-circuits and no
    // detections, boxes or announcements ever appear).
    ods.confidenceThreshold = SettingsService.instance.detectionConfidenceThreshold;
    final modelLoad = ods.isModelLoaded
        ? Future<bool>.value(true)
        : ods.initialize();

    final ok = await service.initializeController();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _cameraFailed = true;
        _cameraError = 'Camera access is required for Look & Detect.';
        _state = LiveAssistantState.disconnected;
        _stateMessage = _cameraError;
      });
      return;
    }
    final started = await service.startImageStream();
    if (!mounted) return;
    if (!started) {
      setState(() {
        _cameraFailed = true;
        _cameraError = 'The camera could not be started.';
        _state = LiveAssistantState.error;
        _stateMessage = _cameraError;
      });
      return;
    }

    final modelOk = await modelLoad;
    if (!mounted) return;
    if (!modelOk) {
      print('LOOK_DETECT_MODEL_LOAD_FAILED: ${ods.errorMessage}');
      setState(() {
        _cameraFailed = true;
        _cameraError = 'The vision model could not be loaded.';
        _state = LiveAssistantState.error;
        _stateMessage = _cameraError;
      });
      return;
    }

    setState(() {
      _cameraReady = true;
      _cameraOn = true;
      _state = _continuousDetect
          ? LiveAssistantState.detecting
          : LiveAssistantState.idle;
    });
    if (_continuousDetect) _startPump();
    _speakAssistant('Look and Detect is ready.');
    print('LOOK_DETECT_CAMERA_READY');
  }

  /// Switch between the rear and front camera.
  Future<void> _flipCamera() async {
    final camera = _cameraService;
    if (camera == null || _cameraFailed) return;
    final ok = await camera.flipCamera();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _state = LiveAssistantState.error;
        _stateMessage = 'Could not switch camera.';
      });
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _onFrame(CameraImage image) {
    _latestFrame = image;
  }

  void _startPump() {
    _pumpTimer?.cancel();
    // Throttled 2 FPS, single-flight: never stack inference, never re-upload
    // near-duplicate frames.
    _pumpTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_cameraOn || !_continuousDetect || !mounted) return;
      if (_busyFrame) return;
      final frame = _latestFrame;
      if (frame == null) return;
      _busyFrame = true;
      _pump(frame).whenComplete(() => _busyFrame = false);
    });
  }

  /// Toggle the live camera preview / stream (privacy-first: stream actually
  /// stops, it is not just hidden).
  Future<void> _toggleCamera() async {
    final next = !_cameraOn;
    HapticFeedback.selectionClick();
    setState(() {
      _cameraOn = next;
      if (!next) _state = LiveAssistantState.idle;
    });
    final camera = _cameraService;
    if (camera == null) return;
    if (next) {
      camera.setOnFrameAvailable(_onFrame);
      final ok = await camera.startImageStream();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _cameraOn = false;
          _cameraError = 'The camera could not be restarted.';
          _state = LiveAssistantState.error;
          _stateMessage = _cameraError;
        });
        return;
      }
      setState(() {
        _cameraReady = true;
        if (_continuousDetect) _state = LiveAssistantState.detecting;
      });
      if (_continuousDetect) _startPump();
    } else {
      _pumpTimer?.cancel();
      _latestFrame = null;
      await camera.stopImageStream();
      _speakAssistant('Camera off.');
    }
  }

  /// Toggle continuous scene detection.
  Future<void> _toggleContinuous() async {
    final next = !_continuousDetect;
    HapticFeedback.selectionClick();
    setState(() => _continuousDetect = next);
    if (next) {
      if (_cameraOn) {
        _startPump();
        setState(() => _state = LiveAssistantState.detecting);
      }
      _speakAssistant('Continuous detection on.');
    } else {
      _pumpTimer?.cancel();
      _speakAssistant('Continuous detection off.');
    }
  }

  // ------------------------------------------------------------------
  // Detection pipeline (shared by continuous + on-demand analysis)
  // ------------------------------------------------------------------

  Future<List<SceneObject>> _runDetection(CameraImage image) async {
    final ods = context.read<ObjectDetectionService>();
    final positionService = context.read<PositionDetectionService>();
    final depthService = context.read<DepthAnalysisService>();
    final camera = _cameraService;
    if (camera == null) return const [];

    List<DetectedObject> detections;
    try {
      detections = await ods.detectCameraImage(
        image,
        inputRotationQuarterTurns: camera.imageRotationQuarterTurns,
      );
    } catch (e, stack) {
      print('LOOK_DETECT_INFERENCE_ERROR: $e');
      print('LOOK_DETECT_INFERENCE_STACK: $stack');
      return const [];
    }

    detections = positionService.analyze(detections);
    detections = depthService.analyze(detections);

    // Familiar-face scan on alternate calls (~1 Hz) so identity matching does
    // not compete with YOLO. Names are only attached when a registered person
    // is confidently matched — never guessed.
    final namesByBox = <int, String>{};
    if (_familiarScan && (_faceTick++ & 1) == 1) {
      namesByBox.addAll(await _scanFamiliarFaces(image, detections, camera));
    }

    final scene = <SceneObject>[];
    for (var i = 0; i < detections.length; i++) {
      final d = detections[i];
      scene.add(
        SceneObject(
          className: d.className,
          confidence: d.confidence,
          boundingBox: d.boundingBox,
          position: d.position ?? ObjectPosition.fromCenterX(d.centerX),
          proximity: d.proximity ?? ProximityLevel.far,
          knownName: d.className.toLowerCase() == 'person'
              ? namesByBox[i]
              : null,
        ),
      );
    }
    return scene;
  }

  Future<Map<int, String>> _scanFamiliarFaces(
    CameraImage image,
    List<DetectedObject> detections,
    CameraService camera,
  ) async {
    final result = <int, String>{};
    final faceService = _faceService;
    if (faceService == null) return result;
    final people = faceService.people;
    if (people.isEmpty) return result;
    final persons = <int, DetectedObject>{
      for (var i = 0; i < detections.length; i++)
        if (detections[i].className.toLowerCase() == 'person') i: detections[i],
    };
    if (persons.isEmpty) return result;

    if (!FaceEmbeddingService.instance.isReady) return result;
    final converted = convertFrameToPortraitRgba(
      image,
      camera.imageRotationQuarterTurns,
    );
    if (converted == null) return result;

    final faces = await _faceDetector.detectRgba(
      converted.rgba,
      converted.width,
      converted.height,
    );
    if (!mounted) return result;

    for (final face in faces) {
      if (!face.isUpright || face.width < 0.08 || face.height < 0.10) continue;
      final embedding = await FaceEmbeddingService.instance.embeddingFor(
        converted.rgba,
        converted.width,
        converted.height,
        face,
      );
      if (embedding == null) continue;
      final match = FaceEmbeddingService.instance.identify(
        embedding,
        people,
        threshold: _mlThreshold,
      );
      if (match == null) continue;

      for (final entry in persons.entries) {
        final box = entry.value.boundingBox;
        if (face.centerX >= box.left &&
            face.centerX <= box.right &&
            face.centerY >= box.top &&
            face.centerY <= box.bottom) {
          result[entry.key] = match.person.name;
          break;
        }
      }
    }
    return result;
  }

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

  // ------------------------------------------------------------------
  // Continuous pump
  // ------------------------------------------------------------------

  Future<void> _pump(CameraImage image) async {
    final scene = await _runDetection(image);
    if (!mounted) return;

    final announcement = _engine.updateScene(scene);
    setState(() => _overlayObjects = scene);

    // Only speak spontaneous announcements when the assistant is free and the
    // user asked for continuous awareness.
    if (announcement != null &&
        announcement.isNotEmpty &&
        (_state == LiveAssistantState.idle ||
            _state == LiveAssistantState.detecting)) {
      _speakAssistant(announcement);
    }
  }

  // ------------------------------------------------------------------
  // Voice interaction
  // ------------------------------------------------------------------

  /// Big microphone button interaction.
  Future<void> _onMicTap() async {
    HapticFeedback.mediumImpact();
    switch (_state) {
      case LiveAssistantState.listening:
        await _voiceInput.cancel();
        setState(() {
          _state = _continuousDetect && _cameraOn
              ? LiveAssistantState.detecting
              : LiveAssistantState.idle;
        });
        return;
      case LiveAssistantState.speaking:
      case LiveAssistantState.processing:
        // Barge-in: cut the answer and start listening.
        _voice.stop();
        // fallthrough to listening
        break;
      case LiveAssistantState.error:
      case LiveAssistantState.disconnected:
        if (!_speechAvailable || _speechFailed) {
          // Speech input is broken on this device: skip retries and offer the
          // typed fallback so the assistant stays useful.
          if (_speechFailed) {
            await _openAskSheet();
            return;
          }
          // Try re-initializing once.
          _speechAvailable = await _voiceInput.initialize();
          if (!_speechAvailable) {
            await _openAskSheet();
            return;
          }
        }
        break;
      case LiveAssistantState.idle:
      case LiveAssistantState.detecting:
        break;
    }
    await _startListening();
  }

  Future<void> _startListening() async {
    // Candidate recognizers: Google first, offline Vosk as the safety net.
    final candidates = _usingWeb ? <VoiceInput>[_web, _vosk] : <VoiceInput>[_vosk];

    for (final input in candidates) {
      if (!mounted) return;
      if (!await input.initialize()) {
        if (input == _web) {
          _usingWeb = false;
          continue;
        }
        break;
      }

      _speechFailed = false;
      setState(() {
        _speechAvailable = true;
        _state = LiveAssistantState.listening;
        _stateMessage = '';
        _liveTranscript = '';
      });

      input
        ..onPartial = (partial) {
          if (!mounted) return;
          setState(() => _liveTranscript = partial);
        }
        ..onResult = (words) {
          _handleSpoken(words);
        }
        ..onError = (message) {
          _onSpeechError(message);
        };

      final started = await input.listen();
      if (!mounted) return;
      if (started) {
        if (input == _web) _usingWeb = true;
        return;
      }

      // Try the next engine when the failure smells systemic (no service, no
      // network, permission) rather than a one-off glitch.
      final reason = input.lastError.toLowerCase();
      final retryable = reason.contains('permission') ||
          reason.contains('denied') ||
          reason.contains('available') ||
          reason.contains('unavailable') ||
          reason.contains('network') ||
          reason.contains('not-found') ||
          reason.contains('service') ||
          reason.contains('not allowed');
      if (input == _web && retryable) {
        _usingWeb = false;
        continue;
      }

      final String message;
      if (reason.contains('permission') || reason.contains('denied')) {
        message =
            'Microphone permission is off. Turn it on in your phone settings, '
            'or ask me by typing.';
      } else if (reason.contains('available') ||
          reason.contains('unavailable') ||
          reason.contains('not_found') ||
          reason.contains('service') ||
          reason.contains('no_match')) {
        message =
            'This device has no speech recognition available. '
            'Ask me by typing instead.';
      } else if (reason.contains('network') ||
          reason.contains('internet') ||
          reason.contains('connect')) {
        message =
            'I could not reach the speech service. Check your internet '
            'connection, or ask me by typing.';
      } else {
        message =
            'I could not start the microphone. Try again, or ask me by typing.';
      }
      setState(() {
        _speechFailed = true;
        _state = LiveAssistantState.error;
        _stateMessage = message;
      });
      _speakAssistant(message);
      // Give the announcement a beat, then open the typed ask sheet so the
      // assistant remains usable even without voice input.
      unawaited(_autoOpenAskAfter(message));
      return;
    }

    if (!mounted) return;
    setState(() {
      _speechAvailable = false;
      _speechFailed = true;
      _state = LiveAssistantState.disconnected;
      _stateMessage = 'Microphone access is required for voice interaction.';
    });
    _speakAssistant(_stateMessage);
    unawaited(_autoOpenAskAfter(_stateMessage));
  }

  Future<void> _autoOpenAskAfter(String message) async {
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted || _state != LiveAssistantState.error) return;
    await _openAskSheet();
  }

  void _onSpeechError(String message) {
    if (!mounted) return;
    // Timeouts / silence are not real errors: just end quietly.
    if (message.contains('timeout') || message.contains('silence')) {
      setState(() {
        if (_state == LiveAssistantState.listening) {
          _state = _continuousDetect && _cameraOn
              ? LiveAssistantState.detecting
              : LiveAssistantState.idle;
        }
      });
      return;
    }
    setState(() {
      _state = LiveAssistantState.error;
      _stateMessage = 'Sorry, I could not hear you clearly. Please try again.';
    });
    _speakAssistant(_stateMessage);
  }

  /// Route a recognized (or typed) question through the assistant.
  Future<void> _handleSpoken(String text) async {
    if (!mounted) return;
    final query = text.trim();
    if (query.isEmpty) return;

    // Stop the recognizer so it cannot keep transcribing while we answer.
    unawaited(_voiceInput.stop());
    _voiceInput.onPartial = null;
    _voiceInput.onResult = null;
    _voiceInput.onError = null;

    // Interruption words.
    final lower = query.toLowerCase();
    if (lower == 'stop' ||
        lower == 'cancel' ||
        lower == 'that\'s enough' ||
        lower == 'shut up') {
      _voice.stop();
      setState(() {
        _state = _continuousDetect && _cameraOn
            ? LiveAssistantState.detecting
            : LiveAssistantState.idle;
        _response = '';
      });
      return;
    }

    setState(() {
      _state = LiveAssistantState.processing;
      _stateMessage = '';
    });
    _speakAssistant('Looking.');

    // Give the user a beat to hear "Looking." before the answer starts.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    final frame = _latestFrame;
    if (frame != null) {
      final scene = await _runDetection(frame);
      if (mounted) {
        _engine.updateScene(scene);
      }
    }

    final answer = _engine.answerQuery(query);
    if (!mounted) return;
    setState(() {
      _response = answer;
      _state = LiveAssistantState.speaking;
      _stateMessage = '';
    });
    if (_effectiveVoice) {
      _voice.speak(answer);
    }
  }

  /// Spoken state announcements and answers.
  void _speakAssistant(String text) {
    if (!_effectiveVoice) return;
    if (_state == LiveAssistantState.listening) return; // never talk while listening
    _voice.speak(text);
  }

  // ------------------------------------------------------------------
  // Options / typed ask
  // ------------------------------------------------------------------

  Future<void> _showOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E1420),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _OptionsSheet(screen: this),
    );
  }

  Future<void> _openAskSheet() async {
    final query = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1420),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _AskSheet(),
    );
    if (query == null || query.trim().isEmpty || !mounted) return;
    await _handleSpoken(query.trim());
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = _cameraService?.controller;
    final safe = MediaQuery.of(context).padding;
    final overlay = _overlayObjects
        .map(
          (o) => DetectedObject(
            className: o.label,
            confidence: o.confidence,
            boundingBox: o.boundingBox,
            position: o.position,
            proximity: o.proximity,
          ),
        )
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ---- Live camera ----
          if (controller != null && _cameraOn)
            CameraPreviewFit(controller: controller)
          else
            const ColoredBox(color: Color(0xFF05070B)),
          if (!_cameraOn)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_off_rounded,
                    size: 44,
                    color: Color(0xFF6B7686),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Camera off',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

          // ---- Detection boxes ----
          if (controller != null && _cameraOn && overlay.isNotEmpty)
            IgnorePointer(
              child: DetectionOverlay(
                previewSize: controller.value.previewSize ?? Size.zero,
                inputSize: displayPreviewSize(controller),
                results: overlay,
                showConfidence: false,
                showPosition: true,
              ),
            ),

          // ---- Subtle bottom scrim for control legibility ----
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 280,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.62),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.95],
                  ),
                ),
              ),
            ),
          ),

          // ---- Top controls ----
          Positioned(
            top: safe.top + 8,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _GlassCircleButton(
                  icon: Icons.cameraswitch_rounded,
                  semanticLabel: 'Switch camera',
                  onTap: _flipCamera,
                ),
                _GlassCircleButton(
                  icon: Icons.more_horiz_rounded,
                  semanticLabel: 'More options',
                  onTap: _showOptions,
                ),
              ],
            ),
          ),

          // ---- Status chip ----
          Positioned(
            top: safe.top + 78,
            left: 0,
            right: 0,
            child: Center(child: _statusChip()),
          ),

          // ---- Response card ----
          Positioned(
            left: 20,
            right: 20,
            bottom: safe.bottom + 168,
            child: _responseCard(),
          ),

          // ---- Microphone button ----
          Positioned(
            bottom: safe.bottom + 86,
            left: 0,
            right: 0,
            child: Center(
              child: _MicButton(state: _state, onTap: _onMicTap),
            ),
          ),

          // ---- Bottom controls ----
          Positioned(
            left: 20,
            right: 20,
            bottom: safe.bottom + 14,
            child: _bottomBar(),
          ),

          // ---- Hidden Google speech WebView (1x1, no paint / no input) ----
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0,
              child: IgnorePointer(
                child: ClipRect(child: _web.build()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip() {
    final active = _cameraOn && _cameraReady;
    final dot = active
        ? const Color(0xFF2FBF6A)
        : const Color(0xFF8A97AB);
    return _glassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      borderRadius: 18,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            _cameraOn ? 'CAMERA ON' : 'CAMERA OFF',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          if (_continuousDetect && _cameraOn) ...[
            const SizedBox(width: 10),
            const Icon(
              Icons.center_focus_strong_rounded,
              size: 13,
              color: Color(0xFF9FC6FF),
            ),
            const SizedBox(width: 5),
            const Text(
              'DETECT',
              style: TextStyle(
                color: Color(0xFF9FC6FF),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _responseCard() {
    final (stateLabel, color) = _stateLabel();
    final visibleText = switch (_state) {
      LiveAssistantState.listening => _liveTranscript.isEmpty
          ? 'Listening\u2026'
          : '“$_liveTranscript”',
      LiveAssistantState.idle => _response.isNotEmpty
          ? _response
          : 'Point the camera at what you want to understand, then tap the microphone and ask me.',
      LiveAssistantState.detecting => _response.isNotEmpty
          ? _response
          : 'Watching your surroundings. I will speak up when something changes.',
      _ => _response.isNotEmpty ? _response : stateLabel,
    };

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _glassContainer(
          key: ValueKey<String>('$stateLabel|$visibleText'),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          borderRadius: 22,
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    stateLabel.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                visibleText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, Color) _stateLabel() {
    switch (_state) {
      case LiveAssistantState.idle:
        return ('Tap the microphone and ask me', const Color(0xFF8A97AB));
      case LiveAssistantState.listening:
        return ('Listening', const Color(0xFF2FBF6A));
      case LiveAssistantState.processing:
        return ('Looking', const Color(0xFF9FC6FF));
      case LiveAssistantState.speaking:
        return ('Speaking', const Color(0xFF9FC6FF));
      case LiveAssistantState.detecting:
        return ('Watching', const Color(0xFF2FBF6A));
      case LiveAssistantState.error:
        return (_stateMessage.isEmpty ? 'Something went wrong' : _stateMessage,
            const Color(0xFFE5484D));
      case LiveAssistantState.disconnected:
        return (_stateMessage.isEmpty ? 'Not available' : _stateMessage,
            const Color(0xFFE5A448));
    }
  }

  Widget _bottomBar() {
    return Center(
      child: _glassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        borderRadius: 30,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GlassIconButton(
              icon: _cameraOn
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              semanticLabel: _cameraOn ? 'Disable camera' : 'Enable camera',
              onTap: _toggleCamera,
            ),
            const SizedBox(width: 18),
            _GlassIconButton(
              icon: _continuousDetect
                  ? Icons.center_focus_strong_rounded
                  : Icons.center_focus_weak_rounded,
              semanticLabel: _continuousDetect
                  ? 'Turn off continuous detection'
                  : 'Turn on continuous detection',
              onTap: _toggleContinuous,
            ),
            const SizedBox(width: 18),
            _GlassIconButton(
              icon: _voiceEnabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              semanticLabel: _voiceEnabled ? 'Turn voice off' : 'Turn voice on',
              onTap: () {
                final next = !_voiceEnabled;
                setState(() => _voiceEnabled = next);
                _voice.setEnabled(next);
                if (!next) _voice.stop();
                HapticFeedback.selectionClick();
              },
            ),
            const SizedBox(width: 18),
            _GlassIconButton(
              icon: Icons.close_rounded,
              semanticLabel: 'Close Look and Detect',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassContainer({
    required Widget child,
    EdgeInsetsGeometry? padding,
    double borderRadius = 20,
    BoxConstraints? constraints,
    Key? key,
  }) {
    return ClipRRect(
      key: key,
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: constraints,
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Glass circle icon button (top bar)
// ------------------------------------------------------------------

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: const Color(0x33000000),
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: Colors.black54,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Glass icon button (bottom bar)
// ------------------------------------------------------------------

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Microphone button
// ------------------------------------------------------------------

class _MicButton extends StatefulWidget {
  const _MicButton({required this.state, required this.onTap});

  final LiveAssistantState state;
  final VoidCallback onTap;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    switch (widget.state) {
      case LiveAssistantState.listening:
      case LiveAssistantState.speaking:
      case LiveAssistantState.processing:
        if (!_pulse.isAnimating) {
          _pulse.repeat();
        }
        break;
      case LiveAssistantState.idle:
      case LiveAssistantState.detecting:
      case LiveAssistantState.error:
      case LiveAssistantState.disconnected:
        if (_pulse.isAnimating) {
          _pulse.stop();
          _pulse.value = 0;
        }
        break;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  IconData get _icon {
    switch (widget.state) {
      case LiveAssistantState.listening:
        return Icons.graphic_eq_rounded;
      case LiveAssistantState.processing:
        return Icons.hourglass_top_rounded;
      case LiveAssistantState.speaking:
        return Icons.volume_up_rounded;
      case LiveAssistantState.error:
      case LiveAssistantState.disconnected:
        return Icons.mic_off_rounded;
      case LiveAssistantState.idle:
      case LiveAssistantState.detecting:
        return Icons.mic_rounded;
    }
  }

  Color get _glow => switch (widget.state) {
        LiveAssistantState.listening ||
        LiveAssistantState.speaking =>
          const Color(0xFF2FBF6A),
        LiveAssistantState.processing => const Color(0xFF9FC6FF),
        LiveAssistantState.error ||
        LiveAssistantState.disconnected =>
          const Color(0xFFE5484D),
        _ => const Color(0xFF1769E0),
      };

  @override
  Widget build(BuildContext context) {
    final ringColor =
        widget.state == LiveAssistantState.listening ||
            widget.state == LiveAssistantState.speaking
            ? _glow
            : _glow.withValues(alpha: 0.35);

    return Semantics(
      button: true,
      label: 'Microphone',
      hint: switch (widget.state) {
        LiveAssistantState.listening => 'Listening',
        LiveAssistantState.processing => 'Looking',
        LiveAssistantState.speaking => 'Speaking, tap to interrupt',
        _ => 'Tap to ask',
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = _pulse.value;
            final active =
                widget.state == LiveAssistantState.listening ||
                    widget.state == LiveAssistantState.speaking;
            return SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (active)
                    Container(
                      width: 92 + 26 * t,
                      height: 92 + 26 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ringColor.withValues(alpha: (1 - t) * 0.7),
                          width: 3,
                        ),
                      ),
                    ),
                  if (widget.state == LiveAssistantState.processing)
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(_glow),
                        strokeWidth: 3,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1E6FE8), Color(0xFF0E3E8A)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _glow.withValues(alpha: 0.55),
                          blurRadius: 26,
                          spreadRadius: active ? 4 : 2,
                        ),
                      ],
                    ),
                    child: Icon(_icon, color: Colors.white, size: 32),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Options sheet
// ------------------------------------------------------------------

class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({required this.screen});

  final _LookAndDetectScreenState screen;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late bool _continuous;
  late bool _camera;
  late bool _voice;
  late bool _familiar;

  @override
  void initState() {
    super.initState();
    final s = widget.screen;
    _continuous = s._continuousDetect;
    _camera = s._cameraOn;
    _voice = s._voiceEnabled;
    _familiar = s._familiarScan;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.screen;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Look & Detect',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text(
                'VisionPath AI Beta',
                style: TextStyle(
                  color: Color(0xFF7C8798),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _optionTile(
              icon: Icons.keyboard_rounded,
              title: 'Ask a question by typing',
              onTap: () {
                Navigator.of(context).pop();
                s._openAskSheet();
              },
            ),
            _optionSwitch(
              icon: Icons.center_focus_strong_rounded,
              title: 'Continuous detection',
              value: _continuous,
              onChanged: (v) {
                setState(() => _continuous = v);
                s._toggleContinuous();
              },
            ),
            _optionSwitch(
              icon: Icons.videocam_rounded,
              title: 'Camera',
              value: _camera,
              onChanged: (v) {
                setState(() => _camera = v);
                s._toggleCamera();
              },
            ),
            _optionSwitch(
              icon: Icons.volume_up_rounded,
              title: 'Voice',
              value: _voice,
              onChanged: (v) {
                setState(() => _voice = v);
                s._voiceEnabled = v;
                s._voice.setEnabled(v);
                if (!v) s._voice.stop();
              },
            ),
            if (s._faceService?.people.isNotEmpty ?? false)
              _optionSwitch(
                icon: Icons.face_retouching_natural_rounded,
                title: 'Recognize familiar faces',
                value: _familiar,
                onChanged: (v) => setState(() {
                  _familiar = v;
                  s._familiarScan = v;
                }),
              ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 14, color: Color(0xFF7C8798)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Video and detections stay on this device. Voice questions are recognized offline or by Google\u2019s speech service when online.',
                    style: TextStyle(
                      color: Color(0xFF7C8798),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF9FC6FF)),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: Color(0xFF7C8798)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _optionSwitch({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: const Color(0xFF9FC6FF)),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: const Color(0xFF1769E0),
      activeTrackColor: const Color(0x334369FF),
      inactiveTrackColor: const Color(0x33FFFFFF),
      inactiveThumbColor: const Color(0xFF9AA3AF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}

// ------------------------------------------------------------------
// Typed ask sheet
// ------------------------------------------------------------------

class _AskSheet extends StatefulWidget {
  const _AskSheet();

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  static const List<({String label, String query})> _quick = [
    (label: 'What\u2019s around me?', query: 'what is around me'),
    (label: 'In front?', query: 'what is in front of me'),
    (label: 'On my left?', query: 'what is on my left'),
    (label: 'On my right?', query: 'what is on my right'),
    (label: 'Anyone there?', query: 'is there anyone there'),
    (label: 'Describe the scene', query: 'describe the scene'),
    (label: 'Find bottle', query: 'find the bottle'),
    (label: 'Find a chair', query: 'find a chair'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ask the assistant',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Type a question about what the camera sees, or pick a quick question.',
            style: TextStyle(
              color: Color(0xFF7C8798),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.done,
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'e.g. What do you see? Find a chair.',
              hintStyle: const TextStyle(color: Color(0xFF5C6775)),
              filled: true,
              fillColor: const Color(0x26FFFFFF),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF1769E0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded,
                    color: Color(0xFF9FC6FF)),
                onPressed: () => _submit(_controller.text),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in _quick)
                ActionChip(
                  label: Text(q.label),
                  onPressed: () => _submit(q.query),
                  backgroundColor: const Color(0x26FFFFFF),
                  side: const BorderSide(color: Color(0x334369FF)),
                  labelStyle: const TextStyle(
                    color: Color(0xFF9FC6FF),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}