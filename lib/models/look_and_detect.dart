import 'dart:ui';

import 'object_position.dart';
import 'proximity_level.dart';

/// A single object understood by the Look & Detect assistant.
///
/// Combines a YOLO detection (class name, box, confidence) with the analysis
/// stages (position + proximity) and, when available, a familiar-person name.
/// All coordinates are normalized to the upright portrait camera frame.
class SceneObject {
  const SceneObject({
    required this.className,
    required this.boundingBox,
    required this.position,
    required this.proximity,
    this.confidence = 1.0,
    this.knownName,
  });

  /// The YOLO class label (e.g. "person", "chair", "car").
  final String className;

  /// Confidence score between 0.0 and 1.0.
  final double confidence;

  /// Bounding box in normalized [0.0, 1.0] space.
  final Rect boundingBox;

  /// Horizontal position relative to the camera view.
  final ObjectPosition position;

  /// Approximate proximity estimate (heuristic, not calibrated distance).
  final ProximityLevel proximity;

  /// Familiar-person name when the face recognition stage identified this
  /// person; otherwise null (a generic object / unknown person).
  final String? knownName;

  double get centerX => boundingBox.center.dx;
  double get centerY => boundingBox.center.dy;

  bool get isPerson => className.toLowerCase() == 'person';

  /// User-facing label: the person's name when known, else the class name.
  String get label => knownName ?? displayName;

  /// Capitalized class name (e.g. "person" -> "Person").
  String get displayName {
    if (className.isEmpty) return className;
    return className[0].toUpperCase() + className.substring(1);
  }
}

/// Natural-language phrases for [ObjectPosition].
String positionPhraseShort(ObjectPosition p) {
  switch (p) {
    case ObjectPosition.left:
      return 'on your left';
    case ObjectPosition.center:
      return 'ahead';
    case ObjectPosition.right:
      return 'on your right';
  }
}

/// Full natural-language phrases for [ObjectPosition] (spoken to the user).
String positionPhraseLong(ObjectPosition p) {
  switch (p) {
    case ObjectPosition.left:
      return 'slightly to your left';
    case ObjectPosition.center:
      return 'directly ahead';
    case ObjectPosition.right:
      return 'slightly to your right';
  }
}