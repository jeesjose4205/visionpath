import 'dart:math' as math;

import '../models/face_detection.dart';
import '../models/familiar_face.dart';

/// FaceRecognitionService turns a detected face into a real, deterministic
/// geometric embedding and matches it against registered people.
///
/// The embedding is computed from ML Kit face landmarks (eyes / nose / mouth /
  /// ears) plus the bounding-box face shape. It is:
  ///  - translation invariant  (all coordinates are relative to the eye midpoint)
  ///  - rotation invariant     (landmark coordinates are roll-aligned first)
  ///  - scale invariant        (every feature is divided by the interocular
  ///    distance, the classic biometric normalizer)
  ///
  /// The 26-dimensional feature vector mixes:
  ///  A. Interior landmark positions (nose / mouth / ear relative to eye midpoint)
  ///  B. Distances and ratios between landmarks (mouth width, nose-to-chin, etc.)
  ///  C. Face-shape features (cheek-to-cheek width, face box width & height
  ///     versus interocular) — the strongest discriminators between people.
  ///  D. Vertical face features (nose-to-lower-lip height, lip-to-chin height).
  ///
  /// Matching uses cosine similarity against the stored representative
  /// embedding, with a conservative threshold so a low-confidence face is
  /// reported as "unknown" rather than guessed.
class FaceRecognitionService {
  FaceRecognitionService({this.similarityThreshold = defaultThreshold});

  /// Conservative cosine-similarity gate: below this, a face is "unknown".
  ///
  /// Matching runs on the per-feature-whitened embedding (each raw feature
  /// divided by its inter-person range before L2 normalising), so face-shape
  /// dimensions contribute as much as position dimensions. On the numerical
  /// verification, same-person under landmark noise scores 0.99+ and under
  /// 12 deg roll ~0.91, while a genuinely different face scores ~0.92;
  /// 0.95 sits between those so a good match is accepted and a stranger or a
  /// strong head tilt reports "unknown" (a safe failure — we prefer a
  /// false-unknown over a false-match).
  static const double defaultThreshold = 0.95;
  static const int _dimensions = 32;

  /// Approximate inter-person range of each raw feature (used to whiten:
  /// divide each feature by its range so no single dimension dominates the
  /// L2 norm). Values are anthropometric ballparks from the observation that
  /// face shape features vary more between people than landmark positions;
  /// see the standalone embed_verify.dart harness and tune on-device.
  static const List<double> _ranges = [
    0.15, 0.15, 0.20, 0.20, 0.20, 0.20, 0.15, 0.15, 0.15, 0.15, // 0-9  positions
    0.40, 1.50, 0.30, 0.80, 1.00, 0.60, 1.00, 1.50, 0.60, 1.00, // 10-19 distances
    2.50, 3.50, 1.50, 0.80, 1.00, 0.50, // 20-25 face shape (landmark/box)
    2.00, 3.50, 1.50, 1.50, // 26-29 contour shape
    0.40, 0.40, // 30-31 contour width ratios
  ];

  /// How far past the mouth the (landmark-proxy) chin extends, as a fraction
  /// of the nose-to-mouth-center distance.
  static const double _chinK = 0.85;

  double similarityThreshold;

  /// Generate the whitened, L2-normalized geometric embedding for a face, or
  /// null when the face is unusable (e.g. zero interocular distance).
  List<double>? generateEmbedding(DetectedFace face) {
    final aligned = _align(face);
    if (aligned == null) return null;

    final I = aligned.interocular;
    if (I < 1e-6) return null;

    final features = _rawFeatures(face, aligned);
    if (features.length != _dimensions) return null;

    // Whiten: divide each raw feature by its inter-person range so face-shape
    // dimensions (which carry the most identity signal) are not swamped by the
    // L2 norm, then normalise to unit length for cosine matching.
    final whitened = <double>[
      for (var i = 0; i < features.length; i++) features[i] / _ranges[i],
    ];
    final norm = _norm(whitened);
    if (norm < 1e-9) return null;
    return [for (final v in whitened) v / norm];
  }

