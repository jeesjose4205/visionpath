import 'dart:math' as math;
import 'dart:typed_data';

/// Geometry that maps a detection from the model's 640x640 letterboxed input
/// back onto the original camera frame.
///
/// The model input is produced by [CurrencyDetector.preprocess], which scales
/// the frame down preserving aspect ratio and centres it on a square canvas
/// padded with [CurrencyDetector.padValue]. The inverse of that transform is
/// what turns a normalised input coordinate (0..1 across the 640 canvas) into a
/// normalised frame coordinate (0..1 across the original frame).
class LetterboxTransform {
  const LetterboxTransform({
    required this.frameWidth,
    required this.frameHeight,
    required this.inputSize,
    required this.scale,
    required this.padX,
    required this.padY,
    this.sourceLeft = 0,
    this.sourceTop = 0,
  });

  /// Size of the original frame the tensor was built from.
  final int frameWidth;
  final int frameHeight;

  /// Side length of the square model input (640).
  final int inputSize;

  /// Uniform factor the frame was scaled by before padding.
  final double scale;

  /// Left / top padding, in input pixels.
  final double padX;
  final double padY;

  /// Left / top edge of the source crop within the original frame, in frame
  /// pixels. Zero when the tensor was built from the whole frame.
  final double sourceLeft;
  final double sourceTop;

  /// Map an input-space x (0..inputSize) to a normalised frame x (0..1).
  double frameX(double inputX) =>
      ((((inputX - padX) / scale) + sourceLeft) / frameWidth).clamp(0.0, 1.0);

  /// Map an input-space y (0..inputSize) to a normalised frame y (0..1).
  double frameY(double inputY) =>
      ((((inputY - padY) / scale) + sourceTop) / frameHeight).clamp(0.0, 1.0);
}

/// A rectangular region of a camera frame that can be fed to the detector.
///
/// Notes are often small in a portrait camera frame, and letterboxing the whole
/// frame shrinks them further. Running the detector on a centred crop keeps the
/// note at a useful pixel size. [fraction] is the crop's side as a fraction of
/// the frame's shorter side; it is null for the full frame.
class CurrencyCrop {
  const CurrencyCrop._({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.fraction,
  });

  /// Full frame, no crop.
  const CurrencyCrop.fullFrame(int width, int height)
    : this._(left: 0, top: 0, width: width, height: height, fraction: null);

  /// Left / top edge in frame pixels.
  final int left;
  final int top;

  /// Crop size in frame pixels.
  final int width;
  final int height;

  /// Side length relative to the frame's shorter side, or null for the full
  /// frame.
  final double? fraction;

  bool get isFullFrame => fraction == null;

  @override
  String toString() =>
      'CurrencyCrop(${fraction == null ? 'full' : '${(fraction! * 100).round()}%'}, '
      '$left,$top ${width}x$height)';
}

