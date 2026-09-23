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
import '../services/settings_service.dart';
import '../services/text_guidance_service.dart';
import '../services/voice_service.dart';
import '../widgets/ocr_result_card.dart';
import '../widgets/read_text_controls.dart';
import '../widgets/settings_button.dart';
import '../widgets/text_camera_preview.dart';

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

class _ReadTextScreenState extends State<ReadTextScreen>
    with SingleTickerProviderStateMixin {
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

  // ------------------------------------------------------------
  // INTRODUCTORY TITLE CARD
  // ------------------------------------------------------------
  //
  // Covers the camera rectangle when the screen opens and again after each
  // New Scan, fading out to reveal the live preview when START READING is
  // pressed. Uses the same visual design language as the Navigate screen.

  bool _showIntroCard = true;
  late final AnimationController _introController;

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

    // Only a deliberate LEFT swipe returns to Look & Navigate. There is no
    // screen defined to the RIGHT of Read Text, so RIGHT swipes do nothing.
    final direction = velocity != 0 ? velocity : distance;
    if (direction >= 0) return;

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
    _applySettings();
    SettingsService.instance.addListener(_applySettings);
    _voice.setEnabled(_voiceEnabled);
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _voice.speak(
          'Read Text. Read text around you with intelligent camera assistance.',
        );
      }
    });
  }

  void _applySettings() {
    final s = SettingsService.instance;
    _voiceEnabled = s.voiceGuidanceEnabled && !s.globalVoiceMuted;
    setState(() {});
    _voice.setEnabled(_voiceEnabled);
    unawaited(_voice.setSpeechRate(s.speechRateValue));
    unawaited(_voice.setVolume(s.voiceVolume));
    unawaited(_voice.setLanguage(s.voiceLanguageTag));
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
    SettingsService.instance.removeListener(_applySettings);
    _stopReading = true;
    _voice.stop();
    _cameraService?.setOnFrameAvailable((_) {});
    unawaited(_cameraService?.stopImageStream() ?? Future<void>.value());
    unawaited(_ocr.close());
    _introController.dispose();
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
    // Analysis only runs once the introductory card has been dismissed via
    // START READING (the live camera stays covered until then).
    if (_showIntroCard) return;
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
    if (!SettingsService.instance.textPositionGuidance) return;
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

  void _startReading() {
    // Gateway to the live session: the intro card fades away and the
    // existing guidance loop takes over from the next video frame.
    if (!_showIntroCard) return;
    _dismissIntroCard();
  }

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
    // Return to the introductory card so the START / READ cycle can repeat.
    _presentIntroCard();
  }

  void _toggleVoice() {
    SettingsService.instance.setGlobalVoiceMuted(
      !SettingsService.instance.globalVoiceMuted,
    );
    _lastGuidanceVoiceAt = null;
    if (SettingsService.instance.globalVoiceMuted) {
      _stopReadAloud();
    }
  }

  // ------------------------------------------------------------
  // INTRODUCTORY TITLE CARD
  // ------------------------------------------------------------

  /// Hides the introductory card with a smooth fade + scale-down so the live
  /// preview is revealed beneath it. Guarded so a later [_presentIntroCard]
  /// during the fade-out is never cancelled afterwards.
  void _dismissIntroCard() {
    if (!_showIntroCard) return;
    _introController.reverse().whenComplete(() {
      if (mounted && _showIntroCard) {
        setState(() => _showIntroCard = false);
      }
    });
  }

  /// Brings the introductory card back (e.g. after a New Scan) using the same
  /// fade + scale entrance as when the screen opened.
  void _presentIntroCard() {
    if (_showIntroCard) {
      _introController.forward();
      return;
    }
    setState(() => _showIntroCard = true);
    _introController.forward();
  }

  // ------------------------------------------------------------
  // STATUS CONTENT HELPERS
  // ------------------------------------------------------------

  /// (icon, tile background, icon color, title, subtitle) for the status card.
  ({IconData icon, Color tile, Color accent, String title, String subtitle})
      _statusCardData() {
    if (_cameraFailed) {
      return (
        icon: Icons.error_outline,
        tile: const Color(0xFFFDE8E8),
        accent: const Color(0xFFD92D20),
        title: 'Camera error',
        subtitle: _statusDetail,
      );
    }
    if (_showIntroCard) {
      return (
        icon: Icons.menu_book_outlined,
        tile: const Color(0xFFF2F4F7),
        accent: const Color(0xFF475467),
        title: 'Ready to read',
        subtitle: 'Position the text in the camera view',
      );
    }
    switch (_phase) {
      case _ReadPhase.searching:
        return (
          icon: Icons.manage_search,
          tile: const Color(0xFFF2F4F7),
          accent: const Color(0xFF475467),
          title: 'Searching for text',
          subtitle: _statusDetail,
        );
      case _ReadPhase.positioning:
        return (
          icon: Icons.near_me_outlined,
          tile: const Color(0xFFEFF5FF),
          accent: const Color(0xFF175CD3),
          title: 'Position the text',
          subtitle: _statusDetail,
        );
      case _ReadPhase.holding:
        return (
          icon: Icons.center_focus_strong,
          tile: const Color(0xFFEFF5FF),
          accent: const Color(0xFF175CD3),
          title: 'Hold steady',
          subtitle: _statusDetail,
        );
      case _ReadPhase.ready:
        return (
          icon: Icons.check_circle_outline,
          tile: const Color(0xFFE8F5E9),
          accent: const Color(0xFF198754),
          title: 'Text centered',
          subtitle: _statusDetail,
        );
      case _ReadPhase.capturing:
        return (
          icon: Icons.photo_camera_outlined,
          tile: const Color(0xFFEFF5FF),
          accent: const Color(0xFF175CD3),
          title: 'Capturing',
          subtitle: _statusDetail,
        );
      case _ReadPhase.processing:
        return (
          icon: Icons.document_scanner_outlined,
          tile: const Color(0xFFEFF5FF),
          accent: const Color(0xFF175CD3),
          title: 'Reading text',
          subtitle: _statusDetail,
        );
      case _ReadPhase.result:
        return (
          icon: Icons.article_outlined,
          tile: const Color(0xFFE8F5E9),
          accent: const Color(0xFF198754),
          title: 'Text recognized',
          subtitle: _statusDetail,
        );
      case _ReadPhase.error:
        return (
          icon: Icons.error_outline,
          tile: const Color(0xFFFDE8E8),
          accent: const Color(0xFFD92D20),
          title: 'No text found',
          subtitle: _statusDetail,
        );
    }
  }

  String _nextActionMessage() {
    if (_showIntroCard) return 'Press START READING';
    switch (_phase) {
      case _ReadPhase.searching:
        return 'Slowly scan the area for text';
      case _ReadPhase.positioning:
      case _ReadPhase.holding:
      case _ReadPhase.ready:
        return _statusDetail;
      case _ReadPhase.capturing:
        return 'Taking a picture...';
      case _ReadPhase.processing:
        return 'Reading the captured text...';
      case _ReadPhase.result:
        return 'Tap Read Aloud to listen, or New Scan';
      case _ReadPhase.error:
        return 'Tap New Scan and try again';
    }
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
                              if (_showIntroCard)
                                ExcludeSemantics(child: _buildMedia(compact))
                              else
                                Semantics(
                                  container: true,
                                  label: 'Read Text camera',
                                  child: _buildMedia(compact),
                                ),
                              if (_showIntroCard)
                                _ReadIntroTitleCard(
                                  animation: _introController,
                                ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: compact ? 8 : 12),

                      _buildStatusCard(compact),

                      SizedBox(height: compact ? 8 : 12),

                      _buildNextActionCard(compact),

                      SizedBox(height: compact ? 8 : 12),

                      _buildPrimaryArea(compact),
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

          // Voice status toggle
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

  Widget _buildStatusCard(bool compact) {
    final data = _statusCardData();

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
              color: data.tile,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(data.icon, color: data.accent, size: compact ? 21 : 24),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
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
                  data.subtitle,
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

  Widget _buildNextActionCard(bool compact) {
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
              Icons.menu_book_outlined,
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
                  _nextActionMessage(),
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

  Widget _buildPrimaryArea(bool compact) {
    // Before START READING: the single feature gate button, styled exactly
    // like Navigate's START NAVIGATION button.
    if (_showIntroCard) {
      return SizedBox(
        width: double.infinity,
        height: compact ? 48 : 54,
        child: ElevatedButton.icon(
          onPressed: _startReading,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF175CD3),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.auto_stories_outlined, size: 25),
          label: Text(
            'START READING',
            style: TextStyle(
              fontSize: compact ? 14 : 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ),
      );
    }

    // During the live session reuse the existing control set unchanged.
    final bool showActions =
        _phase == _ReadPhase.result || _phase == _ReadPhase.error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showActions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildResultCard(compact),
          ),
        ReadTextControls(
          onCapture: _capture,
          capturing: _phase == _ReadPhase.capturing,
          onReadAloud: _startReadAloud,
          onStopReading: _stopReadAloud,
          isReading: _reading,
          onNewScan: _newScan,
          hasResult: showActions,
          hasError: _phase == _ReadPhase.error,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// HEADER BUTTON
// ═══════════════════════════════════════════════════════
//
// Visually identical to the Navigate screen header button.

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

// ═══════════════════════════════════════════════════════
// READ TEXT INTRODUCTORY TITLE CARD
// ═══════════════════════════════════════════════════════
//
// Rendered inside the camera-preview rectangle with the same dimensions,
// position and rounded corners as the Navigate title card. It covers the
// preview until the user presses START READING, then fades and scales away
// to reveal the live camera. Reappears after each New Scan.

class _ReadIntroTitleCard extends StatelessWidget {
  const _ReadIntroTitleCard({required this.animation});

  /// Drives the entrance (fade in + very slight scale) and the departure
  /// when the user presses START READING.
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
      label: 'VisionPath AI. Read text around you with intelligent camera '
          'assistance.',
      child: ExcludeSemantics(
        child: FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: const _ReadIntroCardContent(),
          ),
        ),
      ),
    );
  }
}