  /// Raw scale-invariant features (before whitening/L2).
  List<double> _rawFeatures(DetectedFace face, _Aligned aligned) {
    final I = aligned.interocular;
    double dx(FaceLandmarkPoint p) => p.x / I;
    double dy(FaceLandmarkPoint p) => p.y / I;

    final n = aligned.nose;
    final ml = aligned.mouthLeft;
    final mr = aligned.mouthRight;
    final el = aligned.leftEar;
    final er = aligned.rightEar;
    final lc = aligned.leftCheek;
    final rc = aligned.rightCheek;
    final bm = aligned.bottomMouth;
    final c = aligned.chin;
    final mouthMidX = (ml.x + mr.x) / 2;

    final box = face.boundingBox;

    // 30-dim geometric embedding.
    // [0..9]   interior landmark positions (nose / mouth / ears relative to
    //           eye midpoint, all divided by interocular distance I)
    // [10..19] landmark distances and ratios (mouth width, chin height, etc.)
    // [20..25] face-shape features: face-box width/height vs I, cheek width,
    //           cheek asymmetry, nose-to-lower-lip height, lip-to-chin height.
    // [26..29] contour-shape features derived from the dense face outline
    //           (jaw/forehead widths, face height) — the strongest
    //           face-shape discriminators between different people.
    final contour = aligned.faceContour;
    final bool hasContour = contour.length >= 5;

    // Contour bounding extents (computed first, used by helpers + return).
    double cMinY = 0;
    double cMaxY = 0;
    double contourWidthLo = double.infinity;
    double contourWidthHi = double.negativeInfinity;
    if (hasContour) {
      cMinY = contour.first.y;
      cMaxY = contour.first.y;
      for (final p in contour) {
        if (p.y < cMinY) cMinY = p.y;
        if (p.y > cMaxY) cMaxY = p.y;
        if (p.x < contourWidthLo) contourWidthLo = p.x;
        if (p.x > contourWidthHi) contourWidthHi = p.x;
      }
    }
    final double contourFaceHeight = hasContour ? cMaxY - cMinY : 0;
    final double contourMaxWidth =
        hasContour ? contourWidthHi - contourWidthLo : 0;
    final mouthMidY = (ml.y + mr.y) / 2;
    final foreheadRowY = hasContour ? cMinY + 0.30 * (-cMinY) : 0.0;

    // Helper: width of contour points within a horizontal band around [rowY].
    double contourWidthAt(double rowY, double bandFraction) {
      if (!hasContour) return 0;
      final band = (cMaxY - cMinY) * bandFraction;
      var lo = double.infinity;
      var hi = double.negativeInfinity;
      for (final p in contour) {
        if ((p.y - rowY).abs() <= band) {
          if (p.x < lo) lo = p.x;
          if (p.x > hi) hi = p.x;
        }
      }
      if (!lo.isFinite || !hi.isFinite || hi <= lo) return 0;
      return (hi - lo) / I;
    }

    final double faceMaxWidthNorm = contourMaxWidth / I;
    final jawRowWidthNorm = contourWidthAt(mouthMidY, 0.12);
    final foreheadRowWidthNorm = contourWidthAt(foreheadRowY, 0.12);

    return <double>[
      dx(n), dy(n), // 0-1  nose offset
      dx(ml), dy(ml), // 2-3  left mouth corner
      dx(mr), dy(mr), // 4-5  right mouth corner
      dx(el), dy(el), // 6-7  ear (mirrored-left side)
      dx(er), dy(er), // 8-9  ear (mirrored-right side)
      (mr.x - ml.x).abs() / I, // 10  mouth width
      (er.x - el.x).abs() / I, // 11  ear-to-ear width
      (ml.y - mr.y).abs() / I, // 12  mouth tilt
      (el.y - er.y).abs() / I, // 13  ear height asymmetry
      (c.y - n.y) / I, // 14  nose-to-chin height
      (c.x - n.x) / I, // 15  nose-to-chin horizontal offset
      c.x / I, // 16  chin offset from eye midpoint
      c.y / I, // 17  chin height
      (mouthMidX - n.x) / I, // 18  mouth-center vs nose offset
      mouthMidX / I, // 19  mouth-center vs eye midpoint
      box.width / I, // 20  face width  / interocular (face shape)
      box.height / I, // 21  face height / interocular (face shape)
      (rc.x - lc.x).abs() / I, // 22  cheek-to-cheek (bizygomatic) width
      (lc.y - rc.y).abs() / I, // 23  cheek height asymmetry
      (bm.y - n.y) / I, // 24  nose-to-lower-lip height
      (c.y - bm.y) / I, // 25  lower-lip-to-chin height
      hasContour ? faceMaxWidthNorm : (er.x - el.x).abs() / I, // 26  contour max width / interocular
      hasContour ? contourFaceHeight / I : box.height / I, // 27  contour face height / interocular
      jawRowWidthNorm, // 28  jaw row width (near mouth)
      foreheadRowWidthNorm, // 29  forehead row width
      faceMaxWidthNorm > 1e-9 ? jawRowWidthNorm / faceMaxWidthNorm : 0, // 30  jaw-to-max width ratio (face shape)
      faceMaxWidthNorm > 1e-9 ? foreheadRowWidthNorm / faceMaxWidthNorm : 0, // 31  forehead-to-max width ratio
    ];
  }

