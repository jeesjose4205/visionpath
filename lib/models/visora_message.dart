/// A single turn in the Visora assistant conversation.
class VisoraMessage {
  const VisoraMessage({
    required this.role,
    required this.text,
    this.isError = false,
  });

  /// Either 'user' or 'assistant'.
  final String role;

  final String text;

  /// Whether this message represents a failure that should be tinted red.
  final bool isError;

  bool get isUser => role == 'user';
}