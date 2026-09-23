import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/face_detection.dart';
import '../services/camera_service.dart';
import '../services/face_detection_service.dart';
import '../services/face_embedding_service.dart';
import '../services/face_recognition_service.dart';
import '../services/face_registration_guide.dart';
import '../services/familiar_face_service.dart';
import '../services/settings_service.dart';
import '../services/voice_service.dart';
import '../utils/portrait_rgba.dart';
import '../widgets/camera_preview_fit.dart';
import '../widgets/face_recognition_overlay.dart';
import '../widgets/settings_button.dart';

enum _RegStep { details, camera }

/// FaceRegistrationScreen registers a familiar person via voice-guided
/// multi-sample capture.
///
/// Flow: name/relationship -> live camera (front-first, switchable to back)
/// with ML Kit face detection -> positional voice guidance -> 4 valid samples
/// (front, slight left, slight right, front) -> geometric/learned embeddings ->
/// mean embedding -> saved locally.
///
/// The camera is the app's SHARED [CameraService] controller (flipped to the
/// front lens for self-registration and restored to the rear lens on exit), so
/// registration can never fight a second platform camera handle while the rest
/// of the app already holds one — the cause of silent "Could not start the
/// camera" failures on devices. Samples are captured single-flight and the
/// steadiness window resets between captures, so the four samples are real
/// spaced poses instead of one near-duplicate burst.
class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  static const int _targetSamples = 4;
  static const Color _green = Color(0xFF1E8E3E);

  final VoiceService _voice = VoiceService();
  final FaceDetectionService _detector = FaceDetectionService();
  final FaceRecognitionService _recognition = FaceRecognitionService();
  final FaceRegistrationGuide _guide = FaceRegistrationGuide(
    sampleCount: _targetSamples,
  );

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _relCtrl = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  static const List<String> _relQuick = [
    'Mother',
    'Father',
    'Friend',
    'Teacher',
    'Sister',
    'Brother',
  ];

  // Cached from the provider tree (read outside build from the pump timer).
  late final FamiliarFaceService _faceService;
  late final CameraService _cameraService;

  _RegStep _step = _RegStep.details;
  bool _cameraStarting = false;
  bool _cameraFailed = false;
  String _cameraError = '';
  bool _switching = false;

  CameraImage? _latestFrame;
  DetectedFace? _currentFace;
  final List<List<double>> _samples = [];
  bool _capturingSample = false;
  bool _busyFrame = false;

  Timer? _pumpTimer;
  String _lastSpokenKey = '';
  DateTime? _lastVoiceAt;
  bool _finishing = false;
  RegistrationGuidance? _latestGuidance;

  bool _voiceEnabled = true;

  @override
  void initState() {
    super.initState();
    _faceService = context.read<FamiliarFaceService>();
    _cameraService = context.read<CameraService>();
    _applyVoiceSettings();
    SettingsService.instance.addListener(_applyVoiceSettings);
    unawaited(FaceEmbeddingService.instance.ensureLoaded());
  }

  void _applyVoiceSettings() {
    final s = SettingsService.instance;
    final enabled = s.voiceGuidanceEnabled && !s.globalVoiceMuted;
    _voiceEnabled = enabled;
    _voice.setEnabled(enabled);
    unawaited(_voice.setSpeechRate(s.speechRateValue));
    unawaited(_voice.setVolume(s.voiceVolume));
    unawaited(_voice.setLanguage(s.voiceLanguageTag));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_applyVoiceSettings);
    _pumpTimer?.cancel();
    _pumpTimer = null;
    _voice.dispose();
    _detector.close();
    _teardownSharedCamera();
    _nameCtrl.dispose();
    _relCtrl.dispose();
    super.dispose();
  }

  /// Release the shared stream and restore the rear lens if registration left
  /// the camera on the front (selfie) lens, so later recognition keeps using
  /// the rear camera. The controller itself is owned by [CameraService] and is
  /// never disposed here.
  void _teardownSharedCamera() {
    final cs = _cameraService;
    cs.setOnFrameAvailable((_) {});
    if (!cs.isRearFacing) {
      unawaited(cs.flipCamera().catchError((Object _) => false));
    } else {
      unawaited(cs.stopImageStream().catchError((Object _) => true));
    }
  }

  String get _lensName =>
      _cameraService.isRearFacing ? 'BACK' : 'FRONT';

  // ------------------------------------------------------------
  // DETAILS STEP
  // ------------------------------------------------------------

  Future<void> _startCamera() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_cameraStarting) return;
    _cameraStarting = true;
    _voice.stop();
    setState(() => _step = _RegStep.camera);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _vocals('Position the person\'s face in front of the camera.');
      await _beginCamera();
      if (mounted) {
        setState(() => _cameraStarting = false);
      }
    });
  }

  Future<void> _beginCamera() async {
    final cs = _cameraService;
    try {
      // Ensure the single shared controller exists (rear camera by default).
      if (!cs.isInitialized) {
        final bool ok = await cs.initializeController();
        if (!ok || !mounted) {
          _cameraFailure(cs.errorMessage ?? 'Camera could not be started.');
          return;
        }
      }
      // Self-registration is easier on the front camera.
      if (cs.isRearFacing) {
        final bool flipped = await cs.flipCamera();
        if (!flipped || !mounted) {
          _cameraFailure('Could not open the front camera.');
          return;
        }
      }

      cs.setOnFrameAvailable(_onFrame);
      final bool started = await cs.startImageStream();
      if (!mounted) return;
      if (!started) {
        _cameraFailure(cs.errorMessage ?? 'Image stream failed to start.');
        return;
      }

      _latestFrame = null;
      _guide.reset();
      _samples.clear();
      _pumpTimer?.cancel();
      _pumpTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_busyFrame || _finishing || !mounted) return;
        final frame = _latestFrame;
        if (frame == null) return;
        _busyFrame = true;
        _pump(frame).whenComplete(() => _busyFrame = false);
      });
      print('FACE_REG_CAMERA_READY: ${cs.isRearFacing ? "back" : "front"}');
    } catch (e) {
      print('FACE_REG_CAMERA_FAILED: $e');
      _cameraFailure('$e');
    }
  }

  void _cameraFailure(String message) {
    if (!mounted) return;
    setState(() {
      _cameraFailed = true;
      _cameraError = message;
    });
  }

  Future<void> _retryCamera() async {
    if (!mounted) return;
    setState(() => _cameraFailed = false);
    await _beginCamera();
  }

  Future<void> _switchCamera() async {
    if (_switching || _finishing) return;
    _switching = true;
    _voice.stop();
    if (mounted) setState(() {});
    final bool ok = await _cameraService.flipCamera();
    _latestFrame = null;
    if (!ok && mounted) {
      _vocals('Could not switch the camera.');
    }
    if (mounted) setState(() => _switching = false);
    if (ok) {
      _vocals('Switched to the $_lensName camera.');
    }
  }

  void _cancelAndExit() {
    _voice.stop();
    Navigator.of(context).maybePop();
  }

  void _onFrame(CameraImage image) {
    _latestFrame = image;
  }

  // ------------------------------------------------------------
  // CAMERA PUMP
  // ------------------------------------------------------------

  Future<void> _pump(CameraImage image) async {
    final converted = convertFrameToPortraitRgba(
      image,
      _cameraService.imageRotationQuarterTurns,
    );
    if (converted == null) return;
    final faces = await _detector.detectRgba(
      converted.rgba,
      converted.width,
      converted.height,
    );
    if (!mounted) return;

    final face = _pickBestFace(faces);
    final guide = _guide.update(face: face, currentSample: _samples.length);
    _latestGuidance = guide;

    if (guide.faceUsable && !_finishing && !_capturingSample) {
      _captureSample(converted.rgba, converted.width, converted.height, face!);
    } else if (!guide.faceUsable) {
      _speakGuide(guide);
    }

    setState(() {
      _currentFace = face;
    });
  }

  DetectedFace? _pickBestFace(List<DetectedFace> faces) {
    DetectedFace? best;
    for (final f in faces) {
      if (!f.isUpright) continue;
      if (best == null || f.width * f.height > best.width * best.height) {
        best = f;
      }
    }
    return best;
  }

  Future<void> _captureSample(
    Uint8List rgba,
    int width,
    int height,
    DetectedFace face,
  ) async {
    _capturingSample = true;
    try {
      // Primary: MobileFaceNet embedding (learned model). Fall back to the
      // geometric recognizer only if the model isn't ready yet.
      List<double> embedding;
      if (FaceEmbeddingService.instance.isReady) {
        final ml = await FaceEmbeddingService.instance.embeddingFor(
          rgba,
          width,
          height,
          face,
        );
        if (ml == null) return;
        embedding = ml;
      } else {
        final geo = _recognition.generateEmbedding(face);
        if (geo == null) return;
        embedding = geo;
      }

      _samples.add(embedding);
      // Reset the steadiness window so the next capture requires the person
      // to reposition and hold again - real spacing between samples instead
      // of a burst of near-identical frames.
      _guide.reset();
      print('FACE_REG_SAMPLE_CAPTURED: ${_samples.length}/$_targetSamples '
          'yaw=${face.yawDegrees.toStringAsFixed(1)}');

      if (_samples.length >= _targetSamples) {
        await _finishRegistration();
        return;
      }

      if (!mounted) return;
      setState(() {});
      _vocals(
        'Sample ${_samples.length} of $_targetSamples captured. '
        'Keep your face toward the camera and hold steady.',
      );
      _lastSpokenKey = 'sample${_samples.length}';
    } finally {
      _capturingSample = false;
    }
  }

  Future<void> _finishRegistration() async {
    if (_finishing) return;
    _finishing = true;
    final name = _nameCtrl.text.trim();
    final rel = _relCtrl.text.trim();
    await _faceService.addPerson(
      name: name,
      relationship: rel.isEmpty ? null : rel,
      samples: _samples,
    );
    print('FACE_REG_COMPLETE: $name');
    _voice.stop();
    _vocals('Face registration complete.');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) Navigator.of(context).pop(true);
  }

  void _speakGuide(RegistrationGuidance guide) {
    if (guide.dedupeKey == _lastSpokenKey) return;
    _lastSpokenKey = guide.dedupeKey;
    _vocals(guide.message);
  }

  void _vocals(String message) {
    if (!_voiceEnabled) return;
    final now = DateTime.now();
    final last = _lastVoiceAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastVoiceAt = now;
    _voice.speak(message);
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _step == _RegStep.details
                    ? _buildDetails(compact)
                    : _buildCamera(compact),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          Expanded(
            child: Semantics(
              header: true,
              label: 'VisionPath AI',
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'VisionPath '),
                    const TextSpan(
                      text: 'AI',
                      style: TextStyle(color: Color(0xFF1769E0)),
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

  void _toggleVoice() {
    SettingsService.instance.setGlobalVoiceMuted(
      !SettingsService.instance.globalVoiceMuted,
    );
  }

  // ----------------------------- DETAILS -----------------------------

  Widget _buildDetails(bool compact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 18,
        8,
        compact ? 14 : 18,
        compact ? 10 : 16,
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildTitleRow(compact),
                const SizedBox(height: 14),
                _buildInstructionCard(compact),
                const SizedBox(height: 12),
                _buildDetailsCard(compact),
                const SizedBox(height: 12),
                _buildPrivacyNote(compact),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: compact ? 48 : 54,
            child: ElevatedButton.icon(
              onPressed: _cameraStarting ? null : _startCamera,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF175CD3),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.add_a_photo_outlined, size: 25),
              label: Text(
                'REGISTER FACE',
                style: TextStyle(
                  fontSize: compact ? 14 : 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleRow(bool compact) {
    return Row(
      children: [
        _HeaderButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Register a Familiar Face',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 18 : 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF182230),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Add someone the app should recognize by name',
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
    );
  }

  Widget _buildInstructionCard(bool compact) {
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
                  'FIRST-TIME SETUP',
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF667085),
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '4 quick samples. Keep the person\'s face in the camera '
                  'view and follow the spoken guidance each time.',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 14 : 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF182230),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(bool compact) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PERSON DETAILS',
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: const Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 15, color: Color(0xFF182230)),
              decoration: InputDecoration(
                labelText: 'Full name',
                hintText: 'e.g. Mother, Jees, Aunty Selvi',
                prefixIcon: const Icon(Icons.badge_outlined),
                filled: true,
                fillColor: const Color(0xFFF6F8FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF1769E0),
                    width: 1.6,
                  ),
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Name is required'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _relCtrl,
              style: const TextStyle(fontSize: 15, color: Color(0xFF182230)),
              decoration: InputDecoration(
                labelText: 'Relationship (optional)',
                hintText: 'e.g. Mother, Friend, Teacher',
                prefixIcon: const Icon(Icons.favorite_border_rounded),
                filled: true,
                fillColor: const Color(0xFFF6F8FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF1769E0),
                    width: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final rel in _relQuick)
                  ChoiceChip(
                    label: Text(rel),
                    selected: _relCtrl.text == rel,
                    onSelected: (_) => setState(() => _relCtrl.text = rel),
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _relCtrl.text == rel
                          ? Colors.white
                          : const Color(0xFF182230),
                    ),
                    selectedColor: _green,
                    backgroundColor: const Color(0xFFF1F5F9),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyNote(bool compact) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F2EC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: Color(0xFF1E8E3E),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Faces are stored only on this device. Nothing is uploaded.',
              style: TextStyle(
                fontSize: compact ? 11.5 : 12.5,
                color: const Color(0xFF3E6447),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------- CAMERA -----------------------------

  Widget _buildCamera(bool compact) {
    if (_cameraFailed) {
      return _buildCameraFailure(compact);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 18,
        8,
        compact ? 14 : 18,
        compact ? 10 : 16,
      ),
      child: Column(
        children: [
          _buildCameraTitleRow(compact),
          SizedBox(height: compact ? 8 : 12),
          Expanded(
            flex: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildStage(),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: const _FaceScanCornersPainter(),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 14,
                    child: _buildStatusPill(),
                  ),
                  if (_switching)
                    Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          _buildCameraStatusCard(compact),
          SizedBox(height: compact ? 8 : 12),
          _buildGuidanceCard(compact),
          SizedBox(height: compact ? 8 : 12),
          _buildCameraControls(compact),
        ],
      ),
    );
  }

  Widget _buildCameraTitleRow(bool compact) {
    return Row(
      children: [
        _HeaderButton(
          icon: Icons.arrow_back_rounded,
          label: 'Cancel registration',
          onTap: _finishing ? null : _cancelAndExit,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Face Registration',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 18 : 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF182230),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Follow the voice guidance',
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
        const SizedBox(width: 12),
        _HeaderButton(
          icon: Icons.cameraswitch_rounded,
          label: 'Switch camera',
          onTap: (_switching || _finishing) ? null : _switchCamera,
        ),
      ],
    );
  }

  Widget _buildStage() {
    return Consumer<CameraService>(
      builder: (context, cs, child) {
        final controller = cs.controller;
        if (controller == null || !cs.isInitialized) {
          return Container(
            color: const Color(0xFF20252B),
            alignment: Alignment.center,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.face_retouching_natural,
                  color: Colors.white70,
                  size: 54,
                ),
                SizedBox(height: 12),
                Text(
                  'Starting camera…',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          );
        }

        final face = _currentFace;
        final usable = _latestGuidance?.faceUsable ?? false;
        final overlayEntries = face == null
            ? const <FaceOverlayEntry>[]
            : <FaceOverlayEntry>[
                FaceOverlayEntry(
                  box: face.boundingBox,
                  label: usable ? 'FACE OK' : 'HOLD',
                  color: usable ? _green : const Color(0xFF175CD3),
                ),
              ];

        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: const Color(0xFF20252B),
              child: CameraPreviewFit(controller: controller),
            ),
            FaceRecognitionOverlay(entries: overlayEntries),
          ],
        );
      },
    );
  }

  Widget _buildStatusPill() {
    return Consumer<CameraService>(
      builder: (context, cs, child) {
        final active = cs.isImageStreamActive;
        final String label;
        if (_capturingSample) {
          label = 'CAPTURING';
        } else if (_samples.isEmpty) {
          label = 'REGISTERING';
        } else if (_samples.length >= _targetSamples) {
          label = 'COMPLETE';
        } else {
          label = 'SAMPLE ${_samples.length} OF $_targetSamples';
        }
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
                label,
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
      },
    );
  }

  Widget _buildCameraStatusCard(bool compact) {
    final progress = _samples.isEmpty ? 0.0 : _samples.length / _targetSamples;
    final String title;
    final String subtitle;
    if (_cameraStarting) {
      title = 'Starting camera';
      subtitle = 'Please wait…';
    } else if (_samples.isEmpty) {
      title = 'Position the face';
      subtitle = _latestGuidance?.message ??
          'Center the person\'s face in the camera view';
    } else if (_samples.length >= _targetSamples) {
      title = 'Registration complete';
      subtitle = 'Saving ${_nameCtrl.text.trim()}…';
    } else {
      title = 'Capturing samples';
      subtitle = '${_samples.length} of $_targetSamples captured';
    }

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
              color: _samples.isEmpty
                  ? const Color(0xFFEFF5FF)
                  : const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              _samples.isEmpty
                  ? Icons.center_focus_strong_rounded
                  : Icons.check_circle_outline_rounded,
              color: _samples.isEmpty
                  ? const Color(0xFF175CD3)
                  : const Color(0xFF1E8E3E),
              size: compact ? 21 : 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
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
                  subtitle,
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
          const SizedBox(width: 10),
          SizedBox(
            width: compact ? 44 : 48,
            height: compact ? 6 : 7,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: const Color(0xFFE4E7EC),
                valueColor: const AlwaysStoppedAnimation<Color>(_green),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidanceCard(bool compact) {
    final message = _latestGuidance?.message ??
        'Position the person\'s face in front of the camera.';
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
              Icons.record_voice_over_outlined,
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

  Widget _buildCameraControls(bool compact) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: SizedBox(
            height: compact ? 48 : 54,
            child: ElevatedButton.icon(
              onPressed: (_switching || _finishing) ? null : _switchCamera,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF175CD3),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.cameraswitch_rounded, size: 22),
              label: Text(
                'SWITCH CAMERA',
                style: TextStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: compact ? 48 : 54,
            child: OutlinedButton.icon(
              onPressed: _finishing ? null : _cancelAndExit,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD92D20),
                side: const BorderSide(color: Color(0xFFD92D20), width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.close_rounded, size: 22),
              label: Text(
                'CANCEL',
                style: TextStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraFailure(bool compact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 18,
        8,
        compact ? 14 : 18,
        compact ? 10 : 16,
      ),
      child: Column(
        children: [
          _buildCameraTitleRow(compact),
          const SizedBox(height: 18),
          Expanded(
            child: Center(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(compact ? 18 : 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDE8E8),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.videocam_off_rounded,
                        color: Color(0xFFD92D20),
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Camera unavailable',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compact ? 16 : 17,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF182230),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _cameraError,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 12 : 13,
                        color: const Color(0xFF667085),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: compact ? 46 : 52,
                            child: ElevatedButton.icon(
                              onPressed: _retryCamera,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF175CD3),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              label: const Text('RETRY'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: compact ? 46 : 52,
                            child: OutlinedButton(
                              onPressed: _cancelAndExit,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFD92D20),
                                side: const BorderSide(
                                  color: Color(0xFFD92D20),
                                  width: 1.4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text('CANCEL'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
  final VoidCallback? onTap;

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
// SCAN-FRAME CORNERS
// ============================================================

class _FaceScanCornersPainter extends CustomPainter {
  const _FaceScanCornersPainter();

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
    canvas.drawLine(
        Offset(right, bottom), Offset(right - corner, bottom), paint);
    canvas.drawLine(
        Offset(right, bottom), Offset(right, bottom - corner), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}