  /// Embedding of the average of [samples] (L2-normalized), used as the
  /// registered representative. Returns null when no valid sample exists.
  List<double>? meanEmbedding(List<List<double>> samples) {
    if (samples.isEmpty) return null;
    final dims = samples.first.length;
    final mean = List<double>.filled(dims, 0);
    for (final s in samples) {
      if (s.length != dims) return null;
      for (var i = 0; i < dims; i++) {
        mean[i] += s[i];
      }
    }
    for (var i = 0; i < dims; i++) {
      mean[i] /= samples.length;
    }
    final norm = _norm(mean);
    if (norm < 1e-9) return null;
    return [for (final v in mean) v / norm];
  }

  /// Identify an embedding against registered people.
  FaceRecognitionResult identify(
    List<double> embedding,
    List<FamiliarFace> people,
  ) {
    if (people.isEmpty) return const FaceRecognitionResult.unknown();

    double bestSim = -1;
    FamiliarFace? best;
    for (final person in people) {
      final sim = cosineSimilarity(embedding, person.embedding);
      print('FACE_DETECT_SIM ${person.name}: ${(sim * 100).toStringAsFixed(1)}%');
      if (sim > bestSim) {
        bestSim = sim;
        best = person;
      }
    }
    print('FACE_DETECT_SIM best: ${(bestSim * 100).toStringAsFixed(1)}% '
        'threshold: ${(similarityThreshold * 100).toStringAsFixed(1)}%');
    if (best == null || bestSim < similarityThreshold) {
      return const FaceRecognitionResult.unknown();
    }
    return FaceRecognitionResult.known(
      personId: best.id,
      personName: best.name,
      similarity: bestSim,
    );
  }

