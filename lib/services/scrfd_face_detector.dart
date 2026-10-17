import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/face_detection.dart';

/// On-device face detector backed by SCRFD (Sample and Computation
/// Redistribution for Face Detection), running as a local TFLite model.
///
/// It consumes the same upright portrait RGBA buffers as the rest of the app
/// ([convertFrameToPortraitRgba]) and returns normalized [DetectedFace]s, so
/// every downstream consumer keeps working unchanged.
///
/// The model emits, for each of three feature strides (8/16/32), a per-anchor
/// confidence, a distance-form bounding box and five keypoints:
///   * bounding box  = (cx ± d × stride), centre = anchor grid × stride
///   * keypoints     = (cx + kx × stride, cy + ky × stride)
/// with two anchors per grid position. Results are filtered at
/// [scoreThreshold] and merged with greedy non-maximum suppression
/// ([nmsThreshold]). The five keypoints (eyes, nose, mouth corners) are exactly
/// the landmarks ArcFace alignment needs.
class ScrfdFaceDetector {
  ScrfdFaceDetector();

  static const String _modelAsset = 'assets/ml/scrfd_640.tflite';
  static const int _inputSize = 640;
  static const int _numAnchors = 2;
  static const List<int> _strides = [8, 16, 32];

  /// Minimum per-anchor confidence. Conservative so weak/ambiguous detections
  /// are dropped rather than fed to the recognizer (a missed face is a safe
  /// failure; a false face is not).
  static const double scoreThreshold = 0.5;

  /// Intersection-over-union above which overlapping boxes are suppressed.
  static const double nmsThreshold = 0.4;

  Interpreter? _interpreter;
  bool _loadStarted = false;
  bool _ready = false;
  String? _loadError;

  bool get isReady => _ready;
  String? get loadError => _loadError;

  /// Load the model once. Safe to call repeatedly; returns true on success.
  Future<bool> ensureLoaded() async {
    if (_ready) return true;
    if (_loadStarted) return false;
    _loadStarted = true;
    try {
      _interpreter = await Interpreter.fromAsset(_modelAsset);
      _ready = true;
      print('FACE_DETECTOR_READY: scrfd ${_inputSize}x$_inputSize');
      return true;
    } catch (e) {
      _loadError = '$e';
      print('FACE_DETECTOR_LOAD_FAILED: $e');
      return false;
    } finally {
      _loadStarted = false;
    }
  }

  /// Detect all faces in an upright portrait RGBA buffer.
  Future<List<DetectedFace>> detectRgba(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final interp = _interpreter;
    if (!_ready || interp == null) return const [];
    if (width <= 0 || height <= 0) return const [];

    try {
      final input = _preprocess(rgba, width, height);
      final raw = _infer(interp, input);
      final faces = decodeDetections(raw);
      print('FACE_DETECT_START ${width}x$height -> ${faces.length}');
      return faces;
    } catch (e) {
      print('FACE_DETECT_ERROR: $e');
      return const [];
    }
  }

  /// Resize the portrait frame to the square model input with bilinear
  /// interpolation (matches how the model behaves in practice) and normalize
  /// RGB to [-1, 1).
  Float32List _preprocess(Uint8List rgba, int width, int height) {
    final input = Float32List(_inputSize * _inputSize * 3);
    var i = 0;
    final fx = width / _inputSize;
    final fy = height / _inputSize;
    final wm1 = width - 1;
    final hm1 = height - 1;
    for (var v = 0; v < _inputSize; v++) {
      final sy = v * fy;
      final y0 = sy.floor().clamp(0, hm1);
      final y1 = (y0 + 1).clamp(0, hm1);
      final fyv = sy - y0;
      for (var u = 0; u < _inputSize; u++) {
        final sx = u * fx;
        final x0 = sx.floor().clamp(0, wm1);
        final x1 = (x0 + 1).clamp(0, wm1);
        final fxu = sx - x0;
        final r0 = (y0 * width + x0) * 4;
        final r1 = (y0 * width + x1) * 4;
        final r2 = (y1 * width + x0) * 4;
        final r3 = (y1 * width + x1) * 4;
        for (var ch = 0; ch < 3; ch++) {
          final v00 = rgba[r0 + ch];
          final v10 = rgba[r1 + ch];
          final v01 = rgba[r2 + ch];
          final v11 = rgba[r3 + ch];
          final val = v00 * (1 - fxu) * (1 - fyv) +
              v10 * fxu * (1 - fyv) +
              v01 * (1 - fxu) * fyv +
              v11 * fxu * fyv;
          input[i++] = (val - 127.5) / 128.0;
        }
      }
    }
    return input;
  }

