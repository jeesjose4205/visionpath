import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/face_detection.dart';
import '../models/app_settings.dart';
import '../models/object_position.dart';
import '../services/camera_service.dart';
import '../services/face_announcement_manager.dart';
import '../services/face_detection_service.dart';
import '../services/face_embedding_service.dart';
import '../services/face_recognition_service.dart';
import '../services/familiar_face_service.dart';
import '../services/settings_service.dart';
import '../services/voice_service.dart';
import '../utils/portrait_rgba.dart';
import '../widgets/face_recognition_overlay.dart';

/// FaceRecognitionScreen runs the live familiar-face recognition pipeline
/// (camera -> ML Kit face detection -> MobileFaceNet embedding match ->
/// temporal confirmation -> voice announcement) over the shared camera,
/// using the same 5-FPS single-flight pump pattern as the navigation screen.
/// If the embedding model is unavailable it falls back to the geometric
/// recognizer.
class FaceRecognitionScreen extends StatefulWidget {
  const FaceRecognitionScreen({super.key});

  @override
  State<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends State<FaceRecognitionScreen> {
  static const Color _navy = Color(0xFF0E2A47);
  static const Color _green = Color(0xFF1E8E3E);

  final VoiceService _voice = VoiceService();
  final FaceDetectionService _detector = FaceDetectionService();
  final FaceRecognitionService _recognition = FaceRecognitionService();
  final FaceAnnouncementManager _annMgr = FaceAnnouncementManager(
    unknownAnnouncements: false,
  );

  // Cached from the provider tree (read outside build from the pump timer).
  late final FamiliarFaceService _faceService;

  CameraService? _cameraService;
  CameraImage? _latestFrame;
  Timer? _pumpTimer;
  bool _busyFrame = false;
  bool _voiceEnabled = true;
  bool _unknownEnabled = false;

  // Latest frame results for the overlay + status.
  List<FaceOverlayEntry> _overlay = [];
  String _statusLine = 'Watching for known faces…';
  String _statusName = '';
  String _statusDetail = '';
  bool _waitingForCamera = true;

  @override
  void initState() {
    super.initState();
    _faceService = context.read<FamiliarFaceService>();
    _applySettings();
    SettingsService.instance.addListener(_applySettings);
    unawaited(FaceEmbeddingService.instance.ensureLoaded());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _initCamera();
    });
  }

  /// Applies persisted settings to this screen's live services.
  void _applySettings() {
    final s = SettingsService.instance;
    _voiceEnabled = s.familiarFacesEnabled &&
        s.familiarFaceVoice &&
        s.voiceGuidanceEnabled;
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

  @override
  void dispose() {
    SettingsService.instance.removeListener(_applySettings);
    _pumpTimer?.cancel();
    _pumpTimer = null;
    _cameraService?.setOnFrameAvailable((_) {});
    final service = _cameraService;
    _cameraService = null;
    _latestFrame = null;
    if (service != null) {
      unawaited(service.stopImageStream());
    }
    _voice.dispose();
    _detector.close();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final service = context.read<CameraService>();
    _cameraService = service;
    final bool ok = await service.initializeController();
    if (!mounted) return;
    if (!ok || service.controller == null) {
      setState(() {
        _waitingForCamera = false;
        _statusLine = 'Unavailable';
        _statusDetail = 'Camera failed to start. Go back and try again.';
      });
      return;
    }
    service.setOnFrameAvailable(_onFrame);
    final bool started = await service.startImageStream();
    if (!mounted) return;
    if (!started) {
      setState(() {
        _waitingForCamera = false;
        _statusLine = 'Unavailable';
        _statusDetail = 'Camera stream could not be started.';
      });
      return;
    }
    setState(() => _waitingForCamera = false);
    _pumpTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_busyFrame) return;
      final frame = _latestFrame;
      if (frame == null) return;
      _busyFrame = true;
      _pump(frame).whenComplete(() => _busyFrame = false);
    });
    print('FACE_RECOGNITION_CAMERA_READY');
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
    ObjectPosition? pos;

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
          color: match.isKnown ? _green : const Color(0xFF8A5660),
          subtitle: match.isKnown ? '${(match.similarity * 100).toInt()}%' : null,
        ),
      );
      if (match.isKnown) {
        status = '${match.personName ?? 'Person'}\u00a0\u00b7\u00a0'
            '${(match.similarity * 100).toInt()}%';
        name = match.personName ?? '';
      } else {
        status = 'Unknown person';
      }
      pos = face.position;
    }

    final now = DateTime.now();
    final lines = _annMgr.update(occurrences, now);
    for (final line in lines) {
      _voice.speak(line);
    }

    if (!mounted) return;
    setState(() {
      _overlay = overlayEntries;
      _statusLine = status;
      _statusName = name;
      _statusDetail = pos != null ? _posText(pos) : '';
    });
  }

  String _posText(ObjectPosition pos) {
    switch (pos) {
      case ObjectPosition.left:
        return 'on your left';
      case ObjectPosition.center:
        return 'directly ahead';
      case ObjectPosition.right:
        return 'on your right';
    }
  }

  void _toggleVoice() {
    final next = !_voiceEnabled;
    setState(() => _voiceEnabled = next);
    _voice.setEnabled(next);
    if (!next) {
      _voice.stop();
    }
  }

  void _toggleUnknown() {
    final next = !_unknownEnabled;
    setState(() => _unknownEnabled = next);
    _annMgr.unknownAnnouncements = next;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraService?.controller;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: _CameraStage(
                  controller: controller,
                  waiting: _waitingForCamera,
                  overlay: _overlay,
                  statusLine: _statusLine,
                  matchName: _statusName,
                  detail: _statusDetail,
                ),
              ),
            ),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  // --------------------------- HEADER ---------------------------

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_navy, Color(0xFF123A63)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoundIconButton(
            icon: Icons.arrow_back_rounded,
            dark: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recognizing Faces',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Point the camera at a person\nto hear who they are',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _LiveBadge(),
        ],
      ),
    );
  }

  // --------------------------- CONTROLS ---------------------------

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ToggleTile(
                  icon: Icons.mic_none_rounded,
                  label: 'Voice',
                  hint: _voiceEnabled ? 'On' : 'Off',
                  active: _voiceEnabled,
                  onTap: _toggleVoice,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ToggleTile(
                  icon: Icons.help_outline_rounded,
                  label: 'Unknowns',
                  hint: _unknownEnabled ? 'Announced' : 'Silent',
                  active: _unknownEnabled,
                  onTap: _toggleUnknown,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 15, color: Color(0xFF8A97AB)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Face data never leaves this device.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------------------- CAMERA STAGE ---------------------------

class _CameraStage extends StatelessWidget {
  const _CameraStage({
    required this.controller,
    required this.waiting,
    required this.overlay,
    required this.statusLine,
    required this.matchName,
    required this.detail,
  });

  final CameraController? controller;
  final bool waiting;
  final List<FaceOverlayEntry> overlay;
  final String statusLine;
  final String matchName;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE1E8F2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF15233D).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null)
            CameraPreview(controller!)
          else
            const Center(child: CircularProgressIndicator()),

          if (waiting)
            Container(color: const Color(0xFF0E2A47).withValues(alpha: 0.85)),

          FaceRecognitionOverlay(entries: overlay),

          // Status pill
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _StatusPill(
              line: statusLine,
              isMatch: matchName.isNotEmpty,
            ),
          ),

          // Position hint pill
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: detail.isEmpty
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        detail,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.line, required this.isMatch});

  final String line;
  final bool isMatch;

  @override
  Widget build(BuildContext context) {
    final Color bg =
        isMatch ? const Color(0xFF1E8E3E) : Colors.black.withValues(alpha: 0.62);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMatch)
            const Icon(Icons.check_circle_rounded,
                size: 16, color: Colors.white),
          if (isMatch) const SizedBox(width: 6),
          Flexible(
            child: Text(
              line,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------- HEADER LIVE BADGE ---------------------------

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF2FBF6A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(),
          SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// --------------------------- TOGGLE TILES ---------------------------

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.hint,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? const Color(0xFF1769E0) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 26,
                color: active ? Colors.white : const Color(0xFF718096),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: active ? Colors.white : const Color(0xFF15233D),
                      ),
                    ),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: active
                            ? Colors.white.withValues(alpha: 0.85)
                            : const Color(0xFF8A97AB),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final bg = dark ? Colors.white.withValues(alpha: 0.12) : Colors.white;
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