  /// Cosine similarity between two L2-normalized embeddings (0..1).
  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0;
    double dot = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    // Both inputs are expected unit-length; clamp for float noise.
    return dot.clamp(-1.0, 1.0);
  }

  double _norm(List<double> v) {
    double sum = 0;
    for (final x in v) {
      sum += x * x;
    }
    return math.sqrt(sum);
  }

  // ---------------------------------------------------------------
  // Alignment
  // ---------------------------------------------------------------

  _Aligned? _align(DetectedFace face) {
    // Mirrors in "right" landmarks so the embedding is symmetric regardless of
    // which way the person turned. Without this, "slightly left" and
    // "slightly right" registration samples would fight each other.
    final le = _mirror(face.leftEye);
    final re = _mirror(face.rightEye);
    final n = _mirror(face.noseBase);

    // Ears may be missing; fall back to the bounding-box sides at eye height.
    final eyeRowY = (le.y + re.y) / 2;
    final elRaw = face.leftEar ??
        FaceLandmarkPoint(face.boundingBox.left, eyeRowY);
    final erRaw = face.rightEar ??
        FaceLandmarkPoint(face.boundingBox.right, eyeRowY);
    final el = _mirror(elRaw);
    final er = _mirror(erRaw);
    // Mouth corners may be missing when the head is turned; fall back to
    // bounding-box estimates at the same row, like the ears.
    final w = face.boundingBox.width;
    final l = face.boundingBox.left;
    final mouthRowY =
        eyeRowY + (face.boundingBox.bottom - eyeRowY) * 0.48;
    final mlRaw = face.mouthLeft ??
        FaceLandmarkPoint(l + w * 0.35, mouthRowY);
    final mrRaw = face.mouthRight ??
        FaceLandmarkPoint(l + w * 0.65, mouthRowY);
    final ml = _mirror(mlRaw);
    final mr = _mirror(mrRaw);
    // Cheeks (bizygomatic points) sharpen face-shape discrimination. Fall
    // back to the box sides at a cheek-level row when ML Kit omits them.
    final cheekRowY = eyeRowY + (face.boundingBox.bottom - eyeRowY) * 0.33;
    final lcRaw = face.leftCheek ??
        FaceLandmarkPoint(face.boundingBox.left + w * 0.10, cheekRowY);
    final rcRaw = face.rightCheek ??
        FaceLandmarkPoint(face.boundingBox.left + w * 0.90, cheekRowY);
    final lc = _mirror(lcRaw);
    final rc = _mirror(rcRaw);
    // Bottom of the mouth (lower-lip center) gives the nose-to-lip height, a
    // stable vertical face feature.
    final bmRaw = face.bottomMouth ??
        FaceLandmarkPoint(l + w * 0.50, mouthRowY + (face.boundingBox.bottom - mouthRowY) * 0.10);
    final bm = _mirror(bmRaw);

    final eyeMid = FaceLandmarkPoint(
      (le.x + re.x) / 2,
      (le.y + re.y) / 2,
    );

    final theta = -face.rollDegrees * math.pi / 180;
    final cosT = math.cos(theta);
    final sinT = math.sin(theta);
    FaceLandmarkPoint rot(FaceLandmarkPoint p) {
      final dx = p.x - eyeMid.x;
      final dy = p.y - eyeMid.y;
      return FaceLandmarkPoint(
        eyeMid.x + dx * cosT - dy * sinT,
        eyeMid.y + dx * sinT + dy * cosT,
      );
    }

    final rle = rot(le);
    final rre = rot(re);
    final rn = rot(n);
    final rel = rot(el);
    final rer = rot(er);
    final rml = rot(ml);
    final rmr = rot(mr);
    final rlc = rot(lc);
    final rrc = rot(rc);
    final rbm = rot(bm);

    // Chin approximated without a bounding box (which inflates/rotates under
    // roll): we extend the nose-to-mouth-center direction past the mouth by a
    // fixed fraction. ML Kit exposes no chin landmark, so this stable,
    // landmark-only proxy keeps the embedding invariant to the box shape.
    final mouthMid = FaceLandmarkPoint((rml.x + rmr.x) / 2, (rml.y + rmr.y) / 2);
    final chin = FaceLandmarkPoint(
      mouthMid.x + _chinK * (mouthMid.x - rn.x),
      mouthMid.y + _chinK * (mouthMid.y - rn.y),
    );

    // Recentre on the eye midpoint so features are translation invariant.
    FaceLandmarkPoint relTo(FaceLandmarkPoint p) =>
        FaceLandmarkPoint(p.x - eyeMid.x, p.y - eyeMid.y);

    final interocular = _distance(rle, rre);
    if (interocular < 1e-6) return null;

    return _Aligned(
      interocular: interocular,
      nose: relTo(rn),
      mouthLeft: relTo(rml),
      mouthRight: relTo(rmr),
      leftEar: relTo(rel),
      rightEar: relTo(rer),
      leftCheek: relTo(rlc),
      rightCheek: relTo(rrc),
      bottomMouth: relTo(rbm),
      chin: relTo(chin),
      faceContour: [
        for (final p in face.faceContour) relTo(rot(_mirror(p))),
      ],
    );
  }

  /// Flips a keypoint horizontally (x -> 1-x) so left/right turns become
  /// equivalent during the "slightly different pose" registration sampling.
  FaceLandmarkPoint _mirror(FaceLandmarkPoint p) =>
      FaceLandmarkPoint(1 - p.x, p.y);

  double _distance(FaceLandmarkPoint a, FaceLandmarkPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class _Aligned {
  _Aligned({
    required this.interocular,
    required this.nose,
    required this.mouthLeft,
    required this.mouthRight,
    required this.leftEar,
    required this.rightEar,
    required this.leftCheek,
    required this.rightCheek,
    required this.bottomMouth,
    required this.chin,
    required this.faceContour,
  });

  final double interocular;
  final FaceLandmarkPoint nose;
  final FaceLandmarkPoint mouthLeft;
  final FaceLandmarkPoint mouthRight;
  final FaceLandmarkPoint leftEar;
  final FaceLandmarkPoint rightEar;
  final FaceLandmarkPoint leftCheek;
  final FaceLandmarkPoint rightCheek;
  final FaceLandmarkPoint bottomMouth;
  final FaceLandmarkPoint chin;

  /// Face outline points, mirrored + roll-aligned + eye-mid-centred (same
  /// frame as the other landmarks). May be empty when ML Kit produced none.
  final List<FaceLandmarkPoint> faceContour;
}