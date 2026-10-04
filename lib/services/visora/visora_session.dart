import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/visora_message.dart';
import '../../models/visora_state.dart';
import '../speech_service.dart';
import '../target_navigation_service.dart';
import '../voice_service.dart';
import '../web_speech_engine.dart';
import 'visora_config.dart';
import 'visora_llm_client.dart';

/// VisoraSession drives the Visora assistant: the state machine
/// (IDLE/LISTENING/PROCESSING/SPEAKING/IDLE), the conversation context, the
/// microphone, text-to-speech output and the AI backend.
///
/// It mirrors the Gemini-Live style loop used by the rest of VisionPath and is
/// intentionally independent from the camera pipeline so activating Visora
/// never touches object detection, face recognition or navigation.
class VisoraSession extends ChangeNotifier {
  static final VisoraSession instance = VisoraSession._();

  VisoraSession._();

  final SpeechService _vosk = SpeechService();
  final WebSpeechEngine _web = WebSpeechEngine();
  final VoiceService _voice = VoiceService()..setEnabled(true);
  final VisoraLlmClient _llm = VisoraLlmClient();

  VisoraState _state = VisoraState.closed;
  final List<VisoraMessage> _messages = [];

  /// Maximum number of user/assistant messages kept as conversation history.
  /// Kept bounded so request bodies stay reasonable for long sessions.
  static const int _maxHistory = 16;

  /// Monotonic sequence for the newest in-flight request. Only the request
  /// whose sequence still matches [seq] may mutate shared session state —
  /// guarantees one request can never overwrite another's response.
  int _requestSeq = 0;

  /// The request currently streaming; cancelled when a newer request starts.
  VisoraRequestController? _activeRequest;

  String _partialText = '';
  String _lastResponse = '';
  double _voiceEnergy = 0.0;
  String _lastError = '';

  /// Whether the online Web Speech engine is preferred over offline Vosk.
  bool _usingWeb = true;

  /// The recognizer active right now.
  Object? _activeInput;

  /// Whether the microphone reopens by itself after every utterance. Navigation
  /// turns this on so "find a chair" works without touching anything.
  bool _alwaysOn = false;

  /// Bumped whenever always-on listening is (re)started or stopped, so a pump
  /// loop left over from a previous run can never reopen the microphone.
  int _alwaysOnGeneration = 0;

  /// While capturing, recognized words are collected instead of being routed
  /// to the assistant. This is what a press-and-hold needs: the user is still
  /// holding the screen, so the transcript must not be answered yet.
  bool _capturing = false;
  String _capturedText = '';

  bool _disposed = false;
  int _generation = 0;

  VisoraState get state => _state;

  List<VisoraMessage> get messages => List.unmodifiable(_messages);

  String get partialText => _partialText;

  String get lastResponse => _lastResponse;

  /// 0..1 audio energy used to drive the waveform bars while listening.
  double get voiceEnergy => _voiceEnergy;

  String get lastError => _lastError;

  /// Whether a backend is configured (otherwise offline answers are used).
  bool get hasBackend => VisoraConfig.instance.hasBackend;

  /// The online Google Web Speech engine. Must be hosted somewhere in the
  /// widget tree (hidden WebView) and started once, or its [initialize]
  /// cannot report ready.
  WebSpeechEngine get webEngine => _web;

  /// Whether the microphone is currently reopening itself after each utterance.
  bool get alwaysOnListening => _alwaysOn;

  /// Reset to a fresh session when the assistant is opened.
  void open() {
    _generation++;
    _requestSeq++;
    _activeRequest?.cancel();
    _activeRequest = null;
    _messages.clear();
    _partialText = '';
    _lastError = '';
    _lastResponse = '';
    _state = VisoraState.idle;
    notifyListeners();
  }

