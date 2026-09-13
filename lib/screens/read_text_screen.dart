import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ocr_result.dart';
import '../services/camera_service.dart';
import '../services/ocr_service.dart';
import '../services/text_guidance_service.dart';
import '../services/voice_service.dart';
import '../widgets/ocr_result_card.dart';
import '../widgets/read_text_controls.dart';
import '../widgets/text_camera_preview.dart';
import '../widgets/text_guidance_status.dart';

/// Read Text screen - voice-guided text reading assistant.
///
/// Pipeline per guidance frame:
/// CameraImage -> portrait RGBA (rotation applied) -> ML Kit OCR ->
/// normalized text boxes -> guidance service -> voice + overlay.
///
/// Capture: takePicture (or a frame fallback) -> decode to portrait RGBA ->
/// OCR -> bounded text panel + optional TTS via sequential chunks.
///
/// The screen is deliberately scroll-free for accessibility on small screens.
enum _ReadPhase {
  searching,
  positioning,
  holding,
  ready,
  capturing,
  processing,
  result,
  error,
}

class ReadTextScreen extends StatefulWidget {
  const ReadTextScreen({super.key});

  @override
  State<ReadTextScreen> createState() => _ReadTextScreenState();
}

class _ReadTextScreenState extends State<ReadTextScreen> {
  final OcrService _ocr = OcrService();
  final VoiceService _voice = VoiceService();
  final TextGuidanceService _guidance = TextGuidanceService();

  CameraService? _cameraService;
  bool _cameraFailed = false;

  _ReadPhase _phase = _ReadPhase.searching;
  TextGuidance? _lastGuidance;
  String _statusDetail = 'Preparing camera...';

  bool _busyFrame = false;
  bool _captureInProgress = false;
  bool _autoCaptureDone = false;

  String? _capturePath;
  OcrResult? _result;
  Rect? _resultRegion;

  bool _voiceEnabled = true;
  DateTime? _lastGuidanceVoiceAt;

  bool _reading = false;
  bool _stopReading = false;

  static const Duration _guidanceVoiceCooldown = Duration(milliseconds: 1600);

