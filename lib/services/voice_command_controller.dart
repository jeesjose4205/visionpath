import 'dart:async';

import 'package:flutter/foundation.dart';

import 'visora/visora_session.dart';
import 'voice_service.dart';

/// Why the assistant is not currently able to listen.
enum VoiceCommandFailure {
  /// The microphone was refused or is unavailable.
  permissionDenied,

  /// The finger lifted before anything recognisable was said.
  nothingHeard,
}

/// Owns the press-and-hold voice-command interaction.
///
/// Holding the screen opens the one microphone the app already owns
/// ([VisoraSession.startCapture]) and collects the words; releasing stops it and
/// hands the transcript to the caller. Nothing is answered while the finger is
/// still down, because the sentence is not finished yet.
///
/// Audio safety follows the spec's "safest behaviour": environmental speech that
/// has not started yet is dropped, and a sentence already playing is allowed to
/// finish rather than being cut in half. Either way there is only ever one TTS
/// channel ([VoiceService]), so the microphone and the speaker can never talk
/// over each other.
/// Outcome of trying to open the microphone for a hold.
enum _OpenOutcome {
  /// The recognizer is running.
  opened,

  /// The hold ended before the microphone could open (released, cancelled, or
  /// the screen went away). Nothing should be said about this: the user simply
  /// let go early, and announcing a failure would be wrong and confusing.
  abandoned,

  /// The microphone could not be opened at all.
  unavailable,
}

class VoiceCommandController extends ChangeNotifier {
  /// A hold must last this long before the assistant opens, so an ordinary tap
  /// on the screen never starts the microphone.
  static const Duration holdThreshold = Duration(milliseconds: 350);

  /// Called with the recognized transcript once the user releases the screen.
  void Function(String transcript)? onCommand;

  /// Called when the hold produced nothing usable.
  void Function(VoiceCommandFailure failure)? onFailure;

  /// Shared speech channel, used only to keep the speaker quiet while the
  /// microphone is open.
  final VoiceService _speech;

  VoiceCommandController({VoiceService? speech})
      : _speech = speech ?? VoiceService();

  bool _holding = false;
  bool _listening = false;
  String _transcript = '';
  VoiceCommandFailure? _failure;
  bool _disposed = false;

  /// The user has a finger down: the overlay should be visible.
  bool get isHolding => _holding;

  /// The microphone is genuinely open right now. It stays false while a
  /// sentence is still finishing, so the UI never claims to listen on top of
  /// the app's own voice.
  bool get isListening => _listening;

  /// Whether the assistant surface should be on screen.
  bool get isActive => _holding;

  /// Words recognized so far in this hold (may be empty until release).
  String get transcript => _transcript;

  /// Set when the hold failed, cleared at the start of the next hold.
  VoiceCommandFailure? get failure => _failure;

  /// Begin a hold. Any previous hold is finished first, so a stray second
  /// finger can never open two capture sessions.
  Future<void> beginHold() async {
    if (_disposed) return;
    if (_holding) return;

    _holding = true;
    _listening = false;
    _transcript = '';
    _failure = null;
    _notify();

    // Drop environmental sentences that have not started yet. The one already
    // playing is left alone: cutting a half-spoken hazard warning is worse than
    // waiting for it.
    _speech.clearSpeechQueue();

    final _OpenOutcome outcome = await _openWhenSpeakerIsFree();
    if (_disposed || !_holding) {
      // Released while we were waiting for the speaker.
      if (outcome == _OpenOutcome.opened) {
        await VisoraSession.instance.stopCapture();
      }
      return;
    }
    if (outcome == _OpenOutcome.opened) return;

    _holding = false;
    if (outcome == _OpenOutcome.abandoned) {
      // Let go before we ever listened. Stay silent rather than claiming the
      // microphone is broken.
      _notify();
      return;
    }
    // The engine itself refused to start. Tell the user why, and say "nothing
    // heard" only when the failure was not a permission problem.
    final bool permission = _isPermissionProblem();
    _failure = permission
        ? VoiceCommandFailure.permissionDenied
        : VoiceCommandFailure.nothingHeard;
    _notify();
    onFailure?.call(_failure!);
  }

  /// Whether the last start failure was caused by microphone access rather
  /// than by a broken or busy recognizer.
  bool _isPermissionProblem() {
    final String error = VisoraSession.instance.lastError.toLowerCase();
    return error.contains('permission') || error.contains('microphone');
  }