  void _setState(VisoraState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // LISTENING (microphone input)
  // ------------------------------------------------------------------

  /// Begin listening for the user's question. Interrupts any ongoing speech
  /// and immediately captures the new request (barge-in behaviour).
  Future<void> startListening() async {
    // Barge-in: if Visora is speaking, stop it right now.
    if (_state == VisoraState.speaking) {
      _voice.stop();
    }
    if (_disposed) return;

    _setState(VisoraState.listening);
    _partialText = '';

    final candidates = _usingWeb
        ? <Object>[_web, _vosk]
        : <Object>[_vosk];

    for (final input in candidates) {
      if (_state != VisoraState.listening) return;
      final ok = await _initInput(input);
      if (!ok || _state != VisoraState.listening) {
        if (identical(input, _web)) {
          _usingWeb = false;
          continue;
        }
        _onListenError(_vosk.lastError);
        return;
      }
      _activeInput = input;
      if (identical(input, _web)) _usingWeb = true;
      _bindInput(input, wakeMode: false);

      final started = await _listenOn(input);
      if (started) return;
      if (identical(input, _web)) {
        _usingWeb = false;
        continue;
      }
      _onListenError(_vosk.lastError);
      return;
    }
  }

  Future<bool> _initInput(Object input) async {
    if (input is SpeechService) return _vosk.initialize();
    if (input is WebSpeechEngine) return _web.initialize();
    return false;
  }

  Future<bool> _listenOn(Object input) async {
    if (input is SpeechService) {
      return _vosk.listen();
    }
    if (input is WebSpeechEngine) {
      return _web.listen();
    }
    return false;
  }

  void _onListenError(String message) {
    _lastError = message;
    if (message.toLowerCase().contains('permission')) {
      _lastError = 'Microphone access is needed to talk with Visora.';
    }
    _setState(VisoraState.error);
  }

  void _bindInput(Object input, {required bool wakeMode}) {
    void onPartial(String text) {
      if (wakeMode || _state != VisoraState.listening) return;
      _partialText = text;
      // Drive the waveform from partial-recognition activity: any transcript
      // growth raises the energy briefly.
      _voiceEnergy = (_voiceEnergy * 0.4) + (0.6 * _energyFrom(text));
      notifyListeners();
    }

    void onResult(String text) {
      if (wakeMode) return;
      if (_capturing) {
        // Collect the words; the owner decides what to do when the user lets
        // go of the screen.
        _capturedText = text;
        notifyListeners();
        return;
      }
      unawaited(_onUserSpeech(text));
    }

    void onError(String message) {
      if (wakeMode) return;
      if (message.contains('timeout') || message.contains('silence')) {
        // No speech detected — return to idle quietly.
        if (_state == VisoraState.listening) _setState(VisoraState.idle);
        return;
      }
      _onListenError(message);
    }

    if (input is SpeechService) {
      _vosk.onPartial = onPartial;
      _vosk.onResult = onResult;
      _vosk.onError = onError;
    } else if (input is WebSpeechEngine) {
      _web.onPartial = onPartial;
      _web.onResult = onResult;
      _web.onError = onError;
    }
  }

  /// Recognized (or typed) user request routed through the assistant.
  Future<void> _onUserSpeech(String text) async {
    final query = text.trim();
    if (query.isEmpty) {
      if (_state == VisoraState.listening) _setState(VisoraState.idle);
      return;
    }
    await handleUserMessage(query);
  }

  /// Stop listening, optionally submitting whatever was captured.
  Future<void> stopListening() async {
    _voiceEnergy = 0.0;
    await _stopInputs();
    if (_state == VisoraState.listening) _setState(VisoraState.idle);
  }

  Future<void> _stopInputs() async {
    final active = _activeInput;
    _activeInput = null;
    if (active is SpeechService) {
      await _vosk.stop();
    } else if (active is WebSpeechEngine) {
      await _web.stop();
    }
  }

// ------------------------------------------------------------------
// PRESS-AND-HOLD CAPTURE
// ------------------------------------------------------------------

/// Whether the microphone is collecting words for the owner instead of
/// answering them.
bool get isCapturing => _capturing;

/// Words recognized during the current capture.
String get capturedText => _capturedText;

/// Open the microphone and collect what the user says without acting on it.
///
/// Uses the same recognizer as everything else in the app, so there is still
/// exactly one speech-recognition session. Returns whether listening actually
/// started; false means the caller should report the failure.
Future<bool> startCapture() async {
  if (_disposed || _capturing) return _capturing;
  _capturing = true;
  _capturedText = '';
  notifyListeners();
  await startListening();
  // A failed start leaves the session in the error state; do not pretend to be
  // listening, and let the owner speak the right message.
  if (_state == VisoraState.error) {
    _capturing = false;
    notifyListeners();
    return false;
  }
  return true;
}

/// Close the microphone and return the collected words.
Future<String> stopCapture() async {
  final String text = _capturedText;
  _capturing = false;
  _capturedText = '';
  if (_alwaysOn) {
    // Press-and-hold owns the microphone now; a background listener must not
    // grab it back the moment the finger lifts.
    _alwaysOn = false;
    _alwaysOnGeneration++;
  }
  await _stopInputs();
  if (_state == VisoraState.listening) _setState(VisoraState.idle);
  notifyListeners();
  return text;
}

// ------------------------------------------------------------------
// ALWAYS-ON LISTENING
// ------------------------------------------------------------------
  //
  // While Navigation is running the microphone reopens by itself after every
  // utterance, so a target can be asked for out loud without pressing anything.
  // The recognizer deliberately stays shut while the app is speaking: a live
  // mic would otherwise transcribe the app's own guidance.

  /// Polling interval used while waiting for speech to finish.
  static const Duration _alwaysOnPoll = Duration(milliseconds: 120);

  /// Pause after an utterance before reopening the microphone, so the tail of
  /// the previous phrase is not captured as a new one.
  static const Duration _alwaysOnGap = Duration(milliseconds: 300);

  /// Open the microphone and keep it open. Safe to call when already on.
  void startAlwaysOnListening() {
    if (_disposed || _alwaysOn) return;
    _alwaysOn = true;
    unawaited(_pumpAlwaysOn());
    print('ALWAYSON_START');
  }

  /// Close the microphone and stop reopening it.
  Future<void> stopAlwaysOnListening() async {
    if (!_alwaysOn) return;
    _alwaysOn = false;
    _alwaysOnGeneration++;
    await _stopInputs();
    print('ALWAYSON_STOP');
  }

  Future<void> _pumpAlwaysOn() async {
    final int gen = ++_alwaysOnGeneration;
    while (_alwaysOn && gen == _alwaysOnGeneration && !_disposed) {
      // Never listen on top of the app's own voice.
      if (_voice.isSpeaking) {
        await Future<void>.delayed(_alwaysOnPoll);
        continue;
      }
      // Yield to button-driven listening and to an in-flight assistant answer.
      if (_activeInput != null || _state != VisoraState.idle) {
        await Future<void>.delayed(_alwaysOnPoll);
        continue;
      }

      await startListening();

      // A failed start (no permission, engine error) would otherwise spin this
      // loop forever, so the first hard error ends always-on listening.
      if (_state == VisoraState.error) {
        _alwaysOn = false;
        print('ALWAYSON_ABORT: ${_lastError}');
        return;
      }

      while (_alwaysOn &&
          gen == _alwaysOnGeneration &&
          _state == VisoraState.listening) {
        await Future<void>.delayed(_alwaysOnPoll);
      }

      if (!_alwaysOn || gen != _alwaysOnGeneration || _disposed) return;
      await Future<void>.delayed(_alwaysOnGap);
    }
  }

  // ------------------------------------------------------------------
  // TYPED TEXT INPUT (suggestions, retries, camera questions)
  // ------------------------------------------------------------------

  /// Submit a typed/tapped question.
  Future<void> handleUserMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || _disposed) return;

