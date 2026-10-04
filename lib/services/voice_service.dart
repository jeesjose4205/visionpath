import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'speech_queue.dart';

/// VoiceService provides optional spoken navigation guidance.
///
/// Routine guidance goes through [enqueueSpeech]: complete sentences are held
/// in a [SpeechQueue] and played strictly one at a time, so a new camera frame
/// can never cut a sentence in half and can never start a second utterance on
/// top of the first. Only [speak] interrupts, and it is reserved for safety
/// warnings, which flush the queue instead of queueing behind it.
///
/// Long-form reading keeps using the native engine queue ([speakAllText]).
///
/// TTS runs fire-and-forget so it never blocks the camera/inference pipeline.
/// All calls are error-guarded so a TTS failure cannot crash the app or stop
/// navigation.
///
/// The engine, the sentence queue and the pump are **static on purpose**. Every
/// screen builds its own VoiceService, and each one used to construct its own
/// FlutterTts, which meant the navigation reader and the assistant could speak
/// over each other. Sharing one engine plus one queue is what makes "one
/// sentence finishes before the next begins" true across the whole app.
class VoiceService {
  static const int _queueFlush = 0;
  static const int _queueAdd = 1;

  /// Generous per-sentence synthesis budget: a stalled engine must not be able
  /// to wedge the queue forever.
  static const int _millisecondsPerChar = 400;
  static const int _queueOverheadMs = 6000;

  // ------------------------------------------------------------------
  // Process-wide speech channel (one engine, one queue, one pump)
  // ------------------------------------------------------------------

  static FlutterTts? _tts;
  static bool _initialized = false;
  static Future<void>? _initializing;
  static bool _speaking = false;

  static int _pendingChunks = 0;
  static bool _queueModeAdd = false;
  static void Function()? _readingDone;
  static Timer? _readingWatchdog;

  /// Waiting routine sentences, in speaking order.
  static final SpeechQueue _speechQueue = SpeechQueue();

  /// Bumped whenever an interrupting utterance takes over, so an in-flight
  /// pump loop notices and abandons its remaining sentences.
  static int _speechGeneration = 0;
  static bool _pumping = false;

  // ------------------------------------------------------------------
  // Per-owner settings
  // ------------------------------------------------------------------

  bool _enabled = false;

  double _speechRate = 0.5;
  double _volume = 1.0;
  String _language = 'en-US';

  /// Invoked when a fire-and-forget [speak] utterance finishes (or is stopped).
  void Function()? onSpeakCompleted;

  /// Invoked when the routine queue finished speaking everything it held and
  /// returned to [SpeechState.idle]. A press-and-hold microphone uses this to
  /// stop hearing the app's own guidance and resume listening exactly once.
  void Function()? onQueueDrained;

  /// Whether voice guidance is enabled.
  bool get enabled => _enabled;

  /// Whether anything is being spoken right now (queue or direct utterance).
  bool get isSpeaking => _speaking || _speechQueue.isSpeaking;

  /// State of the routine speech queue.
  SpeechState get speechState => _speechQueue.state;

  /// Sentences waiting for their turn.
  List<String> get pendingSpeech => _speechQueue.pending;

  /// The sentence being spoken right now, null when the channel is idle.
  /// Exposed so a press-and-hold can tell what the speaker is busy with.
  String? get activeSpeech => _speechQueue.activeSentence;

  /// Whether any routine sentence is still waiting.
  bool get hasPendingSpeech => _speechQueue.hasPending;

  /// Currently configured speech rate (0.0–1.0).
  double get speechRate => _speechRate;

  /// Currently configured volume (0.0–1.0).
  double get volume => _volume;

  /// Currently configured TTS language tag (e.g. `en-US`).
  String get language => _language;

  /// Enable/disable voice guidance.
  void setEnabled(bool value) {
    _enabled = value;
    if (!value) {
      stop();
    }
  }

  /// Configure the speech rate. Applies immediately if the engine is ready
  /// and is applied on (re)initialization otherwise.
  Future<void> setSpeechRate(double value) async {
    _speechRate = value.clamp(0.0, 1.0);
    if (_initialized && _tts != null) {
      try {
        await _tts!.setSpeechRate(_speechRate);
      } catch (e) {
        print('VOICE_SET_RATE_FAILED: $e');
      }
    }
  }

