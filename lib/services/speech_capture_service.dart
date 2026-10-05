import 'package:flutter/foundation.dart';

import 'speech_service.dart';
import 'web_speech_engine.dart';

/// Owns the app's single speech-recognition session for press-and-hold voice
/// commands.
///
/// Recognition is deliberately "open the microphone, collect words, hand them
/// to the owner on release": the sentence is not finished while the finger is
/// still down, so nothing is answered until the caller asks. The same recognizer
/// is reused for every command in the app, so there is never more than one
/// speech-recognition session competing for the microphone.
class SpeechCaptureService extends ChangeNotifier {
  static final SpeechCaptureService instance = SpeechCaptureService._();

  SpeechCaptureService._();

  final SpeechService _offline = SpeechService();
  final WebSpeechEngine _web = WebSpeechEngine();

  /// Whether the online Web Speech engine is preferred over offline Vosk.
  bool _preferWeb = true;

  /// The recognizer active right now.
  Object? _activeInput;

  bool _capturing = false;
  String _capturedText = '';
  String _lastError = '';

  /// The online Google Web Speech engine. Must be hosted somewhere in the
  /// widget tree (hidden WebView) and started once, or its [initialize] cannot
  /// report ready.
  WebSpeechEngine get webEngine => _web;

  /// Whether the microphone is collecting words for the owner.
  bool get isCapturing => _capturing;

  /// Words recognized during the current capture.
  String get capturedText => _capturedText;

  /// The most recent recognizer error, empty when the last attempt was fine.
  String get lastError => _lastError;

  /// Open the microphone and collect what the user says without acting on it.
  ///
  /// Returns whether listening actually started; false means the caller should
  /// report the failure and can read [lastError] to tell a permission problem
  /// apart from a busy or broken engine.
  Future<bool> startCapture() async {
    if (_capturing) return true;
    _capturing = true;
    _capturedText = '';
    _lastError = '';
    notifyListeners();

    final candidates =
        _preferWeb ? <Object>[_web, _offline] : <Object>[_offline];
    for (final input in candidates) {
      if (!_capturing) break;
      final bool ready = await _initInput(input);
      if (!ready || !_capturing) {
        if (identical(input, _web)) {
          // The web engine is unusable on this device; never try it again.
          _preferWeb = false;
          continue;
        }
        _captureFailed(_offline.lastError);
        return false;
      }
      _activeInput = input;
      if (identical(input, _web)) _preferWeb = true;
      _bindInput(input);

      final bool started = await _listenOn(input);
      if (started) return true;
      if (identical(input, _web)) {
        _preferWeb = false;
        continue;
      }
      _captureFailed(_offline.lastError);
      return false;
    }

    _captureFailed(_lastError);
    return false;
  }

  /// Close the microphone and return the collected words.
  Future<String> stopCapture() async {
    final String text = _capturedText;
    _capturing = false;
    _capturedText = '';
    await _stopInput();
    notifyListeners();
    return text;
  }

  /// Abort a capture, discarding whatever was recognized.
  Future<void> cancelCapture() async {
    if (!_capturing && _activeInput == null) return;
    _capturing = false;
    _capturedText = '';
    final active = _activeInput;
    _activeInput = null;
    if (active is SpeechService) {
      await _offline.cancel();
    } else if (active is WebSpeechEngine) {
      await _web.cancel();
    }
    notifyListeners();
  }

  Future<bool> _initInput(Object input) async {
    if (input is SpeechService) return _offline.initialize();
    if (input is WebSpeechEngine) return _web.initialize();
    return false;
  }

  Future<bool> _listenOn(Object input) async {
    if (input is SpeechService) return _offline.listen();
    if (input is WebSpeechEngine) return _web.listen();
    return false;
  }

  void _captureFailed(String message) {
    _capturing = false;
    _lastError = message;
    notifyListeners();
  }

  /// Recognized words are collected, never answered: the owner decides what to
  /// do when the user lets go of the screen.
  void _bindInput(Object input) {
    void onPartial(String text) {
      if (!_capturing) return;
      _capturedText = text;
      notifyListeners();
    }

    void onResult(String text) {
      if (!_capturing) return;
      _capturedText = text;
      notifyListeners();
    }

    void onError(String message) {
      if (!_capturing) return;
      if (message.contains('timeout') || message.contains('silence')) {
        // Nothing was said. Stay silent about it; the caller decides what an
        // empty transcript means.
        return;
      }
      _lastError = message;
    }

    if (input is SpeechService) {
      _offline
        ..onPartial = onPartial
        ..onResult = onResult
        ..onError = onError;
    } else if (input is WebSpeechEngine) {
      _web
        ..onPartial = onPartial
        ..onResult = onResult
        ..onError = onError;
    }
  }

  Future<void> _stopInput() async {
    final active = _activeInput;
    _activeInput = null;
    if (active is SpeechService) {
      await _offline.stop();
    } else if (active is WebSpeechEngine) {
      await _web.stop();
    }
  }
}