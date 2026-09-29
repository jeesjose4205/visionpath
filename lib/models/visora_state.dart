/// High-level state of the Visora voice assistant.
///
/// Mirrors the Gemini Live-style interaction loop described by the Visora
/// spec: idle -> activating (wake-word transition) -> listening ->
/// processing -> speaking -> idle, with explicit stopped/error/closed exits.
enum VisoraState {
  /// Assistant is closed / not shown.
  closed,

  /// Wake-word transition: heading animation + overlay entrance.
  activating,

  /// Overlay is open and ready (greeting shown, suggestions available).
  idle,

  /// The microphone is capturing the user's question.
  listening,

  /// The user's request is being processed by the AI.
  processing,

  /// Visora's answer is playing through the speaker / shown on screen.
  speaking,

  /// User pressed the explicit stop action while listening/processing.
  stopped,

  /// A recoverable failure (AI service, microphone, recognition).
  error,
}