  /// Run the interpreter and collect its outputs keyed by tensor name. Output
  /// names are stable across the exported model (`score_8`, `bbox_16`, …).
  Map<String, Float32List> _infer(Interpreter interp, Float32List input) {
    final outTensors = interp.getOutputTensors();
    final buffers = <int, Object>{};
    final byName = <String, int>{};
    for (var i = 0; i < outTensors.length; i++) {
      final t = outTensors[i];
      var n = 1;
      for (final d in t.shape) {
        n *= d;
      }
      buffers[i] = Float32List(n);
      byName[t.name] = i;
    }
    interp.runForMultipleInputs([input], buffers);
    return {
      for (final entry in byName.entries)
        entry.key: buffers[entry.value]! as Float32List,
    };
  }

  /// Pure post-processing: decode, threshold, NMS and convert to
  /// [DetectedFace]s. Kept free of any interpreter so it can be unit-tested
  /// with synthetic tensors.
  static List<DetectedFace> decodeDetections(
    Map<String, Float32List> outputs,
  ) {
    final dets = <_RawDetection>[];
    for (final s in _strides) {
      final scores = outputs['score_$s'];
      final bboxes = outputs['bbox_$s'];
      final kpss = outputs['kps_$s'];
      if (scores == null || bboxes == null || kpss == null) continue;

      final feat = _inputSize ~/ s;
      final count = feat * feat * _numAnchors;
      for (var i = 0; i < count; i++) {
        final score = scores[i];
        if (score < scoreThreshold) continue;

        final pos = i ~/ _numAnchors;
        final cx = (pos % feat) * s.toDouble();
        final cy = (pos ~/ feat) * s.toDouble();

        final o4 = i * 4;
        final left = (cx - bboxes[o4] * s) / _inputSize;
        final top = (cy - bboxes[o4 + 1] * s) / _inputSize;
        final right = (cx + bboxes[o4 + 2] * s) / _inputSize;
        final bottom = (cy + bboxes[o4 + 3] * s) / _inputSize;

        final o10 = i * 10;
        final kps = <FaceLandmarkPoint>[
          for (var k = 0; k < 5; k++)
            FaceLandmarkPoint(
              (cx + kpss[o10 + k * 2] * s) / _inputSize,
              (cy + kpss[o10 + k * 2 + 1] * s) / _inputSize,
            ),
        ];

        dets.add(_RawDetection(
          Rect.fromLTRB(left, top, right, bottom),
          score,
          kps,
        ));
      }
    }

    final faces = <DetectedFace>[];
    for (final d in _nms(dets)) {
      final face = _toDetectedFace(d);
      if (face != null) faces.add(face);
    }
    return faces;
  }

  static DetectedFace? _toDetectedFace(_RawDetection d) {
    final box = d.box;
    final w = box.width;
    final h = box.height;
    if (w < 0.04 || h < 0.04 || w > 0.99 || h > 0.99) return null;

    // Image order: [0]=left eye, [1]=right eye, [2]=nose, [3]/[4]=mouth.
    final le = d.kps[0];
    final re = d.kps[1];
    final roll = math.atan2(re.y - le.y, re.x - le.x) * 180 / math.pi;

    return DetectedFace(
      boundingBox: Rect.fromLTRB(
        box.left.clamp(0.0, 1.0),
        box.top.clamp(0.0, 1.0),
        box.right.clamp(0.0, 1.0),
        box.bottom.clamp(0.0, 1.0),
      ),
      yawDegrees: 0,
      rollDegrees: roll,
      leftEye: le,
      rightEye: re,
      noseBase: d.kps[2],
      mouthLeft: d.kps[3],
      mouthRight: d.kps[4],
      leftEar: null,
      rightEar: null,
    );
  }

  static List<_RawDetection> _nms(List<_RawDetection> dets) {
    final sorted = [...dets]..sort((a, b) => b.score.compareTo(a.score));
    final keep = <_RawDetection>[];
    for (final a in sorted) {
      var suppressed = false;
      for (final b in keep) {
        if (_iou(a.box, b.box) >= nmsThreshold) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) keep.add(a);
    }
    return keep;
  }

  static double _iou(Rect a, Rect b) {
    final l = math.max(a.left, b.left);
    final t = math.max(a.top, b.top);
    final r = math.min(a.right, b.right);
    final bo = math.min(a.bottom, b.bottom);
    final inter = math.max(0.0, r - l) * math.max(0.0, bo - t);
    if (inter <= 0) return 0;
    final union = a.width * a.height + b.width * b.height - inter;
    return union <= 0 ? 0 : inter / union;
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _ready = false;
  }
}

class _RawDetection {
  _RawDetection(this.box, this.score, this.kps);

  final Rect box;
  final double score;
  final List<FaceLandmarkPoint> kps;
}