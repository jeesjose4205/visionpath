import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/models/face_detection.dart';
import 'package:visionpath/models/familiar_face.dart';
import 'package:visionpath/services/face_recognition_service.dart';

DetectedFace _face({
  double leftEyeX = 0.42,
  double rightEyeX = 0.58,
  double noseX = 0.50,
  double noseY = 0.50,
  double mouthLX = 0.45,
  double mouthRX = 0.55,
  double mouthY = 0.58,
  double earLX = 0.28,
  double earRX = 0.72,
  double yaw = 0,
  double roll = 0,
  Rect? box,
}) {
  final b =
      box ??
      const Rect.fromLTRB(0.22, 0.26, 0.78, 0.78);
  return DetectedFace(
    boundingBox: b,
    yawDegrees: yaw,
    rollDegrees: roll,
    leftEye: FaceLandmarkPoint(leftEyeX, 0.40),
    rightEye: FaceLandmarkPoint(rightEyeX, 0.40),
    noseBase: FaceLandmarkPoint(noseX, noseY),
    mouthLeft: FaceLandmarkPoint(mouthLX, mouthY),
    mouthRight: FaceLandmarkPoint(mouthRX, mouthY),
    leftEar: FaceLandmarkPoint(earLX, 0.42),
    rightEar: FaceLandmarkPoint(earRX, 0.42),
  );
}

Rect _rotatedRect(Rect r, double deg) {
  final a = deg * math.pi / 180;
  final c = r.center;
  Offset rot(Offset p) {
    final dx = p.dx - c.dx;
    final dy = p.dy - c.dy;
    return Offset(
      c.dx + dx * math.cos(a) - dy * math.sin(a),
      c.dy + dx * math.sin(a) + dy * math.cos(a),
    );
  }

  final p1 = rot(r.topLeft);
  final p2 = rot(r.topRight);
  final p3 = rot(r.bottomLeft);
  final p4 = rot(r.bottomRight);
  final xs = [p1.dx, p2.dx, p3.dx, p4.dx];
  final ys = [p1.dy, p2.dy, p3.dy, p4.dy];
  return Rect.fromLTRB(
    xs.reduce(math.min),
    ys.reduce(math.min),
    xs.reduce(math.max),
    ys.reduce(math.max),
  );
}