  @override
  void initState() {
    super.initState();
    _voice.setEnabled(_voiceEnabled);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cameraService != null) return;
    _cameraService = Provider.of<CameraService>(context, listen: false);
    _cameraService!.setOnFrameAvailable(_onFrame);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCamera();
    });
  }

  @override
  void dispose() {
    _stopReading = true;
    _voice.stop();
    _cameraService?.setOnFrameAvailable((_) {});
    unawaited(_cameraService?.stopImageStream() ?? Future<void>.value());
    unawaited(_ocr.close());
    super.dispose();
  }

  // ------------------------------------------------------------
  // CAMERA LIFECYCLE
  // ------------------------------------------------------------

  Future<void> _startCamera() async {
    final cs = _cameraService;
    if (cs == null || !mounted) return;
    print('READ_TEXT_CAMERA_INIT_START');
    final bool ok = await cs.startImageStream();
    if (!mounted) return;
    print('READ_TEXT_CAMERA_INIT_RESULT: $ok');
    setState(() {
      _cameraFailed = !ok;
      _statusDetail = ok ? 'Look for text to scan' : (cs.errorMessage ?? 'Camera failed');
    });
    if (!ok && cs.errorMessage != null) {
      print('READ_TEXT_CAMERA_INIT_FAILED: ${cs.errorMessage}');
    }
  }

  // ------------------------------------------------------------
  // GUIDANCE LOOP
  // ------------------------------------------------------------

  void _onFrame(CameraImage image) {
    // Analysis only runs while the user is positioning text.
    if (_busyFrame) return;
    if (_captureInProgress) return;
    if (_phase == _ReadPhase.capturing ||
        _phase == _ReadPhase.processing ||
        _phase == _ReadPhase.result) {
      return;
    }
    _busyFrame = true;
    unawaited(_analyzeFrame(image).whenComplete(() => _busyFrame = false));
  }

  Future<void> _analyzeFrame(CameraImage image) async {
    final cs = _cameraService;
    if (cs == null) return;
    try {
      final converted =
          _ocr.convertFrameToPortraitRgba(image, cs.imageRotationQuarterTurns);
      if (converted == null) return;

      final OcrResult? ocr =
          await _ocr.recognizeRgba(converted.rgba, converted.width, converted.height);
      if (!mounted || ocr == null) return;

      final guidance =
          _guidance.analyze([for (final b in ocr.blocks) b.region]);
      if (!mounted) return;

      setState(() {
        _lastGuidance = guidance;
        _phase = _phaseFromGuidance(guidance);
        _statusDetail = _phase == _ReadPhase.searching
            ? 'No text found. Slowly scan the area.'
            : _guidance.detailFor(guidance);
      });
      _announceGuidance(guidance);

      // Auto-capture once the frame is stable (assisted mode only).
      if (guidance.phase == GuidancePhase.ready &&
          _voiceEnabled &&
          !_autoCaptureDone) {
        _autoCaptureDone = true;
        await _capture();
      }
    } catch (e, st) {
      print('GUIDANCE_ANALYSIS_ERROR: $e');
      print('GUIDANCE_ANALYSIS_STACK: $st');
    }
  }

  _ReadPhase _phaseFromGuidance(TextGuidance guidance) {
    switch (guidance.phase) {
      case GuidancePhase.searching:
        return _ReadPhase.searching;
      case GuidancePhase.moving:
        return _ReadPhase.positioning;
      case GuidancePhase.holding:
        return _ReadPhase.holding;
      case GuidancePhase.ready:
        return _ReadPhase.ready;
    }
  }

  void _announceGuidance(TextGuidance guidance) {
    if (!_voiceEnabled) return;
    final now = DateTime.now();
    if (_lastGuidanceVoiceAt != null &&
        now.difference(_lastGuidanceVoiceAt!) < _guidanceVoiceCooldown) {
      return;
    }
    final String? line = _guidance.voiceLineFor(guidance);
    if (line == null) return;
    _lastGuidanceVoiceAt = now;
    _voice.speak(line);
  }

  // ------------------------------------------------------------
  // CAPTURE + OCR
  // ------------------------------------------------------------

  Future<void> _capture() async {
    if (_captureInProgress) return;
    final cs = _cameraService;
    if (cs == null || cs.controller == null) return;

    _captureInProgress = true;
    _voice.stop();
    if (mounted) {
      setState(() {
        _phase = _ReadPhase.capturing;
        _statusDetail = 'Taking a picture...';
      });
    }

    String? path;
    try {
      try {
        final XFile file = await cs.controller!.takePicture();
        path = file.path;
        print('CAPTURE_TAKEPICTURE_OK: $path');
      } catch (e) {
        print('CAPTURE_TAKEPICTURE_FAILED: $e');
        // Fallback: use the latest live frame converted to a PNG file.
        final CameraImage? latest = cs.latestImage;
        if (latest != null) {
          final converted =
              _ocr.convertFrameToPortraitRgba(latest, cs.imageRotationQuarterTurns);
          if (converted != null) {
            path = await _writeFramePng(
              rgba: converted.rgba,
              width: converted.width,
              height: converted.height,
            );
          }
        }
      }

      if (path == null) {
        if (mounted) {
          setState(() {
            _phase = _ReadPhase.error;
            _statusDetail = 'Capture failed. Please try again.';
          });
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _phase = _ReadPhase.processing;
        _capturePath = path;
        _statusDetail = 'Recognizing text...';
      });

      final OcrResult result = await _ocr.recognizePath(path);
      if (!mounted) return;

      if (result.hasText) {
        _result = result;
        _resultRegion = _unionBlocks(result.blocks);
        _autoCaptureDone = true;
        setState(() {
          _phase = _ReadPhase.result;
          _statusDetail =
              'Recognized ${result.charCount} characters';
        });
        if (_voiceEnabled) {
          unawaited(_startReadAloud());
        }
      } else {
        _autoCaptureDone = true;
        if (mounted) {
          setState(() {
            _phase = _ReadPhase.error;
            _statusDetail = 'No text found in this picture. Try again.';
          });
        }
        if (_voiceEnabled) {
          _voice.speak('No text found. Try again.');
        }
      }
    } catch (e, st) {
      print('CAPTURE_ERROR: $e');
      print('CAPTURE_STACK: $st');
      if (mounted) {
        setState(() {
          _phase = _ReadPhase.error;
          _statusDetail = 'Capture failed. Please try again.';
        });
      }
    } finally {
      _captureInProgress = false;
    }
  }

  Future<String?> _writeFramePng({
    required Uint8List rgba,
    required int width,
    required int height,
  }) async {
    try {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        width,
        height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final ui.Image image = await completer.future;
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return null;
      final int ts = DateTime.now().millisecondsSinceEpoch;
      final File file =
          File('${Directory.systemTemp.path}/read_text_capture_$ts.png');
      await file.writeAsBytes(data.buffer.asUint8List());
      print('CAPTURE_FRAME_FALLBACK_WRITTEN: ${file.path}');
      return file.path;
    } catch (e) {
      print('CAPTURE_FRAME_FALLBACK_FAILED: $e');
      return null;
    }
  }

  Rect? _unionBlocks(List<OcrTextBlock> blocks) {
    if (blocks.isEmpty) return null;
    var left = 1.0, top = 1.0, right = 0.0, bottom = 0.0;
    for (final b in blocks) {
      left = b.region.left < left ? b.region.left : left;
      top = b.region.top < top ? b.region.top : top;
      right = b.region.right > right ? b.region.right : right;
      bottom = b.region.bottom > bottom ? b.region.bottom : bottom;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  // ------------------------------------------------------------
  // READ ALOUD
  // ------------------------------------------------------------

  Future<void> _startReadAloud() async {
    final text = (_result?.text ?? '').trim();
    if (text.isEmpty || _reading) return;
    setState(() {
      _reading = true;
      _stopReading = false;
      _statusDetail = 'Reading aloud...';
    });

    final chunks = _chunkText(text);
    await _voice.speakAllText(
      chunks,
      onDone: () {
        if (!mounted) return;
        setState(() {
          _reading = false;
          _statusDetail = 'Recognized ${_result?.charCount ?? 0} characters';
        });
        if (!_stopReading && _voiceEnabled) {
          _voice.speak('End of text.');
        }
      },
    );
  }

  void _stopReadAloud() {
    _stopReading = true;
    _voice.stop();
    setState(() {
      _reading = false;
    });
  }

  /// Splits long text into natural chunks (paragraph then sentence) capped at
  /// ~220 characters so TTS stays responsive and no chunk is endless.
  List<String> _chunkText(String text) {
    final paragraphs = text
        .split(RegExp(r'\n+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paragraphs.length == 1 && paragraphs.first.length <= 220) {
      return [paragraphs.first];
    }

    const maxLen = 220;
    final chunks = <String>[];
    for (final para in paragraphs) {
      if (para.length <= maxLen) {
        chunks.add(para);
        continue;
      }
      final sentences =
          para.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.isNotEmpty);
      final buffer = StringBuffer();
      for (final sentence in sentences) {
        if (buffer.isNotEmpty && buffer.length + sentence.length + 1 > maxLen) {
          chunks.add(buffer.toString().trim());
          buffer.clear();
        }
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(sentence);
      }
      if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
    }
    return chunks;
  }

  // ------------------------------------------------------------
  // ACTIONS
  // ------------------------------------------------------------

  void _newScan() {
    _stopReading = true;
    _voice.stop();
    _guidance.reset();
    _autoCaptureDone = false;
    setState(() {
      _phase = _ReadPhase.searching;
      _result = null;
      _resultRegion = null;
      _capturePath = null;
      _reading = false;
      _lastGuidance = null;
      _statusDetail = 'Look for text to scan';
    });
  }

  void _toggleVoice() {
    final bool next = !_voiceEnabled;
    setState(() {
      _voiceEnabled = next;
    });
    _voice.setEnabled(next);
    _lastGuidanceVoiceAt = null;
    if (!next) {
      _stopReadAloud();
    }
  }

  // ------------------------------------------------------------
  // STATUS VIEW HELPERS
  // ------------------------------------------------------------

  (IconData, Color, String) _statusView() {
    switch (_phase) {
      case _ReadPhase.searching:
        return (Icons.manage_search, const Color(0xFF1769E0), 'SEARCHING FOR TEXT');
      case _ReadPhase.positioning:
        return (Icons.near_me_outlined, const Color(0xFFB26A00), 'POSITION THE TEXT');
      case _ReadPhase.holding:
        return (Icons.center_focus_strong, const Color(0xFF1769E0), 'HOLD STEADY');
      case _ReadPhase.ready:
        return (Icons.check_circle_outline, const Color(0xFF1E8E3E), 'READY TO CAPTURE');
      case _ReadPhase.capturing:
        return (Icons.photo_camera_outlined, const Color(0xFF1769E0), 'CAPTURING');
      case _ReadPhase.processing:
        return (Icons.document_scanner_outlined, const Color(0xFF1769E0), 'READING TEXT');
      case _ReadPhase.result:
        return (Icons.article_outlined, const Color(0xFF1E8E3E), 'TEXT RECOGNIZED');
      case _ReadPhase.error:
        return (Icons.error_outline, const Color(0xFFC62828), 'NO TEXT FOUND');
    }
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
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18,
            vertical: compact ? 6 : 10,
          ),
          child: Column(
            children: [
              _buildHeader(compact),
              const SizedBox(height: 8),
              _buildStatus(compact),
              const SizedBox(height: 10),
              Expanded(flex: 5, child: _buildMedia(compact)),
              const SizedBox(height: 10),
              if (_phase == _ReadPhase.result || _phase == _ReadPhase.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildResultCard(compact),
                ),
              _buildControls(compact),
              const SizedBox(height: 6),
              _buildHintRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool compact) {
    return SizedBox(
      height: compact ? 48 : 52,
      child: Row(
        children: [
          _HeaderButton(
            icon: Icons.arrow_back_rounded,
            label: 'Back',
            onTap: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Read Text',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF15233D),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Point your camera at text',
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    color: const Color(0xFF718096),
                  ),
                ),
              ],
            ),
          ),
          _HeaderButton(
            icon: _voiceEnabled
                ? Icons.volume_up_outlined
                : Icons.volume_off_outlined,
            label: 'Voice guidance',
            onTap: _toggleVoice,
          ),
        ],
      ),
    );
  }

  Widget _buildStatus(bool compact) {
    final (icon, accent, label) = _statusView();
    if (_cameraFailed) {
      return TextGuidanceStatus(
        icon: Icons.error_outline,
        accent: const Color(0xFFC62828),
        label: 'CAMERA ERROR',
        detail: _statusDetail,
      );
    }
    return TextGuidanceStatus(
      icon: icon,
      accent: accent,
      label: label,
      detail: _statusDetail,
    );
  }

  Widget _buildMedia(bool compact) {
    return Consumer<CameraService>(
      builder: (context, cameraService, child) {
        if (_phase == _ReadPhase.result &&
            _capturePath != null &&
            File(_capturePath!).existsSync()) {
          return _buildSnapshot(compact);
        }
        return TextCameraPreview(
          controller: cameraService.controller,
          initialized: cameraService.isInitialized,
          errorMessage: cameraService.errorMessage,
          textRegion: _lastGuidance?.region,
          blockCount: _lastGuidance?.blockCount ?? 0,
          showFrame: _phase != _ReadPhase.capturing &&
              _phase != _ReadPhase.processing &&
              _phase != _ReadPhase.error,
          statusLabel: _phase == _ReadPhase.error
              ? 'NO TEXT FOUND'
              : _phase == _ReadPhase.capturing
                  ? 'CAPTURING'
                  : _phase == _ReadPhase.processing
                      ? 'READING'
                      : 'SCANNING',
          statusIcon: _phase == _ReadPhase.error
              ? Icons.error_outline
              : _phase == _ReadPhase.capturing
                  ? Icons.photo_camera_outlined
                  : _phase == _ReadPhase.processing
                      ? Icons.document_scanner_outlined
                      : Icons.document_scanner_outlined,
          statusColor: _phase == _ReadPhase.error
              ? const Color(0xFFFF8A80)
              : const Color(0xFF4FC3F7),
        );
      },
    );
  }

  Widget _buildSnapshot(bool compact) {
    final image = Image.file(
      File(_capturePath!),
      fit: BoxFit.fill,
      gaplessPlayback: true,
    );
    final result = _result;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF20252B),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: result?.aspectRatio ?? 0.5625,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    image,
                    if (_resultRegion != null)
                      CustomPaint(
                        painter: _SnapshotRegionPainter(
                          region: _resultRegion!,
                          accent: _reading
                              ? const Color(0xFF4DD0E1)
                              : const Color(0xFF4FC3F7),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _reading ? Icons.graphic_eq : Icons.article_outlined,
                      size: 15,
                      color: const Color(0xFF4FC3F7),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _reading ? 'PLAYING' : 'RECOGNIZED',
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
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(bool compact) {
    if (_phase == _ReadPhase.error || _result == null) {
      return OcrResultCard(text: '', charCount: 0, isReading: false);
    }
    return OcrResultCard(
      text: _result!.text,
      charCount: _result!.charCount,
      isReading: _reading,
    );
  }

  Widget _buildControls(bool compact) {
    final bool showActions =
        _phase == _ReadPhase.result || _phase == _ReadPhase.error;
    return ReadTextControls(
      onCapture: _capture,
      capturing: _phase == _ReadPhase.capturing,
      onReadAloud: _startReadAloud,
      onStopReading: _stopReadAloud,
      isReading: _reading,
      onNewScan: _newScan,
      hasResult: showActions,
      hasError: _phase == _ReadPhase.error,
    );
  }

  Widget _buildHintRow() {
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _voiceEnabled ? Icons.volume_up_outlined : Icons.volume_off_outlined,
            size: 14,
            color: const Color(0xFF8793A5),
          ),
          const SizedBox(width: 5),
          Text(
            _voiceEnabled
                ? 'Voice guidance is ON'
                : 'Voice guidance is OFF',
            style: const TextStyle(fontSize: 10, color: Color(0xFF8793A5)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// HEADER BUTTON
// ═══════════════════════════════════════════════════════

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
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              size: 26,
              color: const Color(0xFF15233D),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// SNAPSHOT OVERLAY PAINTER
// ═══════════════════════════════════════════════════════

class _SnapshotRegionPainter extends CustomPainter {
  final Rect region;
  final Color accent;

  _SnapshotRegionPainter({required this.region, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      region.left * size.width,
      region.top * size.height,
      region.right * size.width,
      region.bottom * size.height,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0x331769E0)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_SnapshotRegionPainter oldDelegate) =>
      oldDelegate.region != region || oldDelegate.accent != accent;
}