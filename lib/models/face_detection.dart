import 'dart:ui';

import 'object_position.dart';

/// A key facial keypoint in normalized portrait coordinates (0..1).
class FaceLandmarkPoint {
  const FaceLandmarkPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  String toString() => '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// A single detected face — pure geometry, no identity.
///
/// All coordinates are normalized (0..1) against the upright portrait input
/// frame, matching every other detection model in the app.
class DetectedFace {
  const DetectedFace({
    required this.boundingBox,
    required this.yawDegrees,
    required this.rollDegrees,
    required this.leftEye,
    required this.rightEye,
    required this.noseBase,
    required this.mouthLeft,
    required this.mouthRight,
    required this.leftEar,
    required this.rightEar,
    this.leftCheek,
    this.rightCheek,
    this.bottomMouth,
    this.faceContour = const [],
    this.chin,
  });

  /// Normalized bounding box (upright portrait).
  final Rect boundingBox;

  /// Horizontal head turn in degrees (ML Kit Euler angle Y).
  final double yawDegrees;

  /// In-plane head rotation in degrees (ML Kit Euler angle Z).
  final double rollDegrees;

  final FaceLandmarkPoint leftEye;
  final FaceLandmarkPoint rightEye;
  final FaceLandmarkPoint noseBase;

  /// Mouth corners (null when ML Kit could not estimate them, e.g. when the
  /// head is turned; the recognition service substitutes bounding-box-based
  /// estimates so side turns during registration are not rejected).
  final FaceLandmarkPoint? mouthLeft;
  final FaceLandmarkPoint? mouthRight;

  /// Ear positions (null when ML Kit could not estimate them; the recognition
  /// service substitutes the bounding-box sides in that case).
  final FaceLandmarkPoint? leftEar;
  final FaceLandmarkPoint? rightEar;

  /// Cheek landmarks (bizygomatic points) — strong face-shape discriminators.
  /// Null when ML Kit did not estimate them for this frame.
  final FaceLandmarkPoint? leftCheek;
  final FaceLandmarkPoint? rightCheek;

  /// Bottom of the mouth (lower lip center). Null when ML Kit did not
  /// estimate it.
  final FaceLandmarkPoint? bottomMouth;

  /// The dense face-outline contour (jaw + cheeks + forehead silhouette) as
  /// normalized points, in acquisition order. Empty when ML Kit did not
  /// produce a face contour for this frame.
  final List<FaceLandmarkPoint> faceContour;

  /// Approximate chin position (bounding-box bottom center, roll-aligned by
  /// the recognition service); may be null before preprocessing.
  final FaceLandmarkPoint? chin;

  double get centerX => boundingBox.center.dx;
  double get centerY => boundingBox.center.dy;
  double get width => boundingBox.width;
  double get height => boundingBox.height;

  ObjectPosition get position => ObjectPosition.fromCenterX(centerX);

  /// Face present and reasonably upright (ML Kit convention: right is
  /// counter-clockwise negative on the back camera, so clamp to +/-25 deg).
  bool get isUpright => rollDegrees.abs() <= 25;
}

/// Result of matching a generated embedding against registered people.
class FaceRecognitionResult {
  const FaceRecognitionResult._({
    this.personId,
    this.personName,
    this.similarity = 0,
  });

  const FaceRecognitionResult.unknown()
      : this._(personId: null, personName: null, similarity: 0);

  /// Non-null when the face matches a registered person.
  final String? personId;
  final String? personName;

  /// Cosine similarity (0..1) against the matched embedding, or 0 for unknown.
  final double similarity;

  bool get isKnown => personId != null;

  factory FaceRecognitionResult.known({
    required String personId,
    required String personName,
    required double similarity,
  }) {
    return FaceRecognitionResult._(
      personId: personId,
      personName: personName,
      similarity: similarity,
    );
  }
}

/// Voice-speakable identity + position for a face tracker.
class FaceOccurrence {
  const FaceOccurrence({
    required this.identityKey,
    required this.name,
    required this.position,
    required this.similarity,
    required this.isUnknown,
    required this.cx,
    required this.cy,
  });

  /// Person id, or a stable marker such as 'UNKNOWN'.
  final String identityKey;

  /// Display name, or 'Unknown person'.
  final String? name;

  final ObjectPosition position;
  final double similarity;
  final bool isUnknown;
  final double cx;
  final double cy;

  /// "Mother is on your left." / "Unknown person is ahead."
  String get message {
    final name = this.name ?? 'Unknown person';
    final String location;
    switch (position) {
      case ObjectPosition.left:
        location = 'on your left';
      case ObjectPosition.center:
        location = 'directly ahead';
      case ObjectPosition.right:
        location = 'on your right';
    }
    return '$name is $location.';
  }
}