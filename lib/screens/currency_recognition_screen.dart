import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/currency_recognition.dart';
import '../services/camera_service.dart';
import '../services/currency_command_parser.dart';
import '../services/currency_recognition_service.dart';
import '../services/currency_stability_verifier.dart';
import '../services/settings_service.dart';
import '../services/speech_capture_service.dart';
import '../services/vibration_service.dart';
import '../services/voice_command_controller.dart';
import '../services/voice_service.dart';
import '../services/web_speech_engine.dart';
import '../utils/portrait_rgba.dart';
import '../widgets/camera_preview_fit.dart';
import '../widgets/press_and_hold_voice_region.dart';
import '../widgets/settings_button.dart';
import '../widgets/settings_scope.dart';
import '../widgets/sound_mode_button.dart';
import '../widgets/voice_search_overlay.dart';

/// Runtime camera permission as this screen sees it.
///
/// [unknown] means the platform could not answer at all (desktop, tests,
/// broken channel); scanning is allowed to proceed and the camera reports its
/// own failure if there genuinely is no camera.
enum CameraPermissionOutcome { granted, denied, unknown }

/// Currency Recognition screen — offline identification of Indian banknotes
/// for low-vision users.
///
/// Pipeline per analysed frame:
/// CameraImage -> portrait RGBA (rotation applied) -> on-device TFLite note
/// detector -> best denomination -> voice + result card.
///
/// Recognition is detection-only (no authenticity claims) and covers banknotes
/// only: the bundled detector has no coin classes. The screen is deliberately
/// scroll-free for accessibility, mirroring Read Text.
enum _CurrencyPhase {
  /// Models are still loading; the camera has not been started yet.
  initializing,

  /// Models are ready (or unavailable) and the intro card is showing.
  ready,

  /// Live camera is being analysed for currency.
  scanning,

  /// A reliable denomination has been identified and locked in.
  identified,

  /// Analysis is running but nothing reliable has been seen yet.
  uncertain,

  /// Camera or model failure.
  error,
}

class CurrencyRecognitionScreen extends StatefulWidget {
  const CurrencyRecognitionScreen({
    super.key,
    @visibleForTesting this.service,
    @visibleForTesting this.requestCameraPermission,
    @visibleForTesting
    this.analysisInterval = const Duration(milliseconds: 600),
  });

  /// Overrides the shared recognition service, so tests can drive the screen
  /// without bundled models.
  final CurrencyRecognitionService? service;

  /// Overrides the runtime camera-permission request. Widget tests cannot
  /// reach a platform channel for it, so they inject a canned answer here.
  final Future<CameraPermissionOutcome> Function()? requestCameraPermission;

  /// Minimum gap between inference passes. Injectable because tests fake the
  /// clock, and the real device clock does not advance under the test fake.
  final Duration analysisInterval;

  @override
  State<CurrencyRecognitionScreen> createState() =>
      _CurrencyRecognitionScreenState();
}

