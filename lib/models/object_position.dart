/// Horizontal position of a detected object relative to the camera view.
enum ObjectPosition {
  left('LEFT'),
  center('CENTER'),
  right('RIGHT');

  const ObjectPosition(this.label);

  /// Display label (e.g., "LEFT").
  final String label;

  /// Determine the position from a normalized center X coordinate (0.0-1.0).
  ///
  /// LEFT:   centerX < 0.33
  /// CENTER: 0.33 <= centerX <= 0.66
  /// RIGHT:  centerX > 0.66
  static ObjectPosition fromCenterX(double centerX) {
    if (centerX < 0.33) return ObjectPosition.left;
    if (centerX > 0.66) return ObjectPosition.right;
    return ObjectPosition.center;
  }
}