  /// Wait for the speaker to fall silent, then open the microphone.
  ///
  /// Polls rather than relying on the drain callback because the queue may be
  /// empty already (nothing is speaking) and no callback would ever arrive.
  ///
  /// The microphone must never open while the app is still talking, so if the
  /// speaker somehow never falls silent the hold is abandoned rather than
  /// forced open.
  Future<_OpenOutcome> _openWhenSpeakerIsFree() async {
    const Duration poll = Duration(milliseconds: 100);
    // A long safety valve against a wedged engine, not a shortcut: when it
    // expires the hold is dropped instead of opening over the speaker.
    const int maxTicks = 120;
    for (int i = 0; i < maxTicks; i++) {
      if (_disposed || !_holding) return _OpenOutcome.abandoned;
      if (!_speech.isSpeaking) return _openMicrophone();
      await Future<void>.delayed(poll);
    }
    // Twelve seconds of unbroken speech means something is wedged. Abandon the
    // hold rather than opening the microphone over the speaker.
    return _OpenOutcome.abandoned;
  }

  Future<_OpenOutcome> _openMicrophone() async {
    final bool started = await VisoraSession.instance.startCapture();
    if (!started) return _OpenOutcome.unavailable;
    if (_disposed || !_holding) {
      // The hold ended while the engine was starting.
      await VisoraSession.instance.stopCapture();
      return _OpenOutcome.abandoned;
    }
    _listening = true;
    _startTranscriptMirror();
    _syncTranscript();
    _notify();
    return _OpenOutcome.opened;
  }

  /// End the hold: close the microphone, then act on what was said.
  Future<void> endHold() async {
    if (_disposed || !_holding) return;
    _holding = false;
    _listening = false;
    _notify();

    final String words = await VisoraSession.instance.stopCapture();
    _stopTranscriptMirror();
    if (_disposed) return;

    final String transcript = words.trim();
    _transcript = transcript;

    if (transcript.isEmpty) {
      _failure = VoiceCommandFailure.nothingHeard;
      _notify();
      onFailure?.call(VoiceCommandFailure.nothingHeard);
      return;
    }

    _notify();
    onCommand?.call(transcript);
  }

  /// Abort without acting (screen disposed, navigation stopped).
  Future<void> cancel() async {
    if (!_holding) return;
    _holding = false;
    _listening = false;
    _notify();
    _stopTranscriptMirror();
    await VisoraSession.instance.stopCapture();
  }

  /// Mirrors the session's live partial words so the overlay can show them.
  ///
  /// The session notifies on every partial result, so the words appear as they
  /// are spoken rather than only on release.
  void _syncTranscript() {
    final String partial = VisoraSession.instance.capturedText;
    if (partial == _transcript) return;
    _transcript = partial;
    _notify();
  }

  /// The session changed (a partial result arrived, or capture ended).
  void _onSessionChanged() => _syncTranscript();

  void _startTranscriptMirror() {
    VisoraSession.instance.removeListener(_onSessionChanged);
    VisoraSession.instance.addListener(_onSessionChanged);
  }

  void _stopTranscriptMirror() {
    VisoraSession.instance.removeListener(_onSessionChanged);
  }

  @visibleForTesting
  /// Drive the hold state without a real recognizer, so widget tests can check
  /// that the overlay reacts to it. Production code must never call this.
  void debugSetHoldState({
    bool holding = false,
    bool listening = false,
    String transcript = '',
  }) {
    _holding = holding;
    _listening = listening;
    _transcript = transcript;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _holding = false;
    _listening = false;
    _stopTranscriptMirror();
    unawaited(VisoraSession.instance.stopCapture());
    super.dispose();
  }

  /// The sentence the assistant speaks when the user releases with nothing
  /// recognisable. Shared so the overlay, the controller and the tests agree.
  static const String nothingHeardMessage = "Sorry, I didn't hear that.";

  /// The sentence spoken when the microphone is unavailable.
  static const String permissionDeniedMessage =
      'Microphone permission is required for voice commands.';

  /// True when [failure] is the permission problem.
  static bool isPermissionProblem(VoiceCommandFailure failure) =>
      failure == VoiceCommandFailure.permissionDenied;
}