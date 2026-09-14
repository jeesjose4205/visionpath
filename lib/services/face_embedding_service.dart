import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/face_detection.dart';
import '../models/familiar_face.dart';

/// Learned 192-dim face embeddings via MobileFaceNet (TensorFlow Lite).
///
/// This is the accuracy-critical layer of Familiar Faces: instead of the
/// hand-crafted geometric features (which cannot fully separate similar
/// faces), the model produces a compact identity vector that the recognition
/// service compares with cosine similarity. The model is bundled in
/// `assets/ml/mobilefacenet.tflite` and runs fully offline.
///
/// The input crop is a 112×112 aligned face, produced by a similarity
/// transform (Umeyama) of the ML Kit landmarks to the canonical positions the
/// model was trained with, then bilinear resampled from the portrait RGBA
/// camera frame. All embeddings are L2-normalized.
class FaceEmbeddingService {
  FaceEmbeddingService._();
  static final FaceEmbeddingService instance = FaceEmbeddingService._();

  static const String _modelAsset = 'assets/ml/mobilefacenet.tflite';
  static const double defaultThreshold = 0.55;
  static const double ambiguityMargin = 0.06;

  Interpreter? _interpreter;
  int _size = 112;
  int _embeddingDim = 192;
  bool _loadStarted = false;
  bool _ready = false;
  String? _loadError;

  bool get isReady => _ready;
  bool get isLoading => _loadStarted;
  String? get loadError => _loadError;
  int get embeddingDim => _embeddingDim;

