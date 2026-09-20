/// Anything that can turn the user's speech into text for the assistant.
///
/// GoogleSpeechEngine (system Web Speech / Google) and SpeechService (Vosk,
/// offline) both implement this so the screen can pick a recognizer at
/// runtime and fall back to the offline one when Google is not reachable.
abstract interface class VoiceInput {
  /// Called with partial transcriptions while the user is speaking.
  void Function(String partial)? onPartial;

  /// Called once with the final recognized words.
  void Function(String finalWords)? onResult;

  /// Called when the recognizer reports an error or the listener notices one.
  void Function(String message)? onError;

  bool get isAvailable;

  bool get isListening;

  String get lastError;

  /// Idempotently prepare the engine. Returns whether recognition is ready.
  Future<bool> initialize();

  /// Start listening and recognize the user's question.
  Future<bool> listen();

  /// Stop listening, keeping the current result.
  Future<void> stop();

  /// Cancel listening without producing a result.
  Future<void> cancel();

  /// Release engine resources.
  Future<void> dispose();
}