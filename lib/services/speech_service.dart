import 'dart:async';
import 'dart:convert';

import 'package:vosk_flutter/vosk_flutter.dart' as vosk;

import 'voice_input.dart';

/// SpeechService converts the user's spoken question into text using the Vosk
/// offline speech-recognition engine bundled with the app.
///
/// Unlike Android's system recognizer (speech_to_text), Vosk needs no Google
/// services, network or API key, so the microphone works on every device and
/// nothing ever leaves the phone.
///
/// The public surface mirrors the previous system-recognizer API
/// ([initialize], [listen], [stop], [cancel], [onPartial], [onResult],
/// [onError]) so callers are unaffected.
class SpeechService implements VoiceInput {
  StreamSubscription<String>? _partialSub;
  StreamSubscription<String>? _resultSub;

  vosk.SpeechService? _service;
  vosk.Recognizer? _recognizer;
  bool _ready = false;
  bool _listening = false;
  String _lastError = '';

  /// Called with partial transcriptions while the user is speaking.
  void Function(String partial)? onPartial;

  /// Called once with the final recognized words.
  void Function(String finalWords)? onResult;

  /// Called when the recognizer reports an error or the listener notices one.
  void Function(String message)? onError;

  bool get isAvailable => _ready;

  bool get isListening => _listening;

  String get lastError => _lastError;

  /// Idempotently initialize the offline engine and load the bundled model.
  /// Returns whether recognition is ready.
  Future<bool> initialize() async {
    if (_ready) return true;

    try {
      final plugin = vosk.VoskFlutterPlugin.instance();
      final modelPath = await vosk.ModelLoader().loadFromAssets(
        'assets/models/vosk-model-small-en-us-0.15.zip',
      );
      final model = await plugin.createModel(modelPath);
      _recognizer = await plugin.createRecognizer(
        model: model,
        sampleRate: 16000,
      );
      _ready = true;
      print('VOSK_MODEL_READY: $modelPath');
      return true;
    } catch (e) {
      _ready = false;
      _lastError = 'Speech engine initialization failed';
      print('VOSK_INIT_FAILED: $e');
      return false;
    }
  }

  /// Start listening and recognize the user's question.
  ///
  /// Returns true when listening actually started. [onResult] is invoked with
  /// the final transcription; partial results are streamed to [onPartial].
  Future<bool> listen() async {
    if (!await initialize()) {
      _lastError = 'Offline speech engine is not available.';
      onError?.call(_lastError);
      return false;
    }
    if (_listening) return true;

    try {
      final plugin = vosk.VoskFlutterPlugin.instance();
      // The plugin keeps a single native speech service; it is created once
      // and re-started on every subsequent listen.
      final service = _service ?? await plugin.initSpeechService(_recognizer!);
      _service = service;

      _partialSub = service.onPartial().listen((raw) {
        final text = _jsonText(raw);
        if (text.isNotEmpty) {
          onPartial?.call(text);
        }
      });
      _resultSub = service.onResult().listen((raw) {
        final text = _jsonText(raw);
        if (text.isNotEmpty) {
          onResult?.call(text);
        }
      });

      final started = await service.start(
        onRecognitionError: _onVoskErrorStreamError,
      );
      if (started == true) {
        _listening = true;
        _lastError = '';
        return true;
      }
      _lastError = 'Speech recognition could not start.';
      onError?.call(_lastError);
      return false;
    } on vosk.MicrophoneAccessDeniedException {
      _lastError = 'permission_denied';
      onError?.call('permission_denied');
      return false;
    } catch (e) {
      _lastError = 'Speech recognition could not start.';
      onError?.call(_lastError);
      print('VOSK_LISTEN_FAILED: $e');
      return false;
    }
  }

  void _onVoskErrorStreamError(Object error) {
    print('VOSK_ERROR_STREAM: $error');
    _lastError = 'Speech recognition failed.';
    onError?.call(_lastError);
  }

  /// Stop listening, keeping the current result.
  Future<void> stop() async {
    _listening = false;
    try {
      await _service?.stop();
    } catch (e) {
      print('VOSK_STOP_FAILED: $e');
    }
  }

  /// Cancel listening without producing a result.
  Future<void> cancel() async {
    _listening = false;
    try {
      await _service?.cancel();
    } catch (e) {
      print('VOSK_CANCEL_FAILED: $e');
    }
  }

  /// Release recognizer service resources.
  Future<void> dispose() async {
    _listening = false;
    try {
      await _service?.dispose();
    } catch (e) {
      print('VOSK_DISPOSE_FAILED: $e');
    }
    await _partialSub?.cancel();
    await _resultSub?.cancel();
    _partialSub = null;
    _resultSub = null;
    _service = null;
    _recognizer = null;
    _ready = false;
  }

  /// Vosk streams JSON like {"partial": "..."} / {"text": "..."}.
  String _jsonText(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return (decoded['partial'] ?? decoded['text'] ?? '') as String;
      }
    } catch (_) {}
    return '';
  }
}