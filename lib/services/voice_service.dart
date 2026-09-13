import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// VoiceService provides optional spoken navigation guidance.
///
/// TTS runs fire-and-forget so it never blocks the camera/inference pipeline.
/// All calls are error-guarded so a TTS failure cannot crash the app or stop
/// navigation.
class VoiceService {
  static const int _queueFlush = 0;
  static const int _queueAdd = 1;

  FlutterTts? _tts;
  bool _initialized = false;
  bool _enabled = false;
  bool _speaking = false;

  int _pendingChunks = 0;
  bool _queueModeAdd = false;
  void Function()? _readingDone;
  Timer? _readingWatchdog;

  /// Whether voice guidance is enabled.
  bool get enabled => _enabled;

  /// Whether TTS is currently speaking (approximate; re-fires on stop).
  bool get isSpeaking => _speaking;

  /// Enable/disable voice guidance.
  void setEnabled(bool value) {
    _enabled = value;
    if (!value) {
      stop();
    }
  }

  /// Lazily initialize the TTS engine.
  Future<void> _ensureInitialized() async {
    if (_initialized || _tts != null) return;
    try {
      _tts = FlutterTts();
      await _tts!.awaitSynthCompletion(true);
      await _tts!.setLanguage('en-US');
      await _tts!.setSpeechRate(0.5);
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);
      _tts!.setErrorHandler((message) {
        print('VOICE_TTS_ERROR_HANDLER: $message');
        _speaking = false;
      });
      _tts!.setCompletionHandler(_onUtteranceComplete);
      _tts!.setCancelHandler(_onUtteranceCancel);
      _initialized = true;
      print('VOICE_INITIALIZED');
    } catch (e) {
      print('VOICE_INIT_FAILED: $e');
      _initialized = false;
      _tts = null;
    }
  }

  /// Speak [message] without blocking the pipeline.
  void speak(String message) {
    if (!_enabled) return;
    unawaited(_speak(message));
  }

  Future<void> _speak(String message) async {
    if (!_enabled) return;
    await _ensureInitialized();
    if (_tts == null) return;
    _speaking = true;
    try {
      print('VOICE_SPEAK: $message');
      await _tts!.stop();
      await _tts!.speak(message);
    } catch (e) {
      print('VOICE_SPEAK_FAILED: $e');
    } finally {
      _speaking = false;
    }
  }

  /// Speak [message] and wait until synthesis completes (or a generous timeout
  /// elapses so a stalled engine can never hang the reading loop).
  ///
  /// Safe for sequential reading: ongoing audio is stopped before speaking so
  /// chunks can never overlap, and volume/pitch are reasserted on every chunk
  /// so reading stays loud even after a stop().
  /// Returns false when speech could not be started.
  Future<bool> speakWait(String message) async {
    if (!_enabled) return false;
    await _ensureInitialized();
    if (_tts == null) return false;
    _speaking = true;
    try {
      print('VOICE_SPEAK_WAIT: ${message.length} chars');
      await _tts!.stop();
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);
      // focus:true requests audio focus so the reading is audible over media.
      final estimate = Duration(
        milliseconds: (message.length * 260) + 4000,
      );
      await _tts!.speak(message, focus: true).timeout(estimate);
      return true;
    } on TimeoutException {
      // Never let an engine that doesn't report completion stall reading.
      print('VOICE_SPEAK_WAIT_TIMEOUT: treated as done');
      return true;
    } catch (e) {
      print('VOICE_SPEAK_WAIT_FAILED: $e');
      return false;
    } finally {
      _speaking = false;
    }
  }

  /// Speak a list of text chunks in strict sequence, loudly.
  ///
  /// Uses the native engine queue (QUEUE_ADD) so a new chunk can never flush
  /// the previous one. This is the reliable pattern for long-form reading:
  /// `speak()` on Android resolves as soon as the engine accepts the text, so
  /// waiting on it per-chunk and stopping between chunks cancels the audio
  /// before it starts. Here every chunk is handed to the engine up-front and
  /// played in order; completion is reported via [onDone] once the last chunk
  /// finishes (guaranteed — even for engines that never report completion, a
  /// watchdog finishes the reading).
  Future<void> speakAllText(
    List<String> chunks, {
    void Function()? onDone,
  }) async {
    if (!_enabled || chunks.isEmpty) {
      _readingDone = onDone;
      _teardownReading(finalize: true);
      return;
    }
    await _ensureInitialized();
    if (_tts == null) {
      _readingDone = onDone;
      _teardownReading(finalize: true);
      return;
    }
    _teardownReading(finalize: false);
    _speaking = true;
    try {
      await _tts!.stop();
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);
      await _tts!.setQueueMode(_queueAdd);
      _queueModeAdd = true;
      _pendingChunks = chunks.length;
      _readingDone = onDone;

      int totalChars = 0;
      for (final chunk in chunks) {
        totalChars += chunk.length;
        unawaited(_tts!.speak(chunk, focus: true).catchError((dynamic _) => 0));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final estimate = Duration(milliseconds: (totalChars * 260) + 4000);
      _readingWatchdog?.cancel();
      _readingWatchdog = Timer(estimate, () {
        print('VOICE_READ_WATCHDOG: forced finish after $totalChars chars');
        _teardownReading(finalize: true);
      });
      print('VOICE_READ_START: ${chunks.length} chunks');
    } catch (e) {
      print('VOICE_READ_START_FAILED: $e');
      _teardownReading(finalize: true);
    }
  }

  void _onUtteranceComplete() {
    if (!_queueModeAdd) return;
    _pendingChunks--;
    if (_pendingChunks <= 0) {
      print('VOICE_READ_DONE: all chunks completed');
      _teardownReading(finalize: true);
    }
  }

  void _onUtteranceCancel() {
    if (_queueModeAdd) {
      print('VOICE_READ_CANCELLED: engine interrupted reading');
      _teardownReading(finalize: true);
    }
  }

  /// Ends the active reading, restores the flush queue and invokes the
  /// completion callback exactly once. When [finalize] is false the engine is
  /// left alone; with true the watchdog/completion bookkeeping is reset.
  void _teardownReading({required bool finalize}) {
    if (_queueModeAdd) {
      _queueModeAdd = false;
      _pendingChunks = 0;
      _speaking = false;
      unawaited(_tts?.setQueueMode(_queueFlush).catchError((dynamic _) {}));
    }
    if (finalize) {
      _readingWatchdog?.cancel();
      _readingWatchdog = null;
      final cb = _readingDone;
      _readingDone = null;
      try {
        cb?.call();
      } catch (e) {
        print('VOICE_READ_DONE_HANDLER_THREW: $e');
      }
    }
  }

  /// Immediately stop any ongoing speech.
  void stop() {
    _speaking = false;
    _teardownReading(finalize: true);
    if (_tts == null) return;
    unawaited(_tts!.stop().catchError((dynamic _) {}));
  }

  /// Release the TTS engine.
  Future<void> dispose() async {
    _teardownReading(finalize: true);
    if (_tts == null) return;
    try {
      await _tts!.stop();
    } catch (_) {}
    _tts = null;
    _initialized = false;
  }
}