/// One currency note located in a frame.
class CurrencyDetection {
  const CurrencyDetection({
    required this.denomination,
    required this.label,
    required this.classIndex,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Face value in whole rupees (e.g. 100 for a ₹100 note).
  final int denomination;

  /// The raw model class label this came from (e.g. `100IndianRupees`).
  final String label;

  /// The model's class index.
  final int classIndex;

  /// Detection confidence in the range 0..1.
  final double confidence;

  /// Bounding box in normalised frame coordinates (0..1), origin top-left.
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => math.max(0.0, right - left);
  double get height => math.max(0.0, bottom - top);
  double get area => width * height;

  @override
  String toString() =>
      'CurrencyDetection(₹$denomination, '
      '${(confidence * 100).toStringAsFixed(1)}%, '
      '[${left.toStringAsFixed(2)},${top.toStringAsFixed(2)},'
      '${right.toStringAsFixed(2)},${bottom.toStringAsFixed(2)}])';
}

/// Result of turning one camera frame into model input: the NHWC float tensor
/// plus the transform needed to map its output boxes back to the frame.
class LetterboxedInput {
  const LetterboxedInput(this.tensor, this.transform);

  /// `[1, 640, 640, 3]` NHWC, RGB, values scaled to 0..1, laid out as raw bytes
  /// ready for the interpreter.
  final Float32List tensor;
  final LetterboxTransform transform;
}

/// Pure-Dart preprocessing and output decoding for the bundled note detector.
///
/// The detector is a YOLOv10n note model exported to TFLite
/// (`assets/ml/currency_notes_yolo.tflite`). Its contract was verified from
/// the shipped FlatBuffer and its embedded Ultralytics metadata:
///
///  * input `[1, 640, 640, 3]` float32, NHWC, **RGB**, letterboxed with a grey
///    (114) pad and scaled to **0..1** — no normalisation is baked into the
///    graph, so the caller divides by 255;
///  * output `[1, 300, 6]` float32, one row per candidate as
///    `x1, y1, x2, y2, confidence, class`. The box coordinates are **normalised
///    to 0..1** across the 640 canvas (the graph's decoded anchor coordinates
///    are scaled by 1/80 before the final top-300 selection). The final graph
///    concatenates `[1, 300, 4]` boxes, `[1, 300, 1]` scores and
///    `[1, 300, 1]` class IDs in that order. The exported head is marked
///    `end2end`, though overlapping duplicates are still possible, so [decode]
///    applies a final IoU suppression.
///
/// This class has no dependency on `tflite_flutter`, so every rule above is
/// unit-testable without a device or a bundled model.
class CurrencyDetector {
  CurrencyDetector({List<String>? labels})
    : labels = List<String>.unmodifiable(labels ?? defaultLabels) {
    for (final String label in this.labels) {
      final int? denomination = denominationFromLabel(label);
      _denominations.add(
        supportedDenominationValues.contains(denomination)
            ? denomination
            : null,
      );
    }
  }

  /// Default class order, matching the exported model's output indices. A
  /// bundled `<asset>_labels.txt` sidecar overrides it; the order is exactly the
  /// model's, so it must not be reordered casually.
  static const List<String> defaultLabels = <String>[
    '100IndianRupees',
    '10IndianRupees',
    '200IndianRupees',
    '20IndianRupees',
    '500IndianRupees',
    '50IndianRupees',
    '5IndianRupees',
  ];

  /// Every denomination the verified model can report. This deliberately
  /// prevents a malformed label sidecar from making the app claim support for
  /// a currency the bundled model was not trained to recognise.
  static const Set<int> supportedDenominationValues = <int>{
    5,
    10,
    20,
    50,
    100,
    200,
    500,
  };

  /// Square model input side length.
  static const int inputSize = 640;

  /// Number of candidate rows in the end2end output.
  static const int numBoxes = 300;

  /// Floats per candidate row (`x1, y1, x2, y2, confidence, class`).
  static const int boxStride = 6;

  /// Exact shape of the verified model input. The runtime service validates
  /// this before inference rather than accepting a similarly-shaped model.
  static const List<int> inputShape = <int>[1, inputSize, inputSize, 3];

  /// Exact shape of the verified model output.
  static const List<int> outputShape = <int>[1, numBoxes, boxStride];

  /// Grey value used for letterbox padding, matching the Ultralytics training
  /// preprocessing (`cv2` border 114).
  static const int padValue = 114;

  /// Lowest confidence [decode] will even consider. A separate, usually higher
  /// acceptance threshold is applied by the service.
  static const double confidenceFloor = 0.25;

  /// IoU above which a lower-confidence overlapping box is suppressed.
  static const double defaultIouThreshold = 0.55;

  final List<String> labels;
  final List<int?> _denominations = <int?>[];

  /// Whether [labels] is exactly the class order embedded in the shipped
  /// detector. Class order is part of a detector contract, not presentation
  /// text, so a reordered sidecar must never be used for inference.
  static bool hasExpectedLabelOrder(List<String> labels) {
    if (labels.length != defaultLabels.length) return false;
    for (int i = 0; i < labels.length; i++) {
      if (labels[i] != defaultLabels[i]) return false;
    }
    return true;
  }

  /// Face value per class index, same order as [labels]. Null entries are
  /// classes whose label carries no denomination; detections of those are
  /// dropped rather than guessed at.
  List<int?> get denominations => List<int?>.unmodifiable(_denominations);

  /// Crops to try in order: the full frame first, then centred squares from
  /// coarsest to tightest.
  ///
  /// A note that fills the frame is detected on the full frame. Smaller notes
  /// need progressively tighter square crops, because the full-frame letterbox
  /// can shrink a note below the detector's usable size. The order matters:
  /// the service accepts the first crop that clears the threshold, so a tight
  /// crop that hallucinates a denomination can never override a confident
  /// coarse one.
  static List<CurrencyCrop> centerCrops(int width, int height) {
    if (width <= 0 || height <= 0) return const <CurrencyCrop>[];

    final List<CurrencyCrop> crops = <CurrencyCrop>[
      CurrencyCrop.fullFrame(width, height),
    ];
    final int shortSide = math.min(width, height);
    const List<double> fractions = <double>[0.8, 0.6, 0.45, 0.35, 0.3];
    int? previousSide;
    for (final double fraction in fractions) {
      final int side = (shortSide * fraction).round().clamp(1, shortSide);
      if (side == previousSide) continue;
      previousSide = side;
      crops.add(
        CurrencyCrop._(
          left: (width - side) ~/ 2,
          top: (height - side) ~/ 2,
          width: side,
          height: side,
          fraction: fraction,
        ),
      );
    }
    return crops;
  }

  /// Scale one frame (`rgba`, `width` x `height`, 4 bytes per pixel) into the
  /// model's `[1, 640, 640, 3]` NHWC float tensor.
  ///
  /// The source is scaled uniformly to fit 640x640 and centred on a grey pad,
  /// exactly as the training pipeline did. [crop] limits sampling to a region
  /// of the frame while keeping coordinates relative to the whole frame.
  /// Returns null for a degenerate frame or an out-of-bounds crop.
  static LetterboxedInput? preprocess(
    Uint8List rgba,
    int width,
    int height, {
    CurrencyCrop? crop,
  }) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      return null;
    }

    final int sourceLeft = crop?.left ?? 0;
    final int sourceTop = crop?.top ?? 0;
    final int sourceWidth = crop?.width ?? width;
    final int sourceHeight = crop?.height ?? height;
    if (sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        sourceLeft < 0 ||
        sourceTop < 0 ||
        sourceLeft + sourceWidth > width ||
        sourceTop + sourceHeight > height) {
      return null;
    }

    final double scale = math.min(
      inputSize / sourceWidth,
      inputSize / sourceHeight,
    );
    final int newW = (sourceWidth * scale).round().clamp(1, inputSize);
    final int newH = (sourceHeight * scale).round().clamp(1, inputSize);
    final int padX = (inputSize - newW) ~/ 2;
    final int padY = (inputSize - newH) ~/ 2;
    final int sourceRight = sourceLeft + sourceWidth;
    final int sourceBottom = sourceTop + sourceHeight;

    final Float32List tensor = Float32List(inputSize * inputSize * 3);
    final double pad = padValue / 255.0;
    tensor.fillRange(0, tensor.length, pad);

    for (int v = 0; v < newH; v++) {
      final double sy = (v + 0.5) / scale - 0.5;
      final int y0 = sy.floor();
      final double fy = sy - y0;
      final int y0c = (sourceTop + y0).clamp(sourceTop, sourceBottom - 1);
      final int y1c = (sourceTop + y0 + 1).clamp(sourceTop, sourceBottom - 1);
      final int rowBase = ((padY + v) * inputSize + padX) * 3;
      for (int u = 0; u < newW; u++) {
        final double sx = (u + 0.5) / scale - 0.5;
        final int x0 = sx.floor();
        final double fx = sx - x0;
        final int x0c = (sourceLeft + x0).clamp(sourceLeft, sourceRight - 1);
        final int x1c = (sourceLeft + x0 + 1).clamp(
          sourceLeft,
          sourceRight - 1,
        );

        final int c00 = (y0c * width + x0c) * 4;
        final int c10 = (y0c * width + x1c) * 4;
        final int c01 = (y1c * width + x0c) * 4;
        final int c11 = (y1c * width + x1c) * 4;

        final int out = rowBase + u * 3;
        for (int ch = 0; ch < 3; ch++) {
          final double value =
              rgba[c00 + ch] * (1 - fx) * (1 - fy) +
              rgba[c10 + ch] * fx * (1 - fy) +
              rgba[c01 + ch] * (1 - fx) * fy +
              rgba[c11 + ch] * fx * fy;
          tensor[out + ch] = value / 255.0;
        }
      }
    }

    return LetterboxedInput(
      tensor,
      LetterboxTransform(
        frameWidth: width,
        frameHeight: height,
        inputSize: inputSize,
        scale: scale,
        padX: padX.toDouble(),
        padY: padY.toDouble(),
        sourceLeft: sourceLeft.toDouble(),
        sourceTop: sourceTop.toDouble(),
      ),
    );
  }