class _CurrencyRecognitionScreenState extends State<CurrencyRecognitionScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final CurrencyRecognitionService _service =
      widget.service ?? CurrencyRecognitionService();
  final VoiceService _voice = VoiceService();
  final VoiceCommandController _voiceCommand = VoiceCommandController();

  /// Multi-frame agreement: one confident frame is not an answer, two
  /// agreeing frames are.
  final CurrencyStabilityVerifier _verifier = CurrencyStabilityVerifier();

  /// Keeps the same note from being announced over and over while it stays in
  /// view, and rate-limits the "unable to identify" message.
  final CurrencyAnnouncementGate _gate = CurrencyAnnouncementGate();

  CameraService? _cameraService;
  bool _cameraFailed = false;
  bool _permissionDenied = false;

  _CurrencyPhase _phase = _CurrencyPhase.initializing;
  String _statusDetail = 'Preparing currency recognition...';
  CurrencyRecognition? _result;

  /// What the scan session is looking for; applies from the next scan start.
  CurrencyScanMode _mode = CurrencyScanMode.both;

  bool _scanInProgress = false;
  bool _busyFrame = false;
  bool _paused = false;

  /// True while the app is backgrounded: the stream is stopped but the session
  /// (phase, result) survives so a quick app-switch does not lose the read.
  bool _backgrounded = false;

  /// Consecutive inference errors before the session is declared broken.
  int _inferenceErrors = 0;
  static const int _maxInferenceErrors = 5;

  DateTime _lastAnalysisAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _voiceEnabled = true;

  bool _showIntroCard = true;
  late final AnimationController _introController;

  // ------------------------------------------------------------
  // LIFECYCLE
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applySettings();
    SettingsService.instance.addListener(_applySettings);
    _voice.setEnabled(_voiceEnabled);
    _voiceCommand
      ..onCommand = _onVoiceCommand
      ..onFailure = _onVoiceCommandFailure;
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    )..forward();
    // Idempotent: Navigate may already have started the shared engine.
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      unawaited(SpeechCaptureService.instance.webEngine.start());
    }
    unawaited(_loadModels());
  }

  /// Suspend camera work when the app leaves the foreground and resume the
  /// session when it comes back. The shared CameraController is also paused by
  /// the OS, so leaving the stream armed while backgrounded just produces
  /// errors (and on some devices a black preview afterwards).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _suspendSession();
      case AppLifecycleState.resumed:
        _resumeSession();
    }
  }

  void _suspendSession() {
    if (_backgrounded) return;
    _backgrounded = true;
    final CameraService? cs = _cameraService;
    if (cs == null) return;
    if (!_sessionActive && !cs.isImageStreamActive) return;
    cs.setOnFrameAvailable((_) {});
    unawaited(cs.stopImageStream());
  }

  void _resumeSession() {
    if (!_backgrounded) return;
    _backgrounded = false;
    if (!_sessionActive) return;
    final CameraService? cs = _cameraService;
    if (cs == null) return;
    cs.setOnFrameAvailable(_onFrame);
    unawaited(cs.startImageStream());
  }

  void _applySettings() {
    final SettingsService s = SettingsService.instance;
    _voiceEnabled = !s.vibrateMode;
    if (mounted) setState(() {});
    _voice.setEnabled(_voiceEnabled);
    _service.threshold = CurrencyRecognitionService.defaultThreshold;
  }

  Future<void> _loadModels() async {
    await _service.ensureLoaded();
    if (!mounted) return;
    if (!_service.anyModelAvailable) {
      setState(() {
        _phase = _CurrencyPhase.error;
        _permissionDenied = false;
        _statusDetail =
            _service.loadError ??
            'Currency model unavailable. '
                'The recognition model is not installed in this build.';
      });
      return;
    }
    setState(() {
      _phase = _CurrencyPhase.ready;
      _permissionDenied = false;
      _statusDetail = 'Camera ready. Press START SCANNING.';
    });
    _speakGreeting();
  }

  /// Retry after the error phase: reload the models (a failed load is cached),
  /// then try the camera again.
  Future<void> _retry() async {
    if (_scanInProgress) return;
    _scanInProgress = true;
    try {
      setState(() {
        _phase = _CurrencyPhase.initializing;
        _statusDetail = 'Retrying...';
      });
      await _service.reload();
      if (!mounted) return;
      if (!_service.anyModelAvailable) {
        setState(() {
          _phase = _CurrencyPhase.error;
          _statusDetail = _service.loadError ?? 'Currency model unavailable.';
        });
        return;
      }
      setState(() {
        _phase = _CurrencyPhase.ready;
        _statusDetail = 'Camera ready. Press START SCANNING.';
      });
      await _startScan();
    } finally {
      _scanInProgress = false;
    }
  }

  void _speakGreeting() {
    if (!_voiceEnabled) return;
    _voice.enqueueSpeech(
      'Currency Recognition. Hold one banknote in front of the camera.',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cameraService != null) return;
    _cameraService = Provider.of<CameraService>(context, listen: false);
    // The camera is intentionally NOT started here: it opens only when the user
    // presses START SCANNING (see [_startScan]).
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SettingsService.instance.removeListener(_applySettings);
    _voiceCommand
      ..onCommand = null
      ..onFailure = null;
    unawaited(_voiceCommand.cancel());
    _voice.stop();
    _cameraService?.setOnFrameAvailable((_) {});
    unawaited(_cameraService?.stopImageStream() ?? Future<void>.value());
    _introController.dispose();
    super.dispose();
  }

  /// Ask for the runtime CAMERA permission the first time a scan is started.
  ///
  /// The manifest declaration alone does not grant access on Android 6+; the
  /// camera would otherwise fail with a generic error the user cannot act on.
  Future<CameraPermissionOutcome> _ensureCameraPermission() async {
    final Future<CameraPermissionOutcome> Function()? injected =
        widget.requestCameraPermission;
    if (injected != null) return injected();
    try {
      final PermissionStatus current = await Permission.camera.status;
      if (current.isGranted) return CameraPermissionOutcome.granted;
      if (current.isPermanentlyDenied) return CameraPermissionOutcome.denied;
      final PermissionStatus requested = await Permission.camera.request();
      if (requested.isGranted) return CameraPermissionOutcome.granted;
      if (requested.isPermanentlyDenied || requested.isDenied) {
        return CameraPermissionOutcome.denied;
      }
      return CameraPermissionOutcome.unknown;
    } catch (e) {
      print('CURRENCY_CAMERA_PERMISSION_FAILED: $e');
      return CameraPermissionOutcome.unknown;
    }
  }

  // ------------------------------------------------------------
  // SCANNING
  // ------------------------------------------------------------

  Future<void> _startScan() async {
    if (_scanInProgress) return;
    _scanInProgress = true;
    _dismissIntroCard();
    _voice.stop();

    try {
      final CameraPermissionOutcome permission =
          await _ensureCameraPermission();
      if (!mounted) return;
      if (permission == CameraPermissionOutcome.denied) {
        setState(() {
          _permissionDenied = true;
          _cameraFailed = false;
          _phase = _CurrencyPhase.error;
          _statusDetail =
              'Camera permission is required to scan currency. '
              'Allow camera access in system settings, then retry.';
        });
        _voice.enqueueSpeech('Camera permission is required to scan currency.');
        return;
      }

      final CameraService? cs = _cameraService;
      if (cs == null) {
        _fail('Camera is unavailable.');
        return;
      }
      if (!cs.isInitialized) {
        final bool ok = await cs.initializeController();
        if (!ok || !mounted) {
          _fail(cs.errorMessage ?? 'Camera could not be started.');
          return;
        }
      }
      if (!mounted) return;
      cs.setOnFrameAvailable(_onFrame);
      final bool streamed = await cs.startImageStream();
      if (!mounted) return;
      if (!streamed) {
        _fail(cs.errorMessage ?? 'Camera stream failed.');
        return;
      }
      setState(() {
        _cameraFailed = false;
        _permissionDenied = false;
        _phase = _CurrencyPhase.scanning;
        _paused = false;
        _result = null;
        _verifier.reset();
        _gate.reset();
        _inferenceErrors = 0;
        _statusDetail = _mode.guidance;
      });
    } finally {
      _scanInProgress = false;
    }
  }

  Future<void> _stopScan() async {
    final CameraService? cs = _cameraService;
    cs?.setOnFrameAvailable((_) {});
    await cs?.stopImageStream();
    if (!mounted) return;
    setState(() {
      _phase = _CurrencyPhase.ready;
      _paused = false;
      _result = null;
      _verifier.reset();
      _statusDetail = 'Camera ready. Press START SCANNING.';
    });
    _presentIntroCard();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _cameraFailed = true;
      _permissionDenied = false;
      _phase = _CurrencyPhase.error;
      _statusDetail = message;
    });
  }

  void _scanAgain() {
    _voice.stop();
    setState(() {
      _phase = _CurrencyPhase.scanning;
      _paused = false;
      _result = null;
      _verifier.reset();
      _gate.reset();
      _inferenceErrors = 0;
      _statusDetail = _mode.guidance;
    });
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
  }

  // ------------------------------------------------------------
  // FRAME ANALYSIS
  // ------------------------------------------------------------

  void _onFrame(CameraImage image) {
    if (_phase != _CurrencyPhase.scanning) return;
    if (_paused || _busyFrame || _backgrounded) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastAnalysisAt) < widget.analysisInterval) return;
    _lastAnalysisAt = now;
    _busyFrame = true;
    unawaited(_analyzeFrame(image).whenComplete(() => _busyFrame = false));
  }

  Future<void> _analyzeFrame(CameraImage image) async {
    final CameraService? cs = _cameraService;
    if (cs == null) return;
    try {
      final ({Uint8List rgba, int width, int height})? frame =
          convertFrameToPortraitRgba(image, cs.imageRotationQuarterTurns);
      if (frame == null) return;

      final CurrencyInferenceResult outcome = await _service.analyze(
        frame.rgba,
        frame.width,
        frame.height,
        kinds: _mode.kinds,
      );
      if (!mounted || _phase != _CurrencyPhase.scanning) return;

      switch (outcome.status) {
        case CurrencyInferenceStatus.busy:
          // Another frame is still in flight; the screen's own _busyFrame
          // flag already prevents this, so nothing to do.
          break;
        case CurrencyInferenceStatus.invalidInput:
          // A malformed frame is normal churn, not a failure of the session.
          break;
        case CurrencyInferenceStatus.inferenceError:
          _inferenceErrors++;
          print(
            'CURRENCY_INFERENCE_ERROR_COUNT: $_inferenceErrors '
            'reason=${outcome.reason}',
          );
          if (_inferenceErrors >= _maxInferenceErrors) {
            _fail(
              'Currency recognition failed repeatedly. '
              '${outcome.reason ?? ''}',
            );
          }
          break;
        case CurrencyInferenceStatus.modelUnavailable:
          _fail(outcome.reason ?? 'Currency model became unavailable.');
          break;
        case CurrencyInferenceStatus.uncertain:
          _inferenceErrors = 0;
          _markUncertain(reason: outcome.reason);
          break;
        case CurrencyInferenceStatus.recognized:
          _inferenceErrors = 0;
          _handleRecognition(outcome.recognition!);
          break;
      }
    } catch (e, st) {
      print('CURRENCY_ANALYSIS_ERROR: $e');
      print('CURRENCY_ANALYSIS_STACK: $st');
    }
  }

  /// Feed one confident frame to the multi-frame verifier. A denomination is
  /// only announced once [CurrencyStabilityVerifier.requiredAgreements]
  /// consecutive frames agree on it.
  void _handleRecognition(CurrencyRecognition rec) {
    final CurrencyStability stability = _verifier.feed(rec);
    switch (stability.outcome) {
      case CurrencyStabilityOutcome.none:
        break;
      case CurrencyStabilityOutcome.waiting:
        setState(() {
          _phase = _CurrencyPhase.scanning;
          _statusDetail = 'Checking... hold steady.';
        });
      case CurrencyStabilityOutcome.stable:
        _lockResult(stability.accepted ?? rec);
        break;
      case CurrencyStabilityOutcome.alreadyStable:
        // Same note still in view; the result card already shows it and the
        // gate has already spoken it once.
        break;
    }
  }

  void _markUncertain({String? reason}) {
    if (!mounted || _phase == _CurrencyPhase.identified) return;
    setState(() {
      _phase = _CurrencyPhase.uncertain;
      _statusDetail = reason == null
          ? 'Currency not detected. Please point the camera at a banknote.'
          : 'Currency not detected ($reason). Please point the camera at a '
                'banknote.';
    });
    _announceUncertain();
  }

  void _lockResult(CurrencyRecognition rec) {
    setState(() {
      _phase = _CurrencyPhase.identified;
      _result = rec;
      _statusDetail = 'Identified ${rec.displayLabel}.';
    });
    if (SettingsService.instance.vibrateMode) {
      VibrationService.instance.vibrateNavigation();
    }
    _announceResult(rec);
  }

  // ------------------------------------------------------------
  // VOICE COMMANDS + VOICE FEEDBACK
  // ------------------------------------------------------------

  /// Route a press-and-hold transcript. Stop outranks start: a sentence that
  /// asks to stop can never open a scan, and only an explicit start (or
  /// "start scanning") can.
  void _onVoiceCommand(String transcript) {
    final CurrencyCommandAction action = CurrencyCommandParser.action(
      transcript,
      allowBareStop: true,
    );
    switch (action) {
      case CurrencyCommandAction.stop:
        if (_sessionActive) unawaited(_stopScan());
        return;
      case CurrencyCommandAction.start:
        if (_phase == _CurrencyPhase.ready) unawaited(_startScan());
        return;
      case CurrencyCommandAction.none:
        if (_repeatRequested(transcript)) _repeatResult();
        return;
    }
  }

  void _onVoiceCommandFailure(VoiceCommandFailure failure) {
    final String message = VoiceCommandController.isPermissionProblem(failure)
        ? VoiceCommandController.permissionDeniedMessage
        : VoiceCommandController.nothingHeardMessage;
    _voice.enqueueSpeech(message);
  }

  /// Deliberately narrow: only phrases that clearly ask for a repeat.
  bool _repeatRequested(String transcript) {
    final String lower = transcript.trim().toLowerCase();
    return lower == 'repeat' ||
        lower == 'repeat that' ||
        lower == 'say that again' ||
        lower == 'repeat please' ||
        lower == 'again please';
  }

  /// Announce a locked-in result at most once per currency.
  void _announceResult(CurrencyRecognition rec) {
    if (!_voiceEnabled) return;
    // Never talk over the user while they are holding the microphone open.
    if (_voiceCommand.isHolding || _voiceCommand.isListening) return;
    if (!_gate.allowsResult(rec)) return;
    _gate.markResult(rec);
    _voice.enqueueSpeech('This appears to be a ${rec.spokenLabel}.');
  }

  void _announceUncertain() {
    if (!_voiceEnabled) return;
    if (_voiceCommand.isHolding || _voiceCommand.isListening) return;
    if (!_gate.allowsUncertain()) return;
    _gate.markUncertain();
    _voice.enqueueSpeech(
      'Currency not detected. Please point the camera at a banknote.',
    );
  }

  void _repeatResult() {
    final CurrencyRecognition? rec = _result;
    if (rec == null) return;
    _voice.enqueueSpeech('${rec.spokenLabel}.');
  }

  // ------------------------------------------------------------
  // INTRO CARD
  // ------------------------------------------------------------

  void _dismissIntroCard() {
    if (!_showIntroCard) return;
    if (!SettingsScope.of(context).animationsEnabled) {
      setState(() => _showIntroCard = false);
      return;
    }
    _introController.reverse().whenComplete(() {
      if (mounted && _showIntroCard) setState(() => _showIntroCard = false);
    });
  }

  void _presentIntroCard() {
    if (_showIntroCard) {
      _introController.forward();
      return;
    }
    setState(() => _showIntroCard = true);
    _introController.forward();
  }

  bool get _sessionActive =>
      _phase == _CurrencyPhase.scanning ||
      _phase == _CurrencyPhase.identified ||
      _phase == _CurrencyPhase.uncertain;

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool compact = size.height < 700;

    return PopScope(
      canPop: !_sessionActive,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop || !mounted || !_sessionActive) return;
        await _stopScan();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFD),
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: PressAndHoldVoiceRegion(
            controller: _voiceCommand,
            enabled: _voiceActivationEnabled,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Column(
                  children: <Widget>[
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
                          children: <Widget>[
                            Expanded(
                              flex: 6,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: <Widget>[
                                    if (_showIntroCard)
                                      ExcludeSemantics(
                                        child: _buildCamera(compact),
                                      )
                                    else
                                      Semantics(
                                        container: true,
                                        label: 'Currency Recognition camera',
                                        child: _buildCamera(compact),
                                      ),
                                    if (_showIntroCard)
                                      _CurrencyIntroCard(
                                        animation: _introController,
                                        ready:
                                            _phase !=
                                            _CurrencyPhase.initializing,
                                        available:
                                            _phase != _CurrencyPhase.error,
                                        busy: _scanInProgress,
                                        onStart: _startScan,
                                        onRetry: _retry,
                                        mode: _mode,
                                        onModeChanged: _setMode,
                                        banknoteAvailable:
                                            _service.hasBanknoteModel,
                                        coinAvailable: _service.hasCoinModel,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 8 : 12),
                            _buildStatusCard(compact),
                            SizedBox(height: compact ? 8 : 12),
                            _buildResultCard(compact),
                            SizedBox(height: compact ? 8 : 12),
                            _buildControls(compact),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Above everything, transparent, purely decorative. The hold
                // gesture that opened it owns the release.
                Positioned.fill(
                  child: VoiceSearchOverlay(controller: _voiceCommand),
                ),
                // Hidden 1x1 speech WebView, only when nothing else hosts it.
                Positioned(
                  left: 0,
                  top: 0,
                  width: 1,
                  height: 1,
                  child: IgnorePointer(child: _speechWebViewHost()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Press-and-hold only makes sense while a camera session is live; on the
  /// idle card the assistant would have nothing to act on.
  bool get _voiceActivationEnabled =>
      _phase == _CurrencyPhase.scanning ||
      _phase == _CurrencyPhase.identified ||
      _phase == _CurrencyPhase.uncertain;

  void _setMode(CurrencyScanMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  /// Host the shared hidden speech WebView unless another screen (Navigate)
  /// already hosts it. Two hosts would fight over the engine's single
  /// controller, so the second one must stay out of the way.
  Widget _speechWebViewHost() {
    // Widget tests set FLUTTER_TEST; the native InAppWebView has no platform
    // channel there, so skip hosting it (the recognizer is unused in tests).
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return const SizedBox.shrink();
    }
    final WebSpeechEngine engine = SpeechCaptureService.instance.webEngine;
    if (engine.isHosted) return const SizedBox.shrink();
    return ClipRect(child: engine.build());
  }

  // ------------------------------------------------------------
  // HEADER
  // ------------------------------------------------------------

  Widget _buildHeader(bool compact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 6 : 10,
        compact ? 6 : 10,
        compact ? 12 : 18,
        4,
      ),
      child: Row(
        children: <Widget>[
          Semantics(
            button: true,
            label: 'Back',
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: const Color(0xFF182230),
              tooltip: 'Back',
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: const Text(
                    'Currency Recognition',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF182230),
                    ),
                  ),
                ),
                const Text(
                  'Identify Indian banknotes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SoundModeButton(),
          const SizedBox(width: 10),
          const SettingsButton(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // CAMERA
  // ------------------------------------------------------------

  Widget _buildCamera(bool compact) {
    return Consumer<CameraService>(
      builder: (BuildContext context, CameraService cameraService, Widget? _) {
        final CameraController? controller = cameraService.controller;
        final bool initialized =
            cameraService.isInitialized && controller != null;
        return Container(
          width: double.infinity,
          color: const Color(0xFF20252B),
          child: initialized
              ? Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CameraPreviewFit(controller: controller),
                    const Positioned.fill(
                      child: CustomPaint(painter: _CurrencyFramePainter()),
                    ),
                    Positioned(top: 14, left: 14, child: _statusPill()),
                    if (!_showIntroCard)
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 14,
                        child: _guideBanner(),
                      ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Color(0xFF64B5F6),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _cameraFailed
                            ? (_cameraService?.errorMessage ?? 'Camera error')
                            : 'Starting camera...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _statusPill() {
    final (IconData, Color, String) data = switch (_phase) {
      _CurrencyPhase.initializing => (
        Icons.hourglass_top_rounded,
        const Color(0xFF4FC3F7),
        'PREPARING',
      ),
      _CurrencyPhase.ready => (
        Icons.check_circle_outline,
        const Color(0xFF4FC3F7),
        'READY',
      ),
      _CurrencyPhase.scanning => (
        _paused ? Icons.pause_circle_outline : Icons.center_focus_strong,
        const Color(0xFF4FC3F7),
        _paused ? 'PAUSED' : 'SCANNING',
      ),
      _CurrencyPhase.identified => (
        Icons.verified_outlined,
        const Color(0xFF66BB6A),
        'IDENTIFIED',
      ),
      _CurrencyPhase.uncertain => (
        Icons.help_outline,
        const Color(0xFFFFB74D),
        'UNSURE',
      ),
      _CurrencyPhase.error => (
        Icons.error_outline,
        const Color(0xFFFF8A80),
        'ERROR',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(data.$1, size: 15, color: data.$2),
          const SizedBox(width: 7),
          Text(
            data.$3,
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

  Widget _guideBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _mode.guidance,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // STATUS CARD
  // ------------------------------------------------------------

  Widget _buildStatusCard(bool compact) {
    final (IconData, Color, Color, String) data = switch (_phase) {
      _CurrencyPhase.initializing => (
        Icons.hourglass_top_rounded,
        const Color(0xFFEFF5FF),
        const Color(0xFF175CD3),
        'Preparing',
      ),
      _CurrencyPhase.ready => (
        Icons.photo_camera_outlined,
        const Color(0xFFEFF5FF),
        const Color(0xFF175CD3),
        'Ready',
      ),
      _CurrencyPhase.scanning => (
        Icons.center_focus_strong,
        const Color(0xFFEFF5FF),
        const Color(0xFF175CD3),
        'Analyzing',
      ),
      _CurrencyPhase.identified => (
        Icons.verified_outlined,
        const Color(0xFFE8F5E9),
        const Color(0xFF198754),
        'Identified',
      ),
      _CurrencyPhase.uncertain => (
        Icons.help_outline,
        const Color(0xFFFFF4E5),
        const Color(0xFFB25E09),
        'Unable to identify clearly',
      ),
      _CurrencyPhase.error => (
        Icons.error_outline,
        const Color(0xFFFDE8E8),
        const Color(0xFFD92D20),
        'Unavailable',
      ),
    };

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: compact ? 40 : 46,
            height: compact ? 40 : 46,
            decoration: BoxDecoration(
              color: data.$2,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(data.$1, color: data.$3, size: compact ? 21 : 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  data.$4,
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
                  _statusDetail,
                  maxLines: 3,
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
  // RESULT CARD
  // ------------------------------------------------------------

  Widget _buildResultCard(bool compact) {
    if (_phase != _CurrencyPhase.identified || _result == null) {
      return const SizedBox.shrink();
    }
    final CurrencyRecognition rec = _result!;
    final String semantic =
        '${rec.displayLabel}. Confidence about ${rec.confidencePercent} percent. '
        'This is an aid, not a guarantee. Verify important amounts another way.';
    return Semantics(
      container: true,
      label: semantic,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 14 : 18),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFB7E0C0)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: compact ? 50 : 58,
              height: compact ? 50 : 58,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                rec.isBanknote
                    ? Icons.payments_outlined
                    : Icons.monetization_on_outlined,
                color: const Color(0xFF198754),
                size: compact ? 26 : 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    rec.displayLabel,
                    style: TextStyle(
                      fontSize: compact ? 20 : 24,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF125C36),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Confidence ${rec.confidencePercent}% • '
                    'Verify important amounts another way.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 11 : 12,
                      color: const Color(0xFF3E6B52),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // CONTROLS
  // ------------------------------------------------------------

  Widget _buildControls(bool compact) {
    final bool showPrimary = _phase != _CurrencyPhase.initializing;
    final bool canRepeat =
        _phase == _CurrencyPhase.identified && _result != null;

    final String primaryLabel;
    final IconData primaryIcon;
    final VoidCallback? primaryAction;
    if (_phase == _CurrencyPhase.error) {
      primaryLabel = _permissionDenied ? 'ALLOW CAMERA & RETRY' : 'RETRY';
      primaryIcon = Icons.refresh_rounded;
      primaryAction = _retry;
    } else if (_phase == _CurrencyPhase.ready) {
      primaryLabel = 'START SCANNING';
      primaryIcon = Icons.camera_alt_outlined;
      primaryAction = _startScan;
    } else if (_phase == _CurrencyPhase.identified ||
        _phase == _CurrencyPhase.uncertain) {
      primaryLabel = 'SCAN AGAIN';
      primaryIcon = Icons.refresh_rounded;
      primaryAction = _scanAgain;
    } else {
      primaryLabel = _paused ? 'RESUME' : 'PAUSE';
      primaryIcon = _paused ? Icons.play_arrow_rounded : Icons.pause_rounded;
      primaryAction = _togglePause;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showPrimary)
          Semantics(
            button: true,
            label: primaryLabel,
            child: SizedBox(
              width: double.infinity,
              height: compact ? 54 : 60,
              child: ElevatedButton.icon(
                onPressed: primaryAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1769E0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: Icon(primaryIcon, size: 22),
                label: Text(
                  primaryLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        if (canRepeat) ...<Widget>[
          SizedBox(height: compact ? 8 : 10),
          Semantics(
            button: true,
            label: 'Repeat result',
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _repeatResult,
                icon: const Icon(Icons.volume_up_outlined, size: 20),
                label: const Text(
                  'REPEAT',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1769E0),
                  backgroundColor: const Color(0xFFEFF5FF),
                  side: const BorderSide(color: Color(0xFFB9D2F7)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Corner brackets marking the framing area for a single banknote.
class _CurrencyFramePainter extends CustomPainter {
  const _CurrencyFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double margin = size.width * 0.12;
    final double inset = size.height * 0.10;
    final double left = margin;
    final double top = inset;
    final double right = size.width - margin;
    final double bottom = size.height - inset;

    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    const double corner = 24.0;
    final Path path = Path()
      ..moveTo(left, top + corner)
      ..lineTo(left, top)
      ..lineTo(left + corner, top)
      ..moveTo(right - corner, top)
      ..lineTo(right, top)
      ..lineTo(right, top + corner)
      ..moveTo(right, bottom - corner)
      ..lineTo(right, bottom)
      ..lineTo(right - corner, bottom)
      ..moveTo(left + corner, bottom)
      ..lineTo(left, bottom)
      ..lineTo(left, bottom - corner);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CurrencyFramePainter oldDelegate) => false;
}

/// Introductory title card shown over the camera rectangle until the user
/// starts a scan. Reuses the design language of the Navigate/Read Text cards.
class _CurrencyIntroCard extends StatelessWidget {
  const _CurrencyIntroCard({
    required this.animation,
    required this.ready,
    required this.available,
    required this.busy,
    required this.onStart,
    required this.mode,
    required this.onModeChanged,
    required this.banknoteAvailable,
    required this.coinAvailable,
    this.onRetry,
  });

  final Animation<double> animation;
  final bool ready;
  final bool available;
  final bool busy;
  final VoidCallback onStart;

  /// What the next scan should look for.
  final CurrencyScanMode mode;
  final ValueChanged<CurrencyScanMode> onModeChanged;

  /// Which models actually loaded, so a mode with no model behind it can be
  /// disabled instead of silently scanning nothing.
  final bool banknoteAvailable;
  final bool coinAvailable;

  /// Retry the model load when neither model is available.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final CurvedAnimation curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Semantics(
      container: true,
      label: 'Currency Recognition. Identify Indian banknotes.',
      child: FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFF0B1424),
                  Color(0xFF14203F),
                  Color(0xFF1B2A5E),
                ],
                stops: <double>[0.0, 0.55, 1.0],
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.30),
                        width: 1.4,
                      ),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[Color(0xFF2E7CF6), Color(0xFF6E5BFF)],
                      ),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Currency Recognition',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    available
                        ? 'Identify Indian banknotes offline, with voice '
                              'feedback.'
                        : 'Recognition model unavailable in this build.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _ModeSelector(
                    mode: mode,
                    onModeChanged: onModeChanged,
                    banknoteAvailable: banknoteAvailable,
                    coinAvailable: coinAvailable,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: !available
                          ? (busy ? null : (onRetry ?? () {}))
                          : ((ready && !busy) ? onStart : null),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1769E0),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF3A4763),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : !available
                          ? const Icon(Icons.refresh_rounded, size: 22)
                          : const Icon(Icons.camera_alt_outlined, size: 22),
                      label: Text(
                        !available
                            ? 'RETRY'
                            : (ready ? 'START SCANNING' : 'PREPARING...'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Which kinds of currency the next scan should analyse.
///
/// A kind whose model did not load is shown but disabled, so the user can see
/// what the app supports instead of discovering it mid-scan. Picking a mode
/// never widens what is claimed: only loaded models contribute results.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.mode,
    required this.onModeChanged,
    required this.banknoteAvailable,
    required this.coinAvailable,
  });

  final CurrencyScanMode mode;
  final ValueChanged<CurrencyScanMode> onModeChanged;
  final bool banknoteAvailable;
  final bool coinAvailable;

  @override
  Widget build(BuildContext context) {
    final bool bothAvailable = banknoteAvailable || coinAvailable;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'Scan for',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<CurrencyScanMode>(
          showSelectedIcon: false,
          selected: <CurrencyScanMode>{mode},
          onSelectionChanged: (Set<CurrencyScanMode> selection) {
            if (selection.isNotEmpty) onModeChanged(selection.first);
          },
          segments: <ButtonSegment<CurrencyScanMode>>[
            ButtonSegment<CurrencyScanMode>(
              value: CurrencyScanMode.both,
              label: const Text('Both'),
              enabled: bothAvailable,
            ),
            ButtonSegment<CurrencyScanMode>(
              value: CurrencyScanMode.banknote,
              label: const Text('Notes'),
              enabled: banknoteAvailable,
            ),
            ButtonSegment<CurrencyScanMode>(
              value: CurrencyScanMode.coin,
              label: const Text('Coins'),
              enabled: coinAvailable,
            ),
          ],
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            backgroundColor: WidgetStateProperty.resolveWith<Color?>(
              (Set<WidgetState> states) => states.contains(WidgetState.selected)
                  ? const Color(0xFF1769E0)
                  : Colors.transparent,
            ),
            foregroundColor: WidgetStateProperty.resolveWith<Color?>(
              (Set<WidgetState> states) => states.contains(WidgetState.selected)
                  ? Colors.white
                  : Colors.white70,
            ),
            side: WidgetStatePropertyAll<BorderSide>(
              BorderSide(color: Colors.white.withValues(alpha: 0.25)),
            ),
            textStyle: const WidgetStatePropertyAll<TextStyle>(
              TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
