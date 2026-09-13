import '../models/detected_object.dart';
import '../models/object_position.dart';

/// PositionDetectionService assigns each detected object a LEFT / CENTER /
/// RIGHT classification based purely on its normalized horizontal center.
/// This stage is independent of the YOLO model itself.
class PositionDetectionService {
  /// Enrich [objects] with their horizontal positions.
  List<DetectedObject> analyze(List<DetectedObject> objects) {
    final List<DetectedObject> enriched = [];

    for (final obj in objects) {
      final ObjectPosition pos = ObjectPosition.fromCenterX(obj.centerX);
      print('POSITION_ANALYSIS: ${obj.displayName} centerX=${obj.centerX.toStringAsFixed(3)} -> ${pos.label}');
      enriched.add(obj.copyWith(position: pos));
    }

    print('POSITION_ANALYSIS_DONE: ${enriched.length} objects');
    return enriched;
  }
}