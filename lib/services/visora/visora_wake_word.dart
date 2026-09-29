import 'dart:async';

import '../speech_service.dart';
import 'visora_config.dart';

/// Listens for the "Visora" wake word so the assistant can be activated by
/// voice. Uses the same bundled Vosk engine as the rest of the app — fully
/// offline, no network round-trip — so activation works on every device.
///
/// Matching is done on partial transcripts and requires the wake word to
/// appear as a standalone token; a short confirmation requirement reduces
/// accidental activation from unrelated speech.
class VisoraWakeWordDetector {
  final SpeechService _speech = SpeechService();

  bool _running = false;
  bool _matchedRecently = false;
  int _consecutiveHits = 0;

  /// Invoked once when the wake word is recognised.
  void Function()? onWake;

  /// Whether the detector is currently listening.
  bool get isRunning => _running;

  /// Start continuous monitoring. Safe to call when already running.
  Future<bool> start() async {
    if (_running) return true;
    if (!VisoraConfig.instance.wakeWordEnabled) return false;
    if (!await _speech.initialize()) return false;

    _speech.onPartial = _onPartial;
    _speech.onResult = _onPartial;
    _speech.onError = (_) {
      // Silence errors: a single failed frame should not kill the detector.
    };

    final started = await _speech.listen();
    if (started) _running = true;
    return started;
  }

  void _onPartial(String text) {
    if (_matchedRecently) return;
    final tokens = text.toLowerCase().split(RegExp(r'[^a-z]+'));
    if (!tokens.contains('visora')) {
      _consecutiveHits = 0;
      return;
    }
    // Two consecutive transcripts containing the wake word make activation
    // far less likely to fire accidentally.
    _consecutiveHits++;
    if (_consecutiveHits < 2) return;
    _consecutiveHits = 0;
    _matchedRecently = true;
    unawaited(stop());
    onWake?.call();
  }

  /// Pause monitoring (e.g. while the assistant is open).
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _speech.stop();
  }

  /// Fully release the recognizer.
  Future<void> dispose() async {
    await stop();
    _speech.onPartial = null;
    _speech.onResult = null;
    _speech.onError = null;
    await _speech.dispose();
  }
}