  /// Loads the model from assets once. Safe to call repeatedly; returns true
  /// when the interpreter is usable by the time the future completes (a
  /// concurrent load returns false immediately — poll [isReady] later).
  Future<bool> ensureLoaded() async {
    if (_ready) return true;
    if (_loadStarted) return false;
    _loadStarted = true;
    try {
      final interp = await Interpreter.fromAsset(_modelAsset);
      _interpreter = interp;
      final inShape = interp.getInputTensor(0).shape;
      if (inShape.length >= 3) {
        _size = inShape[inShape.length - 2];
      }
      final outShape = interp.getOutputTensor(0).shape;
      _embeddingDim = outShape.isEmpty ? 192 : outShape[outShape.length - 1];
      _ready = true;
      print('FACE_EMBEDDING_MODEL_READY: dim=$_embeddingDim size=$_size');
      return true;
    } catch (e) {
      _loadError = '$e';
      print('FACE_EMBEDDING_MODEL_LOAD_FAILED: $e');
      return false;
    } finally {
      _loadStarted = false;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _ready = false;
  }

  // Canonical 112×112 landmark positions the model was trained with
  // (subject-relative: [0]=left eye, [1]=right eye, [2]=nose,
  //  [3]=left mouth, [4]=right mouth).
  static const _P _cLeftEye = _P(38.2946, 51.6963);
  static const _P _cRightEye = _P(73.5318, 51.5014);
  static const _P _cNose = _P(56.0252, 71.7366);
  static const _P _cMouthLeft = _P(41.5493, 92.3655);
  static const _P _cMouthRight = _P(70.7299, 92.2041);

  /// L2-normalized embedding vector for [face] in the portrait RGBA frame.
  /// Returns null when the model isn't loaded yet or the face can't be
  /// aligned (missing eye landmarks).
  Future<List<double>?> embeddingFor(
    Uint8List rgba,
    int width,
    int height,
    DetectedFace face,
  ) async {
    final interp = _interpreter;
    if (interp == null || !_ready) return null;

    // Source landmarks in pixel space; canonical targets in 112×112 space.
    // ML Kit's left/right eye labels are subject-relative, matching the
    // canonical layout, so this stays consistent across front/back cameras.
    final src = <_P>[
      _P(face.leftEye.x * width, face.leftEye.y * height),
      _P(face.rightEye.x * width, face.rightEye.y * height),
      _P(face.noseBase.x * width, face.noseBase.y * height),
    ];
    final dst = <_P>[_cLeftEye, _cRightEye, _cNose];
    if (face.mouthLeft != null) {
      src.add(_P(face.mouthLeft!.x * width, face.mouthLeft!.y * height));
      dst.add(_cMouthLeft);
    }
    if (face.mouthRight != null) {
      src.add(_P(face.mouthRight!.x * width, face.mouthRight!.y * height));
      dst.add(_cMouthRight);
    }

    final t = _umeyama(src, dst);
    if (t == null) return null;

    // Bilinear resample of the aligned crop into [−1, 1] RGB.
    final input = Float32List(_size * _size * 3);
    var i = 0;
    final wm1 = (width - 1).toDouble();
    final hm1 = (height - 1).toDouble();
    for (var v = 0; v < _size; v++) {
      for (var u = 0; u < _size; u++) {
        final p = t.inv(_P(u.toDouble(), v.toDouble()));
        final px = p.x.clamp(0.0, wm1);
        final py = p.y.clamp(0.0, hm1);
        final x0 = px.floor();
        final y0 = py.floor();
        final x1 = x0 + 1 < width ? x0 + 1 : width - 1;
        final y1 = y0 + 1 < height ? y0 + 1 : height - 1;
        final fx = px - x0;
        final fy = py - y0;
        final c00 = (y0 * width + x0) * 4;
        final c10 = (y0 * width + x1) * 4;
        final c01 = (y1 * width + x0) * 4;
        final c11 = (y1 * width + x1) * 4;
        for (var ch = 0; ch < 3; ch++) {
          final v00 = rgba[c00 + ch];
          final v10 = rgba[c10 + ch];
          final v01 = rgba[c01 + ch];
          final v11 = rgba[c11 + ch];
          final b = v00 * (1 - fx) * (1 - fy) +
              v10 * fx * (1 - fy) +
              v01 * (1 - fx) * fy +
              v11 * fx * fy;
          input[i++] = (b - 127.5) / 128.0;
        }
      }
    }

    final out = Float32List(_embeddingDim);
    interp.run(input, out);
    return _l2Normalize(out);
  }

  /// Pointwise mean of [samples], L2-normalized — the stored representative
  /// embedding for a registered person.
  static List<double> normalizedMean(List<List<double>> samples) {
    if (samples.isEmpty) return const [];
    final dims = samples.first.length;
    final mean = List<double>.filled(dims, 0);
    for (final s in samples) {
      if (s.length != dims) continue;
      for (var i = 0; i < dims; i++) {
        mean[i] += s[i];
      }
    }
    final count = samples.where((s) => s.length == dims).length;
    if (count == 0) return const [];
    for (var i = 0; i < dims; i++) {
      mean[i] /= count;
    }
    final norm = _norm(mean);
    if (norm < 1e-9) return const [];
    return [for (final v in mean) v / norm];
  }

  /// Best person for [embedding] by cosine similarity, or null when the
  /// match is below [threshold] or the top-two are too ambiguous. Only
  /// people whose stored embedding dimension matches are considered, which
  /// cleanly separates learned-model records from legacy geometric ones.
  FaceEmbeddingMatch? identify(
    List<double> embedding,
    List<FamiliarFace> people, {
    double threshold = defaultThreshold,
  }) {
    if (people.isEmpty) return null;

    double best = -1;
    double second = -1;
    FamiliarFace? bestP;
    for (final person in people) {
      if (person.embedding.length != embedding.length) continue;
      final sim = cosineSimilarity(embedding, person.embedding);
      print('FACE_DETECT_ML_SIM ${person.name}: '
          '${(sim * 100).toStringAsFixed(1)}%');
      if (sim > best) {
        second = best;
        best = sim;
        bestP = person;
      } else if (sim > second) {
        second = sim;
      }
    }
    print('FACE_DETECT_ML_SIM best: ${(best * 100).toStringAsFixed(1)}% '
        'threshold: ${(threshold * 100).toStringAsFixed(1)}%');
    if (bestP == null || best < threshold) return null;
    final margin = second < 0 ? 1.0 : best - second;
    if (margin < ambiguityMargin) return null;
    return FaceEmbeddingMatch(person: bestP, similarity: best);
  }

  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0;
    var dot = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  // ---------------------------------------------------------------
  // Alignment / resample internals
  // ---------------------------------------------------------------

  static List<double> _l2Normalize(Float32List v) {
    final norm = _norm(v);
    if (norm < 1e-9) return List<double>.filled(v.length, 0);
    return [for (final x in v) x / norm];
  }

  static double _norm(List<double> v) {
    double sum = 0;
    for (final x in v) {
      sum += x * x;
    }
    return math.sqrt(sum);
  }

  /// Similarity transform y = s*R*x + t mapping [src] onto [dst]
  /// (Umeyama 1991). Returns null when fewer than 2 points are given.
  static _Transform? _umeyama(List<_P> src, List<_P> dst) {
    final n = src.length;
    if (n < 2) return null;
    var muX = _P(0, 0);
    var muY = _P(0, 0);
    for (var i = 0; i < n; i++) {
      muX = muX + src[i];
      muY = muY + dst[i];
    }
    muX = muX * (1 / n);
    muY = muY * (1 / n);
    var sigma = _M2(0, 0, 0, 0);
    var varX = 0.0;
    for (var i = 0; i < n; i++) {
      final x = src[i] - muX;
      final y = dst[i] - muY;
      final o = y.outer(x);
      sigma = _M2(
        sigma[0] + o[0],
        sigma[1] + o[1],
        sigma[2] + o[2],
        sigma[3] + o[3],
      );
      varX += x.dot(x);
    }
    sigma = sigma.scaled(1 / n);
    final usv = _svd2x2(sigma);
    final u = usv[0];
    final v = usv[2];
    final svals = usv[1];
    final detU = u[0] * u[3] - u[1] * u[2];
    final detV = v[0] * v[3] - v[1] * v[2];
    final sign = (detU * detV) >= 0 ? 1.0 : -1.0;
    final r = u.mul(_M2(1, 0, 0, sign)).mul(v.transpose());
    final scale = (svals[0] + sign * svals[3]) / (varX / n);
    final t = muY - r.scaled(scale).vec(muX);
    return _Transform(scale, r, t);
  }
}

/// Result of matching an embedding against the registry.
class FaceEmbeddingMatch {
  const FaceEmbeddingMatch({required this.person, required this.similarity});
  final FamiliarFace person;
  final double similarity;
}

// ---------------------------------------------------------------
// Small linear-algebra helpers (2×2 SVD + transforms)
// ---------------------------------------------------------------

class _P {
  const _P(this.x, this.y);
  final double x, y;
  _P operator +(_P o) => _P(x + o.x, y + o.y);
  _P operator -(_P o) => _P(x - o.x, y - o.y);
  _P operator *(double s) => _P(x * s, y * s);
  _M2 outer(_P o) => _M2(x * o.x, x * o.y, y * o.x, y * o.y);
  double dot(_P o) => x * o.x + y * o.y;
}

class _M2 {
  const _M2(this.a, this.b, this.c, this.d);
  final double a, b, c, d;
  _M2 mul(_M2 o) => _M2(
        a * o.a + b * o.c,
        a * o.b + b * o.d,
        c * o.a + d * o.c,
        c * o.b + d * o.d,
      );
  _M2 transpose() => _M2(a, c, b, d);
  _M2 scaled(double s) => _M2(a * s, b * s, c * s, d * s);
  _P vec(_P v) => _P(a * v.x + b * v.y, c * v.x + d * v.y);
  double operator [](int i) =>
      i == 0 ? a : (i == 1 ? b : (i == 2 ? c : d));
}

/// 2×2 SVD via eigendecomposition of A·Aᵀ and Aᵀ·A; S is recovered as
/// Uᵀ·A·V so A == U·S·Vᵀ holds exactly.
List<_M2> _svd2x2(_M2 a) {
  final p1 = a[0] * a[0] + a[1] * a[1];
  final q1 = a[0] * a[2] + a[1] * a[3];
  final r1 = a[2] * a[2] + a[3] * a[3];
  final phiU = 0.5 * math.atan2(2 * q1, p1 - r1);
  final u = _M2(math.cos(phiU), -math.sin(phiU), math.sin(phiU), math.cos(phiU));
  final p2 = a[0] * a[0] + a[2] * a[2];
  final q2 = a[0] * a[1] + a[2] * a[3];
  final r2 = a[1] * a[1] + a[3] * a[3];
  final phiV = 0.5 * math.atan2(2 * q2, p2 - r2);
  final v = _M2(math.cos(phiV), -math.sin(phiV), math.sin(phiV), math.cos(phiV));
  final s = u.transpose().mul(a).mul(v);
  return [_M2(u[0], u[1], u[2], u[3]), _M2(s[0], 0, 0, s[3]), v];
}

class _Transform {
  _Transform(this.s, this.r, this.t);
  final double s;
  final _M2 r;
  final _P t;

  /// Maps an output (canonical) pixel back to a source pixel via
  /// x = (1/s)·Rᵀ·(y − t).
  _P inv(_P y) {
    final dy = y - t;
    final rt = r.transpose();
    return _P(rt[0] * dy.x + rt[1] * dy.y, rt[2] * dy.x + rt[3] * dy.y) *
        (1 / s);
  }
}