import 'package:flutter/painting.dart';

import '../models/detected_object.dart';
import '../models/proximity_level.dart';

/// DepthAnalysisService provides an APPROXIMATE proximity estimate per object.
///
/// WARNING: A monocular camera cannot measure true physical distance. The
/// estimate is derived only from the normalized bounding-box footprint:
/// a small box => likely far, a large box => likely close, a very large box =>
/// likely very close. Thresholds are heuristic, not calibrated.
class DepthAnalysisService {
  /// Estimate proximity from a normalized bounding box.
  ///
  /// Heuristic thresholds (on normalized [0,1] coordinates):
  /// - width > 0.70 or height > 0.85 -> VERY_NEAR
  /// - area   >= 0.25                -> VERY_NEAR
  /// - area   >= 0.12                -> NEAR
  /// - area   >= 0.05                -> MEDIUM
  /// - otherwise                       -> FAR
  static ProximityLevel estimateProximity(Rect box) {
    final double width = box.width;
    final double height = box.height;
    final double area = width * height;

    if (width > 0.70 || height > 0.85) return ProximityLevel.veryNear;
    if (area >= 0.25) return ProximityLevel.veryNear;
    if (area >= 0.12) return ProximityLevel.near;
    if (area >= 0.05) return ProximityLevel.medium;
    return ProximityLevel.far;
  }

  /// Enrich [objects] with approximate proximity levels.
  List<DetectedObject> analyze(List<DetectedObject> objects) {
    final List<DetectedObject> enriched = [];

    for (final obj in objects) {
      final ProximityLevel level = estimateProximity(obj.boundingBox);
      print('DEPTH_ANALYSIS: ${obj.displayName} area=${(obj.boundingBox.width * obj.boundingBox.height).toStringAsFixed(3)} -> ${level.label} (approximate)');
      enriched.add(obj.copyWith(proximity: level));
    }

    print('DEPTH_ANALYSIS_DONE: ${enriched.length} objects');
    return enriched;
  }
}