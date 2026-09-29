import 'detected_object.dart';
import 'proximity_level.dart';

/// Quality of a depth estimate. Higher quality = more cells contributed to
/// the estimate and a stronger engine signal.
enum DepthQuality { none, low, fair, good }

/// Per-object depth analysis result.
///
/// Distances are RELATIVE unless the metric calibration ran:
///   - [relativeDepth]  -> 0..1, higher = closer to the camera.
///   - [normalizedDepth] -> 0..1, map value for the object (higher = closer).
///   - [estimatedDistance] -> calibrated METERS when the user enabled metric
///     distance and a valid conversion existed; null otherwise. Never a
///     fabricated measurement — relative depth is never passed off as meters.
class DepthResult {
  /// 0..1 nearness (higher = closer). Drives [proximity] classification.
  final double relativeDepth;

  /// 0..1 map value for the object (same orientation as [relativeDepth]).
  final double normalizedDepth;

  /// Relative proximity classification derived from [relativeDepth].
  final ProximityLevel proximity;

  /// Confidence of this estimate (0..1).
  final double confidence;

  /// Physical distance in meters, when a metric calibration produced one.
  /// Null when calibration is disabled or the value is out of range.
  final double? estimatedDistance;

  /// Quality of the depth evidence for this object.
  final DepthQuality depthQuality;

  /// True when produced by the box-area fallback instead of a depth map.
  final bool fromFallback;

  const DepthResult({
    required this.relativeDepth,
    required this.normalizedDepth,
    required this.proximity,
    required this.confidence,
    this.estimatedDistance,
    this.depthQuality = DepthQuality.fair,
    this.fromFallback = false,
  });

  /// Fallback result derived only from bounding-box footprint (legacy path).
  factory DepthResult.boxHeuristic({
    required double relativeDepth,
    required ProximityLevel proximity,
  }) {
    return DepthResult(
      relativeDepth: relativeDepth,
      normalizedDepth: relativeDepth,
      proximity: proximity,
      confidence: 0.2,
      depthQuality: DepthQuality.none,
      fromFallback: true,
    );
  }

  @override
  String toString() =>
      'DepthResult(relativeDepth: $relativeDepth, proximity: ${proximity.label}, confidence: $confidence)';
}

/// A detected object paired with its depth analysis.
class ObjectWithDepth {
  final DetectedObject object;

  final DepthResult depth;

  const ObjectWithDepth({required this.object, required this.depth});
}