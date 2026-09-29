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

  /// Estimated distance in METERS (assigned by the calibrated depth stage).
  ///
  /// Always null until a calibrated metric conversion has run: the system
  /// never fabricates meters from relative depth alone. Owned by this single
  /// detection — every box gets its own independently measured value.
  final double? distanceMeters;

  /// Confidence of the distance estimate (0..1). Low values mean the number
  /// should be presented as approximate.
  final double? distanceConfidence;

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
    this.distanceMeters,
    this.distanceConfidence,
  }) : centerX = (boundingBox.left + boundingBox.right) / 2,
       centerY = (boundingBox.top + boundingBox.bottom) / 2;

  /// Create a copy with overridden derived-analysis fields.
  DetectedObject copyWith({
    ObjectPosition? position,
    ProximityLevel? proximity,
    double? distanceMeters,
    double? distanceConfidence,
  }) {
    return DetectedObject(
      className: className,
      confidence: confidence,
      boundingBox: boundingBox,
      position: position ?? this.position,
      proximity: proximity ?? this.proximity,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      distanceConfidence: distanceConfidence ?? this.distanceConfidence,
    );
  }

  /// True when this detection carries a valid metric estimate.
  bool get hasDistance => distanceMeters != null;

  /// True when the distance estimate is low-confidence and must be presented
  /// as approximate rather than precise.
  bool get distanceLowConfidence =>
      distanceConfidence != null && distanceConfidence! < 0.35;

  /// "2.4 m" style plain value, or null when no metric estimate exists.
  /// No approximation marker: used for spoken announcements as-is.
  String? get distanceValueText {
    final double? d = distanceMeters;
    if (d == null) return null;
    return '${formatDistanceMeters(d)} m';
  }

  /// "≈ 2.4 m" style value for on-screen labels, or null when no metric
  /// estimate exists. Approximated prefix is added for low-confidence reads.
  String? get distanceLabel {
    final String? value = distanceValueText;
    if (value == null) return null;
    return distanceLowConfidence ? '≈ $value' : value;
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
    final String distance = distanceMeters == null
        ? 'N/A'
        : '${formatDistanceMeters(distanceMeters!)} m';
    return 'DetectedObject(className: $className, confidence: ${confidence * 100}%, box: $boundingBox, position: ${position?.label ?? horizontalPosition}, proximity: ${proximity?.label ?? 'N/A'}, distance: $distance)';
  }
}

/// Format a metric distance in meters for human-readable display.
///
/// - >= 10 m      -> whole meters ("12 m")
/// - >= 1 m       -> one decimal ("2.4 m")
/// - >= 0.5 m     -> one decimal ("0.7 m")
/// - < 0.5 m      -> two decimals ("0.37 m")
///
/// Precision is intentionally coarse so estimates are never presented as
/// exact measurements.
String formatDistanceMeters(double meters) {
  if (!meters.isFinite || meters <= 0) return '0 m';
  if (meters >= 10) return meters.toStringAsFixed(0);
  if (meters >= 0.5) return meters.toStringAsFixed(1);
  return meters.toStringAsFixed(2);
}