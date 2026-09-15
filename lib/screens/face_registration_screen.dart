import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/face_detection.dart';
import '../services/face_detection_service.dart';
import '../services/face_embedding_service.dart';
import '../services/face_recognition_service.dart';
import '../services/face_registration_guide.dart';
import '../services/familiar_face_service.dart';
import '../services/settings_service.dart';
import '../services/voice_service.dart';
import '../utils/portrait_rgba.dart';

enum _RegStep { details, camera }

/// FaceRegistrationScreen registers a familiar person via voice-guided
/// multi-sample capture.
///
/// Flow: name/relationship -> live camera (front-first, switchable to back)
/// with ML Kit face detection -> positional voice guidance -> 4 valid samples
/// (front, slight left, slight right, front) -> geometric embeddings -> mean
/// embedding -> saved locally.
///
/// Design notes:
///  - The registration preview is a round "portrait window" with a green
///    progress ring that fills as samples are captured; the percent complete
///    is shown below the ring.
///  - Registration owns its own CameraController so it can prefer the front
///    camera and switch lenses, independent of the app's shared camera.
class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  static const int _targetSamples = 4;
  static const Color _ink = Color(0xFF15233D);
  static const Color _accent = Color(0xFF1769E0);
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

  _RegStep _step = _RegStep.details;

  // Dedicated registration camera (front-first, switchable).
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  CameraController? _controller;
  bool _switching = false;
  bool _cameraFailed = false;
  bool _busyFrame = false;

  CameraImage? _latestFrame;
  DetectedFace? _currentFace;
  final List<List<double>> _samples = [];

  Timer? _pumpTimer;
  String _lastSpokenKey = '';
  DateTime? _lastVoiceAt;
  bool _finishing = false;
  RegistrationGuidance? _latestGuidance;

  @override
  void initState() {
    super.initState();
    _faceService = context.read<FamiliarFaceService>();
    _applyVoiceSettings();
    SettingsService.instance.addListener(_applyVoiceSettings);
    unawaited(FaceEmbeddingService.instance.ensureLoaded());
  }

  void _applyVoiceSettings() {
    final s = SettingsService.instance;
    _voice.setEnabled(s.voiceGuidanceEnabled);
    unawaited(_voice.setSpeechRate(s.speechRateValue));
    unawaited(_voice.setVolume(s.voiceVolume));
    unawaited(_voice.setLanguage(s.voiceLanguageTag));
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_applyVoiceSettings);
    _pumpTimer?.cancel();
    _pumpTimer = null;
    _teardownControllerAsync();
    _voice.dispose();
    _detector.close();
    _nameCtrl.dispose();
    _relCtrl.dispose();
    super.dispose();
  }

  void _teardownControllerAsync() {
    final c = _controller;
    if (c == null) return;
    _controller = null;
    unawaited(c.stopImageStream().catchError((Object _) {}));
    unawaited(c.dispose().then((_) {}));
  }

  int get _quarterTurns {
    final s = _controller?.description.sensorOrientation ?? 90;
    return ((s % 360) / 90).round() % 4;
  }

  String get _lensName {
    if (_cameras.isEmpty) return 'CAMERA';
    final dir = _cameras[_cameraIndex].lensDirection;
    return dir == CameraLensDirection.front ? 'FRONT' : 'BACK';
  }

  // ------------------------------------------------------------
  // DETAILS STEP
  // ------------------------------------------------------------

  Future<void> _startCamera() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _step = _RegStep.camera);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _vocals('Position the person\'s face in front of the camera.');
      await _initCamera();
    });
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => _cameraFailed = true);
        return;
      }
      // Front camera first, then back, as requested.
      final sorted = List<CameraDescription>.of(cams);
      sorted.sort((a, b) =>
          _lensRank(a.lensDirection).compareTo(_lensRank(b.lensDirection)));
      _cameras = sorted;
      await _openCameraAt(0);
    } catch (e) {
      print('FACE_REG_CAMERA_LIST_FAILED: $e');
      if (mounted) setState(() => _cameraFailed = true);
    }
  }

  int _lensRank(CameraLensDirection d) {
    switch (d) {
      case CameraLensDirection.front:
        return 0;
      case CameraLensDirection.back:
        return 1;
      default:
        return 2;
    }
  }

  Future<void> _openCameraAt(int index) async {
    await _stopControllerStream();
    final cam = _cameras[index];
    final next = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await next.initialize();
      _controller = next;
      _cameraIndex = index;
      _latestFrame = null;
      _busyFrame = false;
      await next.startImageStream(_onFrame);
      _guide.reset();
      _pumpTimer?.cancel();
      _pumpTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_busyFrame) return;
        final frame = _latestFrame;
        if (frame == null) return;
        _busyFrame = true;
        _pump(frame).whenComplete(() => _busyFrame = false);
      });
      print('FACE_REG_CAMERA_READY: ${cam.lensDirection}');
    } catch (e) {
      print('FACE_REG_CAMERA_FAILED: $e');
      unawaited(next.dispose());
      if (mounted) setState(() => _cameraFailed = true);
    }
  }

  Future<void> _stopControllerStream() async {
    _pumpTimer?.cancel();
    _pumpTimer = null;
    final c = _controller;
    _controller = null;
    if (c != null) {
      if (c.value.isStreamingImages) {
        await c.stopImageStream().catchError((Object _) {});
      }
      await c.dispose();
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.isEmpty || _switching || _finishing) return;
    final next = (_cameraIndex + 1) % _cameras.length;
    if (next == _cameraIndex) return;
    setState(() => _switching = true);
    await _openCameraAt(next);
    if (mounted) setState(() => _switching = false);
    _vocals('Switched to the $_lensName camera.');
  }

  void _onFrame(CameraImage image) {
    _latestFrame = image;
  }

  // ------------------------------------------------------------
  // CAMERA PUMP
  // ------------------------------------------------------------

  Future<void> _pump(CameraImage image) async {
    final converted = convertFrameToPortraitRgba(image, _quarterTurns);
    if (converted == null) return;
    final faces = await _detector.detectRgba(
      converted.rgba,
      converted.width,
      converted.height,
    );

    final face = _pickBestFace(faces);
    final guide = _guide.update(face: face, currentSample: _samples.length);
    _latestGuidance = guide;
    if (_samples.isEmpty) {
      _speakGuide(guide);
    }

    if (guide.faceUsable && !_finishing) {
      _captureSample(converted.rgba, converted.width, converted.height, face!);
    } else {
      _speakGuide(guide);
    }

    if (mounted) {
      setState(() {
        _currentFace = face;
      });
    }
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
    print('FACE_REG_SAMPLE_CAPTURED: ${_samples.length}/$_targetSamples '
        'yaw=${face.yawDegrees.toStringAsFixed(1)}');

    if (_samples.length >= _targetSamples) {
      await _finishRegistration();
      return;
    }

    if (!mounted) return;
    setState(() {});
    _vocals(
      'Sample ${_samples.length} of $_targetSamples captured. ' +
          _guide.expectedPoseHint(_samples.length),
    );
    _lastSpokenKey = 'sample${_samples.length}';
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
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5FA),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child:
              _step == _RegStep.details ? _buildDetails() : _buildCamera(),
        ),
      ),
    );
  }

  // ----------------------------- DETAILS -----------------------------

  Widget _buildDetails() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RoundIconButton(
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Register a Familiar Face',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Add someone the app should recognize by name',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1769E0), Color(0xFF0E2A47)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Row(
              children: [
                Icon(Icons.face_retouching_natural_rounded,
                    size: 42, color: Colors.white),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '4 quick samples',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Keep the face in the round window, keep the '
                        'phone steady, and follow the voice guidance.',
                        style: TextStyle(color: Color(0xFFD6E4F3), fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE1E8F2)),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PERSON DETAILS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: Color(0xFF8A97AB),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _nameCtrl,
                        autofocus: true,
                        style: const TextStyle(fontSize: 16, color: _ink),
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          hintText: 'e.g. Mother, Jees, Aunty Selvi',
                          prefixIcon: Icon(Icons.badge_outlined),
                          filled: true,
                          fillColor: Color(0xFFF6F8FC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                            borderSide: BorderSide(color: Color(0xFFE1E8F2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                            borderSide: BorderSide(color: _accent, width: 1.6),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _relCtrl,
                        style: const TextStyle(fontSize: 16, color: _ink),
                        decoration: const InputDecoration(
                          labelText: 'Relationship (optional)',
                          hintText: 'e.g. Mother, Friend, Teacher',
                          prefixIcon: Icon(Icons.favorite_border_rounded),
                          filled: true,
                          fillColor: Color(0xFFF6F8FC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                            borderSide: BorderSide(color: Color(0xFFE1E8F2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                            borderSide: BorderSide(color: _accent, width: 1.6),
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
                              onSelected: (_) =>
                                  setState(() => _relCtrl.text = rel),
                              showCheckmark: false,
                              labelStyle: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _relCtrl.text == rel
                                    ? Colors.white
                                    : _ink,
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
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F2EC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 18, color: Color(0xFF1E8E3E)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Faces are stored only on this device. Nothing is uploaded.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF3E6447),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 58),
              backgroundColor: _green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            onPressed: _startCamera,
            icon: const Icon(Icons.add_a_photo_outlined, size: 24),
            label: const Text('REGISTER FACE'),
          ),
        ],
      ),
    );
  }

  // ----------------------------- CAMERA -----------------------------

  Widget _buildCamera() {
    if (_cameraFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded,
                size: 44, color: Color(0xFFC62828)),
            const SizedBox(height: 10),
            const Text('Could not start the camera',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                setState(() => _cameraFailed = false);
                _initCamera();
              },
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    final progress = _samples.isEmpty
        ? 0.0
        : _samples.length / _targetSamples;
    final percent = (progress * 100).round();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0E2A47), Color(0xFF123A63)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    dark: true,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Face Registration',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Follow the voice guidance',
                          style: TextStyle(fontSize: 12, color: Color(0xFF9FB8D2)),
                        ),
                      ],
                    ),
                  ),
                  _CameraChip(
                    label: _lensName,
                    icon: Icons.cameraswitch_rounded,
                    onPressed: _cameras.length > 1 ? _switchCamera : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RoundReadout(
                        progress: progress,
                        face: _currentFace,
                        controller: _controller,
                        switching: _switching,
                        hasFace: _currentFace != null &&
                            (_latestGuidance?.faceUsable ?? false),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '$percent%',
                        style: TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.w900,
                          color: _progressTextColor(),
                          height: 1.0,
                        ),
                      ),
                      Text(
                        'REGISTRATION COMPLETE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < _targetSamples; i++) ...[
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < _samples.length
                                    ? _green
                                    : Colors.white.withValues(alpha: 0.18),
                                border: Border.all(
                                  color: i < _samples.length
                                      ? Colors.white.withValues(alpha: 0.9)
                                      : Colors.white.withValues(alpha: 0.25),
                                  width: 1.4,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: i < _samples.length
                                  ? const Icon(Icons.check_rounded,
                                      size: 16, color: Colors.white)
                                  : Text(
                                      '${i + 1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFB9CBE0),
                                      ),
                                    ),
                            ),
                            if (i != _targetSamples - 1)
                              const SizedBox(width: 12),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 18),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Text(
                          _guideMessageRealtime(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _samples.isEmpty
                            ? 'Hold the round window still while a sample is taken'
                            : 'Sample ${_samples.length} of $_targetSamples captured',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _progressTextColor() {
    if (_samples.isEmpty) return Colors.white;
    if (_samples.length >= _targetSamples) return const Color(0xFF6EE7A0);
    return const Color(0xFF9FE8C1);
  }

  String _guideMessageRealtime() {
    return _latestGuidance?.message ??
        'Position the person\'s face in front of the camera.';
  }
}

// ----------------------- ROUND READOUT ------------------------------

/// The round registration window: circular camera preview wrapped in a green
/// progress ring that fills as samples are captured. The percentage is shown
/// by the caller below this widget.
class _RoundReadout extends StatelessWidget {
  const _RoundReadout({
    required this.progress,
    required this.face,
    required this.controller,
    required this.switching,
    required this.hasFace,
  });

  final double progress;
  final DetectedFace? face;
  final CameraController? controller;
  final bool switching;
  final bool hasFace;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final circ = math.min(screenW - 96, 340.0);
    final ringGap = 14.0;
    final previewSize = circ - ringGap * 2 - 16;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: circ,
          height: circ,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Green progress ring on the border.
              SizedBox(
                width: circ,
                height: circ,
                child: CircularProgressIndicator(
                  value: progress.clamp(0.0, 1.0).toDouble(),
                  strokeWidth: ringGap,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation(_FaceRegGreen),
                  strokeCap: StrokeCap.round,
                ),
              ),
              // Round camera preview inside the ring.
              SizedBox(
                width: previewSize,
                height: previewSize,
                child: ClipOval(
                  child: () {
                    final cam = controller;
                    return cam == null
                        ? Container(color: const Color(0xFF0A1B30))
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              CameraPreview(cam),
                              CustomPaint(painter: _ReticlePainter(face)),
                              if (switching)
                                Container(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  alignment: Alignment.center,
                                  child: const CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          );
                  }(),
                ),
              ),
              // Live "face detected" flash badge at the top of the ring.
              Positioned(
                top: 6,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: hasFace ? 1 : 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _FaceRegGreen,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'FACE OK',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'ROUND WINDOW',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

const Color _FaceRegGreen = Color(0xFF2FBF6A);

/// Target ring + live face indicator drawn over the camera preview.
class _ReticlePainter extends CustomPainter {
  const _ReticlePainter(this.face);

  final DetectedFace? face;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final w = size.width;

    // Soft target ring for centering.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.30);
    canvas.drawCircle(center, w * 0.34, ring);
    canvas.drawCircle(center, w * 0.36, ring..strokeWidth = 1);
    // Gentle crosshair ticks.
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 2;
    final k = w * 0.30;
    canvas.drawLine(Offset(0, center.dy), Offset(k, center.dy), tick);
    canvas.drawLine(Offset(w - k, center.dy), Offset(w, center.dy), tick);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, k), tick);
    canvas.drawLine(Offset(center.dx, w - k), Offset(center.dx, w), tick);

    // Live face position dot.
    final f = face;
    if (f == null || !f.isUpright) return;
    final pos = Offset(f.centerX * w, f.centerY * w);
    if (pos.dx < 0 || pos.dy < 0 || pos.dx > w || pos.dy > w) return;
    final dot = Paint()..color = const Color(0xFF2FBF6A);
    canvas.drawCircle(pos, 5, dot);
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x662FBF6A);
    canvas.drawCircle(pos, 10, halo);
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter old) =>
      old.face != face;
}

// ----------------------- SHARED CHROME ------------------------------

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
    this.dark = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : const Color(0xFF15233D);
    final bg = dark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      elevation: dark ? 0 : 1,
      child: IconButton(
        icon: Icon(icon, color: fg),
        onPressed: onPressed,
        iconSize: 24,
        padding: const EdgeInsets.all(11),
      ),
    );
  }
}

class _CameraChip extends StatelessWidget {
  const _CameraChip({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onPressed == null
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}