class _ReadIntroCardContent extends StatelessWidget {
  const _ReadIntroCardContent();

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
            child: _ReadGlowBlob(size: 230, color: const Color(0xFF2E7CF6)),
          ),
          Positioned(
            bottom: -90,
            left: -70,
            child: _ReadGlowBlob(size: 260, color: const Color(0xFF7C5BFF)),
          ),
          Positioned(
            bottom: 120,
            right: -50,
            child: _ReadGlowBlob(size: 180, color: const Color(0xFF4C8DFF)),
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
                          _ReadLogoMark(size: short ? 56 : 68),
                          const SizedBox(height: 14),
                          _ReadBrandTitle(fontSize: short ? 22 : 27),
                          const SizedBox(height: 8),
                          const _ReadFeatureTitle(),
                          const SizedBox(height: 6),
                          const _ReadDescription(),
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
                          const _ReadReadyPanel(),
                          const SizedBox(height: 20),
                          const _ReadPageDots(),
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

class _ReadLogoMark extends StatelessWidget {
  const _ReadLogoMark({required this.size});

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
        Icons.document_scanner_outlined,
        color: Colors.white,
        size: size * 0.48,
      ),
    );
  }
}

class _ReadBrandTitle extends StatelessWidget {
  const _ReadBrandTitle({required this.fontSize});

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

class _ReadFeatureTitle extends StatelessWidget {
  const _ReadFeatureTitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'READ TEXT',
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

class _ReadDescription extends StatelessWidget {
  const _ReadDescription();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Read text around you with\nintelligent camera assistance',
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

class _ReadReadyPanel extends StatelessWidget {
  const _ReadReadyPanel();

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
                  'Camera ready to read',
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
                  'Tap below to start reading',
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

class _ReadPageDots extends StatelessWidget {
  const _ReadPageDots();

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
            color: i == 0
                ? const Color(0xFF9FC6FF)
                : Colors.white.withValues(alpha: 0.28),
          ),
        );
      }),
    );
  }
}

class _ReadGlowBlob extends StatelessWidget {
  const _ReadGlowBlob({required this.size, required this.color});

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