  /// Decode a raw `[1, 300, 6]` output tensor into a de-duplicated, ordered list
  /// of detections.
  ///
  /// Rows below [confidenceThreshold] are dropped, as are rows whose class has
  /// no denomination. Coordinates are mapped back onto the frame when
  /// [transform] is given (otherwise left normalised to the 640 canvas). The
  /// result is sorted by confidence, highest first, after IoU suppression.
  List<CurrencyDetection> decode(
    Float32List raw, {
    LetterboxTransform? transform,
    double confidenceThreshold = confidenceFloor,
    double iouThreshold = defaultIouThreshold,
  }) {
    if (raw.length < numBoxes * boxStride) return const <CurrencyDetection>[];

    final List<CurrencyDetection> candidates = <CurrencyDetection>[];
    for (int i = 0; i < numBoxes; i++) {
      final int b = i * boxStride;
      final double confidence = raw[b + 4];
      if (!confidence.isFinite ||
          confidence < confidenceThreshold ||
          confidence > 1.0) {
        continue;
      }

      final double rawClass = raw[b + 5];
      if (!rawClass.isFinite) continue;
      final int cls = rawClass.round();
      // The verified graph obtains this float by casting an integer class ID.
      // Do not turn an arbitrary malformed value such as 0.49 into class 0.
      if ((rawClass - cls).abs() > 1e-3) continue;
      if (cls < 0 || cls >= labels.length) continue;
      final int? denomination = _denominations[cls];
      if (denomination == null) continue;

      double x1 = raw[b] * inputSize;
      double y1 = raw[b + 1] * inputSize;
      double x2 = raw[b + 2] * inputSize;
      double y2 = raw[b + 3] * inputSize;
      if (!x1.isFinite ||
          !y1.isFinite ||
          !x2.isFinite ||
          !y2.isFinite ||
          x2 <= x1 ||
          y2 <= y1) {
        continue;
      }

      final double left = transform == null
          ? (x1 / inputSize)
          : transform.frameX(x1);
      final double top = transform == null
          ? (y1 / inputSize)
          : transform.frameY(y1);
      final double right = transform == null
          ? (x2 / inputSize)
          : transform.frameX(x2);
      final double bottom = transform == null
          ? (y2 / inputSize)
          : transform.frameY(y2);
      // A box wholly in the letterbox border maps to no source-frame area.
      if (right <= left || bottom <= top) continue;

      candidates.add(
        CurrencyDetection(
          denomination: denomination,
          label: labels[cls],
          classIndex: cls,
          confidence: confidence,
          left: left,
          top: top,
          right: right,
          bottom: bottom,
        ),
      );
    }

    final List<CurrencyDetection> kept = _suppressOverlaps(
      candidates,
      iouThreshold,
    );
    kept.sort(
      (CurrencyDetection a, CurrencyDetection b) =>
          b.confidence.compareTo(a.confidence),
    );
    return kept;
  }

