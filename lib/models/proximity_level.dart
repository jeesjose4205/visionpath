/// Approximate proximity classification for a detected object.
///
/// IMPORTANT: This is an ESTIMATE derived from bounding-box size on a
/// monocular camera feed. It is NOT an exact physical distance measurement.
enum ProximityLevel {
  far('FAR'),
  medium('MEDIUM'),
  near('NEAR'),
  veryNear('VERY_NEAR');

  const ProximityLevel(this.label);

  /// Display label (e.g., "NEAR").
  final String label;

  /// Rank used for prioritization (higher = closer/more urgent).
  int get rank => index;
}