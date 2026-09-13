import 'package:flutter/material.dart';

import 'object_position.dart';
import 'proximity_level.dart';

/// DetectedObject represents an object detected by YOLO inference.
///
/// All box coordinates are normalized to the [0.0, 1.0] range so the model is
/// not tied to screen pixel dimensions.
class DetectedObject {
  /// The class label (e.g., "person", "chair", "car")
  final String className;

  /// Confidence score between 0.0 and 1.0
  final double confidence;

  /// Bounding box coordinates in normalized [0.0, 1.0] space
  final Rect boundingBox;

  /// Horizontal position relative to the camera view (assigned by the
  /// position analysis stage). Null before that stage runs.
  final ObjectPosition? position;

  /// Approximate proximity estimate (assigned by the depth analysis stage).
  /// Null before that stage runs.
  final ProximityLevel? proximity;

  /// Center X coordinate (normalized)
  final double centerX;

  /// Center Y coordinate (normalized)
  final double centerY;

  DetectedObject({
    required this.className,
    required this.confidence,
    required this.boundingBox,
    this.position,
    this.proximity,
  }) : centerX = (boundingBox.left + boundingBox.right) / 2,
       centerY = (boundingBox.top + boundingBox.bottom) / 2;

  /// Create a copy with overridden derived-analysis fields.
  DetectedObject copyWith({
    ObjectPosition? position,
    ProximityLevel? proximity,
  }) {
    return DetectedObject(
      className: className,
      confidence: confidence,
      boundingBox: boundingBox,
      position: position ?? this.position,
      proximity: proximity ?? this.proximity,
    );
  }

  /// Get horizontal position category as a string (legacy helper).
  String get horizontalPosition =>
      (position ?? ObjectPosition.fromCenterX(centerX)).label;

  /// Get capitalized display name (e.g., "person" → "Person")
  String get displayName {
    if (className.isEmpty) return className;
    return className[0].toUpperCase() + className.substring(1);
  }

  /// Get a user-facing phrase with position, e.g., "Person ahead".
  String get userFacingMessage {
    final ObjectPosition pos = position ?? ObjectPosition.fromCenterX(centerX);
    final String positionText = switch (pos) {
      ObjectPosition.center => 'ahead',
      ObjectPosition.left => 'on your left',
      ObjectPosition.right => 'on your right',
    };
    return '$displayName $positionText';
  }

  @override
  String toString() {
    return 'DetectedObject(className: $className, confidence: ${confidence * 100}%, box: $boundingBox, position: ${position?.label ?? horizontalPosition}, proximity: ${proximity?.label ?? 'N/A'})';
  }
}