  /// Highest-confidence detection, or null when the list is empty.
  static CurrencyDetection? best(List<CurrencyDetection> detections) {
    if (detections.isEmpty) return null;
    CurrencyDetection top = detections.first;
    for (final CurrencyDetection d in detections) {
      if (d.confidence > top.confidence) top = d;
    }
    return top;
  }

  /// Greedy non-maximum suppression. Class-agnostic on purpose: the same note
  /// can surface twice under different class scores, and the app only reports
  /// one denomination at a time.
  static List<CurrencyDetection> _suppressOverlaps(
    List<CurrencyDetection> boxes,
    double iouThreshold,
  ) {
    if (boxes.length <= 1) return List<CurrencyDetection>.of(boxes);
    final List<CurrencyDetection> sorted = List<CurrencyDetection>.of(boxes)
      ..sort(
        (CurrencyDetection a, CurrencyDetection b) =>
            b.confidence.compareTo(a.confidence),
      );
    final List<bool> removed = List<bool>.filled(sorted.length, false);
    final List<CurrencyDetection> kept = <CurrencyDetection>[];
    for (int i = 0; i < sorted.length; i++) {
      if (removed[i]) continue;
      kept.add(sorted[i]);
      for (int j = i + 1; j < sorted.length; j++) {
        if (removed[j]) continue;
        if (_iou(sorted[i], sorted[j]) > iouThreshold) removed[j] = true;
      }
    }
    return kept;
  }