void main() {
  final service = FaceRecognitionService();

  group('geometric embedding', () {
    test('is unit length and deterministic', () {
      final a = service.generateEmbedding(_face())!;
      final b = service.generateEmbedding(_face())!;

      double norm = 0;
      for (final v in a) {
        norm += v * v;
      }
      expect(norm, closeTo(1.0, 1e-9));
      expect(a, b);
    });

    test('is translation invariant', () {
      final a = service.generateEmbedding(_face())!;
      final shiftedBox = const Rect.fromLTRB(0.25, 0.28, 0.81, 0.80);
      final shifted = service.generateEmbedding(
        _face(box: shiftedBox),
      )!;
      expect(service.cosineSimilarity(a, shifted), closeTo(1.0, 1e-6));
    });

    test('is scale invariant', () {
      // Scale every coordinate by 0.85 around the frame center.
      Offset scale(Offset p) =>
          Offset(0.5 + (p.dx - 0.5) * 0.85, 0.5 + (p.dy - 0.5) * 0.85);
      const b = Rect.fromLTRB(0.22, 0.26, 0.78, 0.78);
      final sb = Rect.fromLTRB(
        scale(b.topLeft).dx,
        scale(b.topLeft).dy,
        scale(b.bottomRight).dx,
        scale(b.bottomRight).dy,
      );
      final a = service.generateEmbedding(_face())!;
      final s = service.generateEmbedding(
        _face(
          leftEyeX: scale(const Offset(0.42, 0.40)).dx,
          rightEyeX: scale(const Offset(0.58, 0.40)).dx,
          noseX: scale(const Offset(0.50, 0.50)).dx,
          noseY: scale(const Offset(0.50, 0.50)).dy,
          mouthLX: scale(const Offset(0.45, 0.58)).dx,
          mouthRX: scale(const Offset(0.55, 0.58)).dx,
          mouthY: scale(const Offset(0.45, 0.58)).dy,
          earLX: scale(const Offset(0.28, 0.42)).dx,
          earRX: scale(const Offset(0.72, 0.42)).dx,
          box: sb,
        ),
      )!;
      expect(service.cosineSimilarity(a, s), closeTo(1.0, 1e-6));
    });

    test('is resistant to in-plane roll after alignment', () {
      const deg = 12.0;
      Offset rot(Offset p) {
        final a = deg * math.pi / 180;
        final c = const Offset(0.5, 0.5);
        final dx = p.dx - c.dx;
        final dy = p.dy - c.dy;
        return Offset(
          c.dx + dx * math.cos(a) - dy * math.sin(a),
          c.dy + dx * math.sin(a) + dy * math.cos(a),
        );
      }

      final a = service.generateEmbedding(_face())!;
      final r = service.generateEmbedding(
        DetectedFace(
          boundingBox: _rotatedRect(const Rect.fromLTRB(0.22, 0.26, 0.78, 0.78), deg),
          yawDegrees: 0,
          rollDegrees: deg,
          leftEye: FaceLandmarkPoint(rot(const Offset(0.42, 0.40)).dx,
              rot(const Offset(0.42, 0.40)).dy),
          rightEye: FaceLandmarkPoint(rot(const Offset(0.58, 0.40)).dx,
              rot(const Offset(0.58, 0.40)).dy),
          noseBase: FaceLandmarkPoint(
              rot(const Offset(0.50, 0.50)).dx,
              rot(const Offset(0.50, 0.50)).dy),
          mouthLeft: FaceLandmarkPoint(rot(const Offset(0.45, 0.58)).dx,
              rot(const Offset(0.45, 0.58)).dy),
          mouthRight: FaceLandmarkPoint(rot(const Offset(0.55, 0.58)).dx,
              rot(const Offset(0.55, 0.58)).dy),
          leftEar: FaceLandmarkPoint(rot(const Offset(0.28, 0.42)).dx,
              rot(const Offset(0.28, 0.42)).dy),
          rightEar: FaceLandmarkPoint(rot(const Offset(0.72, 0.42)).dx,
              rot(const Offset(0.72, 0.42)).dy),
        ),
      )!;
      expect(service.cosineSimilarity(a, r), greaterThanOrEqualTo(0.95));
    });

    test('matches itself and rejects a clearly different face', () {
      final motherEmb = service.generateEmbedding(_face())!;
      final mother = FamiliarFace(
        id: 'm1',
        name: 'Mother',
        embedding: motherEmb,
        sampleCount: 4,
        createdAt: 0,
      );

      final hit = service.identify(motherEmb, [mother]);
      expect(hit.isKnown, isTrue);
      expect(hit.personName, 'Mother');

      // A clearly different face: nose and mouth pushed far off-centre,
      // asymmetric ears down at the jaw height.
      final otherEmb = service.generateEmbedding(
        _face(
          noseX: 0.63,
          noseY: 0.56,
          mouthLX: 0.52,
          mouthRX: 0.70,
          mouthY: 0.62,
          earLX: 0.19,
          earRX: 0.69,
        ),
      )!;
      expect(service.cosineSimilarity(motherEmb, otherEmb),
          lessThan(service.similarityThreshold));
      final miss = service.identify(otherEmb, [mother]);
      expect(miss.isKnown, isFalse);
    });

    test('mean embedding is a stable unit-length representative', () {
      final s1 = service.generateEmbedding(_face())!;
      final s2 = service.generateEmbedding(
        _face(noseX: 0.50, mouthRX: 0.57),
      )!;
      final mean = service.meanEmbedding([s1, s2])!;
      double norm = 0;
      for (final v in mean) {
        norm += v * v;
      }
      expect(norm, closeTo(1.0, 1e-9));
      expect(service.cosineSimilarity(s1, mean), greaterThan(0.9));
    });
  });
}