    await _stopInputs();
    _voiceEnergy = 0.0;
    _partialText = '';

    // "Stop." / "Cancel." end an active target search first. Only when nothing is
    // being tracked do they act as the assistant's ordinary barge-in word, so
    // they never start a target search by themselves.
    final lower = query.toLowerCase();
    final bool targetActive = TargetNavigationService.instance.isActive;
    if (!targetActive &&
        (lower == 'stop' ||
            lower == 'cancel' ||
            lower.contains('shut up') ||
            lower == 'nevermind')) {
      _voice.stop();
      _setState(VisoraState.idle);
      return;
    }

    // Target Object Navigation ("find a chair", "stop searching") is a device
    // command, not a question for the model: it drives the live camera
    // pipeline, so it is handled here — before the message is sent to the LLM
    // — and the Navigation screen speaks the answer.
    if (TargetNavigationService.instance.handleCommand(query)) {
      _lastResponse = '';
      _setState(VisoraState.idle);
      return;
    }

    _messages.add(VisoraMessage(role: 'user', text: query));
    notifyListeners();
    await _processRequest(query);
  }

  // ------------------------------------------------------------------
  // PROCESSING + RESPONSE
  // ------------------------------------------------------------------

  Future<void> _processRequest(String query) async {
    // Any newer request cancels the currently streaming one so the two can
    // never race on shared state or the response buffer.
    final superseded = _activeRequest;
    _activeRequest = null;
    superseded?.cancel();

    final seq = ++_requestSeq;
    _setState(VisoraState.processing);
    // Brief visual acknowledgement so the UI updates instantly.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (_disposed || _state != VisoraState.processing) return;
    if (seq != _requestSeq) return;

    // Keep the conversation healthy: drop any stale error messages that a
    // previous failed request may have left behind, and trim history so only
    // recent turns are sent to the AI.
    clearConversationErrors();
    _trimHistory(notify: false);

    final hist = <Map<String, String>>[
      {
        'role': 'system',
        'content':
            'You are Visora, a calm, helpful and accessible AI voice '
            'assistant built into the VisionPath AI app for people with visual '
            'impairments. Answer clearly, conversationally and concisely.',
      },
      for (final m in _messages)
        {'role': m.role, 'content': m.text},
    ];

    _debugLog(
      'Visora REQUEST START id=$seq conversation-count=${_messages.length} '
      'user="${_preview(query)}"',
    );

    // Fresh per-request controller + local buffer (reset for every request).
    final controller = VisoraRequestController();
    _activeRequest = controller;
    final buffer = StringBuffer();
    double energy = 0.0;

    final answer = await _llm.generate(
      hist,
      onDelta: (delta) {
        if (seq != _requestSeq || controller.isCancelled) return;
        buffer.write(delta);
        _lastResponse = buffer.toString().trim();
        energy = (energy * 0.3) + (0.7 * _energyFrom(delta));
        _voiceEnergy = energy;
        notifyListeners();
      },
      controller: controller,
    );

    // A superseded/cancelled request must not touch any state afterwards.
    if (_disposed) return;
    if (seq != _requestSeq || controller.isCancelled) return;
    if (identical(_activeRequest, controller)) _activeRequest = null;

    _voiceEnergy = 0.0;

    final text = answer.text.trim();

    // A failed (or empty) request is shown and spoken to the user but is
    // NEVER stored as an assistant message — error messages must not make it
    // into the conversation history sent back to the LLM.
    if (answer.isError || text.isEmpty) {
      _lastError = text.isEmpty
          ? 'Visora could not produce an answer. Please try again.'
          : answer.text;
      _setState(VisoraState.error);
      if (VisoraConfig.instance.voiceOutputEnabled) {
        _voice.speak(_lastError);
      }
      return;
    }

    // Success (live or offline): only now does the response become a real
    // assistant turn in the conversation.
    _messages.add(VisoraMessage(role: 'assistant', text: text));
    _lastResponse = text;
    notifyListeners();
    _trimHistory(notify: false);

    // Spoken output unless muted or disabled.
    if (VisoraConfig.instance.voiceOutputEnabled) {
      _setState(VisoraState.speaking);
      _voice.speak(text);
      // Stay in speaking state while audio plays, then relax to idle.
      await Future<void>.delayed(
        Duration(milliseconds: (text.length * 60).clamp(800, 20000)),
      );
      if (_disposed || seq != _requestSeq) return;
      if (_state == VisoraState.speaking) _setState(VisoraState.idle);
    } else {
      _setState(VisoraState.idle);
    }
  }

  /// Remove any assistant error messages recorded earlier in this session so a
  /// failed request can never leak into the LLM conversation.
  void clearConversationErrors() {
    if (!_messages.any((m) => m.isError)) return;
    _messages.removeWhere((m) => m.isError);
    notifyListeners();
  }

  /// Cap the conversation to [_maxHistory] recent turns (oldest dropped).
  void _trimHistory({bool notify = true}) {
    if (_messages.length <= _maxHistory) return;
    _messages.removeRange(0, _messages.length - _maxHistory);
    if (notify) notifyListeners();
  }

  /// Return to idle (e.g. TTS completion callback).
  void onSpeechDone() {
    if (_disposed) return;
    if (_state == VisoraState.speaking) _setState(VisoraState.idle);
  }

  /// Stop only the current spoken answer and relax back to idle.
  void stopSpeaking() {
    if (_state != VisoraState.speaking) return;
    _voice.stop();
    _setState(VisoraState.idle);
  }

  /// Re-play the latest answer with the device voice.
  void replayAnswer() {
    if (_lastResponse.isEmpty || _disposed) return;
    if (!VisoraConfig.instance.voiceOutputEnabled) return;
    _setState(VisoraState.speaking);
    _voice.speak(_lastResponse);
    final gen = _generation;
    Future<void>.delayed(
      Duration(milliseconds: (_lastResponse.length * 60).clamp(800, 20000)),
    ).then((_) {
      if (_disposed || gen != _generation) return;
      if (_state == VisoraState.speaking) _setState(VisoraState.idle);
    });
  }

  double _energyFrom(String text) {
    if (text.isEmpty) return 0.15;
    final energy = text.length * 0.14;
    return (energy < 0.2 ? 0.2 : (energy > 0.9 ? 0.9 : energy)).toDouble();
  }

  /// Log to the console only in DEBUG builds; never logs the API key.
  void _debugLog(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(message);
    }
  }

  String _preview(String s) {
    if (s.length <= 120) return s;
    return '${s.substring(0, 120)}… (${s.length} chars)';
  }

  // ------------------------------------------------------------------
  // INTERRUPTION + CLOSE
  // ------------------------------------------------------------------

  /// User-initiated stop: silence audio and microphone, show stopped state.
  Future<void> interrupt() async {
    _requestSeq++;
    final active = _activeRequest;
    _activeRequest = null;
    active?.cancel();
    _voice.stop();
    _voiceEnergy = 0.0;
    await _stopInputs();
    if (_state == VisoraState.speaking ||
        _state == VisoraState.listening ||
        _state == VisoraState.processing ||
        _state == VisoraState.error) {
      _setState(VisoraState.stopped);
      // Briefly reflect the stopped state, then return to idle.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!_disposed && _state == VisoraState.stopped) {
        _setState(VisoraState.idle);
      }
    }
  }

  /// Speak a greeting when the assistant opens.
  void speakGreeting() {
    if (!VisoraConfig.instance.voiceOutputEnabled) return;
    _voice.speak('Hello! I am Visora, your AI assistant.');
  }

  /// Close the assistant: stop everything and release resources.
  Future<void> close() async {
    _generation++;
    _requestSeq++;
    final active = _activeRequest;
    _activeRequest = null;
    active?.cancel();
    _voiceEnergy = 0.0;
    _voice.stop();
    await _stopInputs();
    _setState(VisoraState.closed);
  }

  Future<void> disposeSession() async {
    _disposed = true;
    _alwaysOn = false;
    _alwaysOnGeneration++;
    _generation++;
    _requestSeq++;
    final active = _activeRequest;
    _activeRequest = null;
    active?.cancel();
    _voiceEnergy = 0.0;
    _voice.stop();
    await _stopInputs();
    _vosk.onPartial = null;
    _vosk.onResult = null;
    _vosk.onError = null;
    _web.onPartial = null;
    _web.onResult = null;
    _web.onError = null;
    unawaited(_vosk.dispose());
    unawaited(_web.dispose());
    unawaited(_voice.dispose());
    super.dispose();
  }
}