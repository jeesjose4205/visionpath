import 'package:flutter/painting.dart';

import '../models/app_settings.dart';
import '../models/detected_object.dart';
import '../models/proximity_level.dart';
import 'settings_service.dart';

/// DepthAnalysisService provides an APPROXIMATE proximity estimate per object.
///
/// WARNING: A monocular camera cannot measure true physical distance. The
/// estimate is derived only from the normalized bounding-box footprint:
/// a small box => likely far, a large box => likely close, a very large box =>
/// likely very close. Thresholds are heuristic, not calibrated.
class DepthAnalysisService {
  static double _sensitivityScale(ObstacleSensitivity s) {
    switch (s) {
      case ObstacleSensitivity.low:
        return 1.25;
      case ObstacleSensitivity.medium:
        return 1.0;
      case ObstacleSensitivity.high:
        return 0.8;
    }
  }

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

    // "Obstacle Warning Sensitivity" shifts how readily an object is reported
    // as close: Low requires larger boxes, High flags boxes sooner. This tunes
    // warning sensitivity only — never a safety guarantee.
    final double s = _sensitivityScale(
      SettingsService.instance.obstacleSensitivity,
    );

    if (width > 0.70 * s || height > 0.85 * s) return ProximityLevel.veryNear;
    if (area >= 0.25 * s) return ProximityLevel.veryNear;
    if (area >= 0.12 * s) return ProximityLevel.near;
    if (area >= 0.05 * s) return ProximityLevel.medium;
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