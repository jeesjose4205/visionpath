/// High-level state of the Look & Detect assistant.
///
/// Mirrors the Gemini Live-style interaction loop:
/// idle -> listening (awaiting a spoken question) -> processing ("Looking")
/// -> speaking (answer out loud) -> idle; with continuous detection shown as
/// [detecting] and failures surfaced as [error] / [disconnected].
enum LiveAssistantState {
  /// Awaiting input. Microphone is idle.
  idle,

  /// The microphone is capturing the user's question.
  listening,

  /// The camera frame is being analyzed / the answer is being composed.
  processing,

  /// The assistant's answer is playing through the speaker.
  speaking,

  /// Continuous detection is running and watching the environment.
  detecting,

  /// A recoverable failure (camera, microphone, recognition).
  error,

  /// A service is unreachable (e.g. speech recognition not available).
  disconnected,
}