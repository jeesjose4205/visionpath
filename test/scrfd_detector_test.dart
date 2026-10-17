import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/services/scrfd_face_detector.dart';

/// Synthetic-tensor tests for the SCRFD output decoder.
///
/// The decode path is the accuracy-critical, hardware-independent part of
/// detection (anchor lattice, stride scaling, score gate, NMS, keypoint
/// ordering). These tests feed hand-built output tensors so the geometry is
/// verified exactly, without needing the TFLite runtime on the host.
///
/// Anchor layout (stride s, feature map f×f, 2 anchors/position): index
/// `i = (row * f + col) * 2 + anchor`, box/keypoint values are scaled by `s`,
/// grid centres are `(col*s, row*s)`, and normalized output is `coord / 640`.
void main() {
  const int f = 80; // feature map size for stride 8
  const int count = f * f * 2; // 12800

  // Distance-form box half-extents (in stride units); 10*8 = 80px, so the
  // normalized box is 160/640 = 0.25 wide — above the 0.04 minimum size.
  const double d = 10;
  const double centre = 320; // grid col/row 40 at stride 8

  Map<String, Float32List> outputs() => {
        'score_8': Float32List(count),
        'bbox_8': Float32List(count * 4),
        'kps_8': Float32List(count * 10),
        'score_16': Float32List(40 * 40 * 2),
        'bbox_16': Float32List(40 * 40 * 2 * 4),
        'kps_16': Float32List(40 * 40 * 2 * 10),
        'score_32': Float32List(20 * 20 * 2),
        'bbox_32': Float32List(20 * 20 * 2 * 4),
        'kps_32': Float32List(20 * 20 * 2 * 10),
      };

  void putFace(Map<String, Float32List> o, int row, int col, double score,
      {int anchor = 0}) {
    final i = (row * f + col) * 2 + anchor;
    o['score_8']![i] = score;
    final o4 = i * 4;
    o['bbox_8']![o4] = d;
    o['bbox_8']![o4 + 1] = d;
    o['bbox_8']![o4 + 2] = d;
    o['bbox_8']![o4 + 3] = d;
    final o10 = i * 10;
    const kv = [-2.0, -2.0, 2.0, -2.0, 0.0, 0.0, -1.0, 1.0, 1.0, 1.0];
    for (var k = 0; k < 10; k++) {
      o['kps_8']![o10 + k] = kv[k];
    }
  }

  test('decodes one anchor into the expected box and keypoints', () {
    final o = outputs();
    putFace(o, 40, 40, 0.9);

    final faces = ScrfdFaceDetector.decodeDetections(o);
    expect(faces, hasLength(1));

    final face = faces.single;
    expect(face.boundingBox.left, closeTo((centre - d * 8) / 640, 1e-9));
    expect(face.boundingBox.top, closeTo((centre - d * 8) / 640, 1e-9));
    expect(face.boundingBox.right, closeTo((centre + d * 8) / 640, 1e-9));
    expect(face.boundingBox.bottom, closeTo((centre + d * 8) / 640, 1e-9));

    expect(face.leftEye.x, closeTo((centre - 2 * 8) / 640, 1e-9));
    expect(face.rightEye.x, closeTo((centre + 2 * 8) / 640, 1e-9));
    expect(face.leftEye.x, lessThan(face.rightEye.x));
    expect(face.noseBase.x, closeTo(centre / 640, 1e-9));
    expect(face.mouthLeft!.x, lessThan(face.mouthRight!.x));
    expect(face.rollDegrees, closeTo(0, 1e-6));
  });

  test('suppresses lower-scoring overlapping detections (NMS)', () {
    final o = outputs();
    putFace(o, 40, 40, 0.9);
    putFace(o, 40, 40, 0.7, anchor: 1); // same position, other anchor
    putFace(o, 40, 41, 0.6); // adjacent cell, heavily overlapping

    expect(ScrfdFaceDetector.decodeDetections(o), hasLength(1));
  });

  test('rejects detections below the score threshold', () {
    final o = outputs();
    putFace(o, 40, 40, 0.49);

    expect(ScrfdFaceDetector.decodeDetections(o), isEmpty);
  });

  test('returns detections ordered by descending score', () {
    final o = outputs();
    putFace(o, 10, 10, 0.6);
    putFace(o, 60, 60, 0.95);

    final faces = ScrfdFaceDetector.decodeDetections(o);
    expect(faces, hasLength(2));
    expect(faces.first.leftEye.y, greaterThan(faces.last.leftEye.y));
  });
}