  /// Configure the output volume. Applies immediately if ready.
  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    if (_initialized && _tts != null) {
      try {
        await _tts!.setVolume(_volume);
      } catch (e) {
        print('VOICE_SET_VOLUME_FAILED: $e');
      }
    }
  }

  /// Configure the TTS language tag. Applies immediately if ready.
  Future<void> setLanguage(String languageTag) async {
    _language = languageTag;
    if (_initialized && _tts != null) {
      try {
        await _tts!.setLanguage(_language);
      } catch (e) {
        print('VOICE_SET_LANGUAGE_FAILED: $e');
      }
    }
  }

  /// Lazily initialize the shared TTS engine. Concurrent callers await the same
  /// future, so the engine is built exactly once no matter how many services
  /// ask for it.
  Future<void> _ensureInitialized() {
    if (_initialized) return Future<void>.value();
    final Future<void>? inFlight = _initializing;
    if (inFlight != null) return inFlight;
    final Future<void> future = _initEngine();
    _initializing = future;
    return future;
  }

  Future<void> _initEngine() async {
    try {
      final FlutterTts engine = _tts ??= FlutterTts();
      await engine.awaitSynthCompletion(true);
      await engine.setLanguage(_language);
      await engine.setSpeechRate(_speechRate);
      await engine.setVolume(_volume);
      await engine.setPitch(1.0);
      engine.setErrorHandler((dynamic message) {
        print('VOICE_TTS_ERROR_HANDLER: $message');
        _speaking = false;
      });
      engine.setCompletionHandler(_onUtteranceComplete);
      engine.setCancelHandler(_onUtteranceCancel);
      _initialized = true;
      print('VOICE_INITIALIZED rate=$_speechRate vol=$_volume lang=$_language');
    } catch (e) {
      print('VOICE_INIT_FAILED: $e');
      _initialized = false;
      _tts = null;
    } finally {
      _initializing = null;
    }
  }

  /// Speak [message] immediately, interrupting anything in progress.
  ///
  /// Reserved for guidance that must not wait — safety warnings and the
  /// navigation greeting. Pending routine sentences are dropped so a hazard
  /// warning is never stuck behind a scene description.
  void speak(String message) {
    if (!_enabled) return;
    _speechQueue.clear();
    _speechGeneration++;
    unawaited(_speak(message));
  }

  /// Queue one complete sentence to be spoken after the current one finishes.
  ///
  /// Returns true when the sentence was queued, false when voice is off or the
  /// exact sentence is already waiting (or already being spoken). Callers can
  /// therefore call this on every camera frame: unchanged scenes collapse to
  /// a single queued sentence.
  bool enqueueSpeech(String sentence) {
    if (!_enabled) return false;
    final bool added = _speechQueue.add(sentence);
    if (added) unawaited(_pumpSpeechQueue());
    return added;
  }

  /// Forget every waiting sentence.
  ///
  /// The sentence currently coming out of the speaker is deliberately left
  /// running and still reported as speaking, so a press-and-hold waits for real
  /// silence before opening the microphone instead of talking over it. Use
  /// [stop] to cut speech off immediately.
  void clearSpeechQueue() => _speechQueue.clearPending();

  /// Play queued sentences one at a time, waiting for each to finish.
  ///
  /// `_awaitSynthCompletion` is enabled during initialization, so
  /// `tts.speak()` resolves when synthesis is complete — the next sentence
  /// cannot start early, and no utterance is ever stopped mid-way. The
  /// `_pumping` guard is what prevents two async pumps from running at once,
  /// and the generation check aborts the loop if an interrupting [speak] took
  /// over in the meantime.
  Future<void> _pumpSpeechQueue() async {
    if (_pumping || !_enabled) return;
    _pumping = true;
    final int generation = _speechGeneration;
    try {
      while (_enabled) {
        final String? sentence = _speechQueue.takeNext();
        if (sentence == null) break;
        if (generation != _speechGeneration) {
          _speechQueue.clear();
          break;
        }

        await _ensureInitialized();
        final FlutterTts? tts = _tts;
        if (tts == null) {
          _speechQueue.finishCurrent();
          break;
        }

        print('VOICE_QUEUE_SPEAK: $sentence');
        final Duration budget = Duration(
          milliseconds: (_millisecondsPerChar * sentence.length) +
              _queueOverheadMs,
        );
        try {
          await tts.speak(sentence).timeout(budget);
        } on TimeoutException {
          print('VOICE_QUEUE_TIMEOUT: treated as finished');
        } catch (e) {
          print('VOICE_QUEUE_FAILED: $e');
        }
        _speechQueue.finishCurrent();

        if (generation != _speechGeneration) {
          _speechQueue.clear();
          break;
        }
      }
    } finally {
      _pumping = false;
      // Never leave the queue claiming to be mid-utterance.
      if (_speechQueue.isSpeaking) _speechQueue.finishCurrent();
      // The queue is empty and nothing is being spoken. An always-on listener
      // waits for this before reopening the microphone, so the recognizer never
      // hears its own guidance.
      if (generation == _speechGeneration) _notifyQueueDrained();
    }
  }

  /// Notifies [onQueueDrained] that the queue ran dry without being cancelled.
  void _notifyQueueDrained() {
    if (_speechQueue.state != SpeechState.idle) return;
    print('VOICE_QUEUE_DRAINED');
    onQueueDrained?.call();
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
      onSpeakCompleted?.call();
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
    // Long-form reading owns the engine: drop any queued navigation lines.
    _speechQueue.clear();
    _speechGeneration++;
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

  static void _onUtteranceComplete() {
    if (!_queueModeAdd) return;
    _pendingChunks--;
    if (_pendingChunks <= 0) {
      print('VOICE_READ_DONE: all chunks completed');
      _teardownReading(finalize: true);
    }
  }

  static void _onUtteranceCancel() {
    if (_queueModeAdd) {
      print('VOICE_READ_CANCELLED: engine interrupted reading');
      _teardownReading(finalize: true);
    }
  }

  /// Ends the active reading, restores the flush queue and invokes the
  /// completion callback exactly once. When [finalize] is false the engine is
  /// left alone; with true the watchdog/completion bookkeeping is reset.
  static void _teardownReading({required bool finalize}) {
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

  /// Immediately stop any ongoing speech and drop anything still queued.
  void stop() {
    _speaking = false;
    _speechQueue.clear();
    _speechGeneration++;
    _teardownReading(finalize: true);
    if (_tts == null) return;
    unawaited(_tts!.stop().catchError((dynamic _) {}));
  }

  /// Release this owner's speech state.
  ///
  /// The engine and the sentence queue are shared, so they are deliberately
  /// *not* destroyed here: tearing them down would silence whichever other
  /// screen happens to still be alive. Use [stop] to cut speech off now.
  Future<void> dispose() async {
    _speechQueue.clear();
    _speechGeneration++;
    _readingWatchdog?.cancel();
    _readingWatchdog = null;
    _teardownReading(finalize: true);
    _speaking = false;
  }
}