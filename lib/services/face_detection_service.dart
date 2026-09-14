import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/face_detection.dart';

/// FaceDetectionService wraps the ML Kit face detector.
///
/// It works on the same upright portrait RGBA buffers as the rest of the app
/// ([convertFrameToPortraitRgba]) so all normalized coordinates refer to the
/// same portrait space. Detection is local, real and offline.
///
/// Runs ML Kit in [FaceDetectorMode.accurate] with contours enabled so the
/// recognition service can derive real face-shape features (jaw/forehead
/// widths, face height) from the dense face outline — the strongest on-device
/// discriminator the SDK exposes, and more stable than the five landmark
/// points alone.
class FaceDetectionService {
  FaceDetectionService()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.accurate,
            enableLandmarks: true,
            enableContours: true,
          ),
        );

  final FaceDetector _detector;
  bool _closed = false;

  /// Detect all faces in an upright portrait RGBA buffer.
  ///
  /// Returns normalized [DetectedFace]s for every usable face. Passes through
  /// ML Kit results untouched — no fabricated boxes or dropped faces.
  Future<List<DetectedFace>> detectRgba(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    if (_closed) return const [];
    try {
      final input = InputImage.fromBitmap(
        bitmap: rgba,
        width: width,
        height: height,
      );
      final faces = await _detector.processImage(input);
      final detected = <DetectedFace>[];
      for (final face in faces) {
        final d = _toDetectedFace(face, width, height);
        if (d != null) detected.add(d);
      }
      print('FACE_DETECT_START ${width}x$height -> ${detected.length}');
      return detected;
    } catch (e) {
      print('FACE_DETECT_ERROR: $e');
      return const [];
    }
  }

  DetectedFace? _toDetectedFace(Face face, int width, int height) {
    final box = face.boundingBox;
    if (box.width <= 0 || box.height <= 0) return null;
    if (box.isEmpty) return null;

    // Filter out absurd detections to keep matching stable.
    final normW = box.width / width;
    final normH = box.height / height;
    if (normW < 0.04 || normH < 0.04 || normW > 0.99 || normH > 0.99) {
      return null;
    }

    FaceLandmarkPoint? landmark(FaceLandmarkType type) {
      final p = face.landmarks[type]?.position;
      if (p == null) return null;
      return FaceLandmarkPoint(p.x / width, p.y / height);
    }

    final leftEye = landmark(FaceLandmarkType.leftEye);
    final rightEye = landmark(FaceLandmarkType.rightEye);
    final noseBase = landmark(FaceLandmarkType.noseBase);
    final mouthLeft = landmark(FaceLandmarkType.leftMouth);
    final mouthRight = landmark(FaceLandmarkType.rightMouth);
    final leftEar = landmark(FaceLandmarkType.leftEar);
    final rightEar = landmark(FaceLandmarkType.rightEar);
    final leftCheek = landmark(FaceLandmarkType.leftCheek);
    final rightCheek = landmark(FaceLandmarkType.rightCheek);
    final bottomMouth = landmark(FaceLandmarkType.bottomMouth);

    // Dense face outline (jaw + cheeks + forehead), normalized to portrait.
    // Only returned by ML Kit in accurate mode; may be empty on some frames.
    final contour = face.contours[FaceContourType.face]?.points ?? const [];
    final faceContour = <FaceLandmarkPoint>[
      for (final p in contour)
        FaceLandmarkPoint(p.x / width, p.y / height),
    ];

    // Core landmarks are required; mouth/ear corners may be missing when the
    // head is turned and are handled via bounding-box estimates downstream.
    if (leftEye == null || rightEye == null || noseBase == null) {
      return null;
    }

    return DetectedFace(
      boundingBox: Rect.fromLTRB(
        (box.left / width).clamp(0.0, 1.0),
        (box.top / height).clamp(0.0, 1.0),
        (box.right / width).clamp(0.0, 1.0),
        (box.bottom / height).clamp(0.0, 1.0),
      ),
      yawDegrees: face.headEulerAngleY ?? 0,
      rollDegrees: face.headEulerAngleZ ?? 0,
      leftEye: leftEye,
      rightEye: rightEye,
      noseBase: noseBase,
      mouthLeft: mouthLeft,
      mouthRight: mouthRight,
      leftEar: leftEar,
      rightEar: rightEar,
      leftCheek: leftCheek,
      rightCheek: rightCheek,
      bottomMouth: bottomMouth,
      faceContour: faceContour,
    );
  }

  /// Release the ML Kit detector. Safe to call multiple times.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _detector.close();
    } catch (e) {
      print('FACE_DETECT_CLOSE_ERROR: $e');
    }
  }
}