  static double _iou(CurrencyDetection a, CurrencyDetection b) {
    final double interLeft = math.max(a.left, b.left);
    final double interTop = math.max(a.top, b.top);
    final double interRight = math.min(a.right, b.right);
    final double interBottom = math.min(a.bottom, b.bottom);
    final double interW = interRight - interLeft;
    final double interH = interBottom - interTop;
    if (interW <= 0 || interH <= 0) return 0;
    final double inter = interW * interH;
    final double union = a.area + b.area - inter;
    return union <= 0 ? 0 : inter / union;
  }

  static const Map<String, int> _wordNumbers = <String, int>{
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'twenty': 20,
    'fifty': 50,
    'hundred': 100,
    'two hundred': 200,
    'five hundred': 500,
    'two thousand': 2000,
  };

  /// Number words sorted longest-first, so "five hundred" resolves to 500
  /// rather than the "five" prefix and "two hundred" to 200 rather than "two".
  static final List<MapEntry<String, int>> _wordNumbersByLength =
      _wordNumbers.entries.toList()..sort(
        (MapEntry<String, int> a, MapEntry<String, int> b) =>
            b.key.length.compareTo(a.key.length),
      );

  /// Extract a rupee face value from a class label. Accepts "₹100", "100",
  /// "100 rupees", "100IndianRupees", "coin_10" and simple number words.
  /// Returns null when the label carries no denomination.
  static int? denominationFromLabel(String label) {
    final String lower = label.toLowerCase().trim();
    if (lower.isEmpty) return null;
    final RegExpMatch? digits = RegExp(r'\d+').firstMatch(lower);
    if (digits != null) {
      final int? value = int.tryParse(digits.group(0)!);
      if (value != null && value > 0) return value;
    }
    for (final MapEntry<String, int> e in _wordNumbersByLength) {
      if (lower.contains(e.key)) return e.value;
    }
    return null;
  }
}
