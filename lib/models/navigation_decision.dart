/// Navigation decision produced by the decision engine.
///
/// The system never guarantees that an environment is safe; decisions indicate
/// what the path "appears" to allow.
enum NavigationDecision {
  forward('FORWARD'),
  left('LEFT'),
  right('RIGHT'),
  slow('SLOW'),
  stop('STOP');

  const NavigationDecision(this.label);

  /// Display label (e.g., "FORWARD").
  final String label;
}