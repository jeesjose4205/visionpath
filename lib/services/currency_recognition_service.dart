import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/currency_recognition.dart';
import 'currency_detector.dart';

/// How a classification model expects its pixel input to be scaled before
/// inference.
///
/// This cannot be safely auto-detected from a `.tflite` file, so it is declared
/// per model. It is retained as a documented contract (and pinned by
/// [CurrencyRecognitionService.inputScalingFor]) for the retired classifier
/// models; the note detector that replaced them declares its own scaling in
/// [CurrencyDetector.preprocess].
enum CurrencyInputScaling {
  /// Raw 0..255 (models with preprocessing baked in, e.g. Keras MobileNet
  /// exported with `include_preprocessing=True`). Both retired classifier
  /// models were of this kind — they contained an internal
  /// `Rescaling(1/127.5, -1)` — so they had to be fed raw 0..255 values.
  raw,

  /// value / 255 -> [0, 1].
  zeroToOne,

  /// value / 127.5 - 1 -> [-1, 1] (ArcFace-style).
  minusOneToOne,

  /// ImageNet mean/std normalisation (0.485/0.456/0.406, 0.229/0.224/0.225).
  imageNet,
}

/// The input-scaling contract of one retired classifier model.
///
/// Kept only so the regression that broke the classifiers (pre-scaling a frame
/// that a model rescales internally) stays pinned by a test. The live recognizer
/// is the note detector, whose preprocessing is defined in [CurrencyDetector].
class _ClassifierInputContract {
  const _ClassifierInputContract(this.kind, this.inputScaling);

  final CurrencyKind kind;
  final CurrencyInputScaling inputScaling;
}

/// Where the recognizer is in its lifecycle.
enum CurrencyModelState { notLoaded, loading, ready, unavailable }

/// Outcome classification for one [CurrencyRecognitionService.analyze] call.
///
/// The screen maps these 1:1 onto what it shows, so every failure mode has an
/// explicit, distinguishable state instead of a silent `null`.
enum CurrencyInferenceStatus {
  /// A model produced an answer at or above the acceptance threshold.
  recognized,

  /// The model ran, but nothing cleared the threshold (or nothing usable came
  /// out of the model at all). The camera view is fine; the currency is not
  /// confidently identified yet.
  uncertain,

  /// No bundleable model is available for the requested [CurrencyKind]s.
  modelUnavailable,

  /// The frame itself was unusable (wrong size, too few bytes).
  invalidInput,

  /// The interpreter threw while running. Worth surfacing as a real error.
  inferenceError,

  /// Another frame is still being analysed; this one was dropped.
  busy,
}

/// Full result of analysing one frame, including why it did or did not
/// identify anything.
class CurrencyInferenceResult {
  const CurrencyInferenceResult._({
    required this.status,
    this.recognition,
    this.reason,
    this.labelsAssumed = false,
  });

  const CurrencyInferenceResult.recognized(
    CurrencyRecognition value, {
    bool labelsAssumed = false,
  }) : this._(
         status: CurrencyInferenceStatus.recognized,
         recognition: value,
         labelsAssumed: labelsAssumed,
       );

  const CurrencyInferenceResult.uncertain({String? reason})
    : this._(status: CurrencyInferenceStatus.uncertain, reason: reason);

  const CurrencyInferenceResult.modelUnavailable(String reason)
    : this._(status: CurrencyInferenceStatus.modelUnavailable, reason: reason);

  const CurrencyInferenceResult.invalidInput(String reason)
    : this._(status: CurrencyInferenceStatus.invalidInput, reason: reason);

  const CurrencyInferenceResult.inferenceError(String reason)
    : this._(status: CurrencyInferenceStatus.inferenceError, reason: reason);

  static const CurrencyInferenceResult busy = CurrencyInferenceResult._(
    status: CurrencyInferenceStatus.busy,
  );

  final CurrencyInferenceStatus status;

  /// Non-null only for [CurrencyInferenceStatus.recognized] and
  /// [CurrencyInferenceStatus.uncertain].
  final CurrencyRecognition? recognition;

  /// Human-readable explanation for any non-recognized outcome.
  final String? reason;

  /// True when the model used the built-in default label order instead of a
  /// bundled sidecar labels file.
  final bool labelsAssumed;

  bool get isRecognized => status == CurrencyInferenceStatus.recognized;
  bool get isUncertain => status == CurrencyInferenceStatus.uncertain;
  bool get isBusy => status == CurrencyInferenceStatus.busy;
}

/// A detector model that loaded successfully, with everything inference needs.
class _LoadedDetector {
  _LoadedDetector({
    required this.interpreter,
    required this.detector,
    required this.labelsAssumed,
  });

  final Interpreter interpreter;
  final CurrencyDetector detector;
  final bool labelsAssumed;
}

/// On-device Indian **banknote** recognition for low-vision users.
///
/// Recognition is performed by the bundled YOLOv10n note detector
/// (`assets/ml/currency_notes_yolo.tflite`). Each camera frame is searched from
/// the full frame inwards through progressively tighter centred crops, because
/// letterboxing a portrait frame can shrink a small note below the detector's
/// usable size. The first crop whose best detection clears [threshold] wins,
/// and its box is mapped back to frame coordinates. There is deliberately
/// **no** attempt at authenticity or counterfeit detection. The model runs
/// entirely offline and never leaves the device.
///
/// The service never fabricates a result. If the model asset is absent or fails
/// to load it is marked unavailable and [classify] returns `null`.
///
/// **Coins are not supported.** The bundled detector has banknote classes only
/// (₹5, ₹10, ₹20, ₹50, ₹100, ₹200, ₹500); there is no coin model, so
/// [supportedDenominations] reports nothing for [CurrencyKind.coin] and no coin
/// result is ever produced.
///
/// **Known limitation — non-currency rejection.** The detector is a closed-set
/// object detector: it has no background / "not currency" class. In independent
/// testing it assigned high confidence to some ordinary non-currency scenes
/// (e.g. a book at 0.87). [threshold] therefore only filters genuinely
/// low-confidence frames and cannot by itself stop a non-currency object from
/// being reported as a denomination. Reliable rejection requires a model trained
/// with an explicit background class; the confidence gate here is a best-effort
/// filter only and must not be presented as a working rejection guarantee.
class CurrencyRecognitionService {
  CurrencyRecognitionService({double? threshold})
    : threshold = threshold ?? defaultThreshold;

  /// Confidence a detection must reach before it is treated as an answer.
  static const double defaultThreshold = 0.60;

  /// The bundled note detector, and its optional label sidecar.
  static const String detectorAsset = 'assets/ml/currency_notes_yolo.tflite';
  static const String detectorLabelsAsset =
      'assets/ml/currency_notes_yolo_labels.txt';

  static const List<double> _imagenetMean = <double>[0.485, 0.456, 0.406];
  static const List<double> _imagenetStd = <double>[0.229, 0.224, 0.225];

  /// Retired classifier contracts. Both models baked in `Rescaling(1/127.5, -1)`
  /// and therefore had to be fed raw 0..255, not pre-normalised input. Kept so
  /// the double-normalisation regression stays documented and tested.
  static const List<_ClassifierInputContract> _retiredContracts =
      <_ClassifierInputContract>[
        _ClassifierInputContract(
          CurrencyKind.banknote,
          CurrencyInputScaling.raw,
        ),
        _ClassifierInputContract(CurrencyKind.coin, CurrencyInputScaling.raw),
      ];

  /// Acceptance threshold applied to [CurrencyRecognition.reliable].
  double threshold;

  /// Opt-in, off by default. Emits per-frame diagnostics: frame geometry and
  /// letterbox numbers, the top candidate rows *before* the confidence filter,
  /// and why the winning detection was accepted or rejected.
  ///
  /// Tests and the debug probe flip this on; production stays silent, and no
  /// sub-threshold candidate is ever announced to the user.
  @visibleForTesting
  static bool debugDiagnostics = false;

  // The interpreter is cached statically because loading a multi-megabyte model
  // is expensive and the screen can be opened repeatedly. The cache is process
  // wide and intentionally never evicted except by [closeAll].
  static _LoadedDetector? _detector;
  static String? _detectorLoadError;
  static Future<void>? _loadFuture;
  static bool _loadedOnce = false;
  static String? _loadError;
  static bool _analysisInFlight = false;

  bool get loaded => _loadedOnce;

  /// True when the note detector is loaded. [CurrencyKind.banknote] results are
  /// produced by it.
  bool get hasBanknoteModel => _detector != null;

  /// Always false: the bundled detector cannot recognise coins.
  bool get hasCoinModel => false;

  bool get anyModelAvailable => _detector != null;

  /// True when the detector fell back to the built-in default label order.
  bool get labelsAssumed => _detector?.labelsAssumed ?? false;

  /// Current lifecycle state, for the screen's loading / error UI.
  CurrencyModelState get state {
    if (!_loadedOnce) {
      return _loadFuture == null
          ? CurrencyModelState.notLoaded
          : CurrencyModelState.loading;
    }
    if (anyModelAvailable) return CurrencyModelState.ready;
    return CurrencyModelState.unavailable;
  }

  /// Human-readable reason when no model could be loaded, else null.
  String? get loadError => _loadError;

  /// Why [kind]'s model is unavailable, or null when it is available.
  String? kindLoadError(CurrencyKind kind) {
    if (kind == CurrencyKind.banknote && _detector != null) return null;
    if (kind == CurrencyKind.coin) {
      return 'Coins are not supported by the bundled note detector.';
    }
    return _detectorLoadError ??
        _loadError ??
        'No banknote model is bundled with this build.';
  }

  /// Face values the loaded [kind] model can recognise, or null when that kind
  /// has no model. Used to tell the user what is actually supportable instead of
  /// implying full coverage.
  List<int>? supportedDenominations(CurrencyKind kind) {
    if (kind != CurrencyKind.banknote) return null;
    final _LoadedDetector? model = _detector;
    if (model == null) return null;
    return List<int>.unmodifiable(
      model.detector.denominations.whereType<int>(),
    );
  }

  /// Loads the bundled note detector once. Safe to call repeatedly.
  Future<void> ensureLoaded() async {
    if (_loadedOnce) return;
    _loadFuture ??= _loadAll();
    await _loadFuture!;
  }

  /// Discards the static model cache and loads again.
  ///
  /// Needed because a failed load is cached for the life of the process
  /// otherwise: a build that ships without the model cannot be fixed by the
  /// user until the app restarts.
  Future<void> reload() async {
    await closeAll();
    await ensureLoaded();
  }

  /// Closes the open interpreter and clears the process-wide cache.
  @visibleForTesting
  static Future<void> closeAll() async {
    try {
      _detector?.interpreter.close();
    } catch (e) {
      print('CURRENCY_MODEL_CLOSE_FAILED error=$e');
    }
    _detector = null;
    _detectorLoadError = null;
    _loadError = null;
    _loadedOnce = false;
    _loadFuture = null;
    _analysisInFlight = false;
  }

  static Future<void> _loadAll() async {
    try {
      _detector = await _loadDetector();
    } catch (e) {
      _detector = null;
      _detectorLoadError = 'failed to load ($e)';
    }
    if (_detector == null) {
      _detectorLoadError ??= 'not bundled';
      _loadError =
          'No currency recognition model is bundled with this build. '
          '(notes detector: $_detectorLoadError)';
    }
    _loadedOnce = true;
    _loadFuture = null;
  }

  static Future<_LoadedDetector?> _loadDetector() async {
    try {
      final Interpreter interpreter = await Interpreter.fromAsset(
        detectorAsset,
      );
      interpreter.allocateTensors();

      void rejectModel(String reason) {
        _detectorLoadError = reason;
        try {
          interpreter.close();
        } catch (_) {
          // The original contract failure is the useful error to preserve.
        }
      }

      final Tensor input = interpreter.getInputTensor(0);
      final List<int> inShape = input.shape;
      if (!_sameShape(inShape, CurrencyDetector.inputShape)) {
        rejectModel(
          'input tensor shape $inShape is not ${CurrencyDetector.inputShape}',
        );
        return null;
      }
      if (input.type != TensorType.float32) {
        rejectModel('unsupported input type ${input.type}');
        return null;
      }
      final int expectedInputBytes =
          CurrencyDetector.inputSize * CurrencyDetector.inputSize * 3 * 4;
      if (input.numBytes() != expectedInputBytes) {
        rejectModel(
          'input tensor byte size ${input.numBytes()} is not '
          '$expectedInputBytes for float32 RGB input',
        );
        return null;
      }

      final Tensor output = interpreter.getOutputTensor(0);
      final List<int> outShape = output.shape;
      if (!_sameShape(outShape, CurrencyDetector.outputShape)) {
        rejectModel(
          'output tensor shape $outShape is not '
          '${CurrencyDetector.outputShape} detection head',
        );
        return null;
      }
      if (output.type != TensorType.float32) {
        rejectModel('unsupported output type ${output.type}');
        return null;
      }
      final int expectedOutputBytes =
          CurrencyDetector.numBoxes * CurrencyDetector.boxStride * 4;
      if (output.numBytes() != expectedOutputBytes) {
        rejectModel(
          'output tensor byte size ${output.numBytes()} is not '
          '$expectedOutputBytes for float32 detector output',
        );
        return null;
      }

      final _LabelsLoad labelsLoad = await _loadLabels();
      final CurrencyDetector detector = CurrencyDetector(
        labels: labelsLoad.labels,
      );

      print(
        'CURRENCY_MODEL_LOADED asset=$detectorAsset '
        'input=${inShape[1]}x${inShape[2]} boxes=${outShape[1]} '
        'labels=${labelsLoad.labels.length} '
        'labelsAssumed=${labelsLoad.assumed}',
      );

      return _LoadedDetector(
        interpreter: interpreter,
        detector: detector,
        labelsAssumed: labelsLoad.assumed,
      );
    } catch (e) {
      _detectorLoadError = 'failed to load ($e)';
      return null;
    }
  }

  static Future<_LabelsLoad> _loadLabels() async {
    try {
      final String raw = await rootBundle.loadString(detectorLabelsAsset);
      final List<String> labels = raw
          .split('\n')
          .map((String l) => l.trim())
          .where((String l) => l.isNotEmpty)
          .toList();
      if (CurrencyDetector.hasExpectedLabelOrder(labels)) {
        return _LabelsLoad(labels, assumed: false);
      }
      print(
        'CURRENCY_LABELS_INVALID: expected the verified seven-class '
        'order; using the embedded default mapping instead.',
      );
    } catch (_) {
      // Sidecar is optional; fall through to the documented default order.
    }
    return _LabelsLoad(CurrencyDetector.defaultLabels, assumed: true);
  }

  static bool _sameShape(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    for (int i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) return false;
    }
    return true;
  }

  /// Analyse one upright portrait RGBA frame and return the winning
  /// recognition, or null for every non-recognized outcome.
  Future<CurrencyRecognition?> classify(
    Uint8List rgba,
    int width,
    int height, {
    Set<CurrencyKind>? kinds,
  }) async {
    final CurrencyInferenceResult result = await analyze(
      rgba,
      width,
      height,
      kinds: kinds,
    );
    return result.recognition;
  }

  /// Analyse one upright portrait RGBA frame and report why it did or did not
  /// identify a denomination.
  ///
  /// A frame that is still being processed by a previous call is dropped with
  /// [CurrencyInferenceStatus.busy] so the camera stream cannot queue up behind
  /// a slow interpreter.
  Future<CurrencyInferenceResult> analyze(
    Uint8List rgba,
    int width,
    int height, {
    Set<CurrencyKind>? kinds,
  }) async {
    if (_analysisInFlight) return CurrencyInferenceResult.busy;
    _analysisInFlight = true;
    try {
      return await _analyze(rgba, width, height, kinds);
    } finally {
      _analysisInFlight = false;
    }
  }

  Future<CurrencyInferenceResult> _analyze(
    Uint8List rgba,
    int width,
    int height,
    Set<CurrencyKind>? kinds,
  ) async {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      return CurrencyInferenceResult.invalidInput(
        'frame is ${width}x$height with ${rgba.length} bytes',
      );
    }

    final Set<CurrencyKind> wanted =
        kinds ?? const <CurrencyKind>{CurrencyKind.banknote, CurrencyKind.coin};

    final _LoadedDetector? loaded = _detector;
    final bool canDetect =
        wanted.contains(CurrencyKind.banknote) && loaded != null;
    if (!canDetect) {
      final String missing = wanted.map((CurrencyKind k) => k.name).join(', ');
      return CurrencyInferenceResult.modelUnavailable(
        'No model available for: $missing. ${_loadError ?? ''}'.trim(),
      );
    }

    final List<CurrencyCrop> crops = CurrencyDetector.centerCrops(
      width,
      height,
    );
    if (crops.isEmpty) {
      return CurrencyInferenceResult.invalidInput(
        'could not prepare detector input for ${width}x$height',
      );
    }

    final Float32List output = Float32List(
      CurrencyDetector.numBoxes * CurrencyDetector.boxStride,
    );
    CurrencyDetection? accepted;
    CurrencyDetection? bestBelowThreshold;
    for (final CurrencyCrop crop in crops) {
      final LetterboxedInput? input = CurrencyDetector.preprocess(
        rgba,
        width,
        height,
        crop: crop,
      );
      if (input == null) continue;

      output.fillRange(0, output.length, 0);
      try {
        loaded.interpreter.run(
          input.tensor.buffer.asUint8List(
            input.tensor.offsetInBytes,
            input.tensor.lengthInBytes,
          ),
          output.buffer.asUint8List(output.offsetInBytes, output.lengthInBytes),
        );
      } catch (e) {
        print('CURRENCY_INFERENCE_ERROR asset=$detectorAsset error=$e');
        return CurrencyInferenceResult.inferenceError('inference failed: $e');
      }

      final List<CurrencyDetection> detections = loaded.detector.decode(
        output,
        transform: input.transform,
      );
      if (debugDiagnostics) {
        _logDiagnostics(
          loaded,
          input.transform,
          output,
          detections,
          threshold,
          crop: crop,
        );
      }
      final CurrencyDetection? candidate = CurrencyDetector.best(detections);
      if (candidate == null) continue;

      if (candidate.confidence >= threshold) {
        accepted = candidate;
        if (debugDiagnostics) {
          print(
            'CURRENCY_DEBUG_ACCEPTED_CROP crop=$crop '
            'conf=${candidate.confidence.toStringAsFixed(4)} '
            'denom=${candidate.denomination}',
          );
        }
        break;
      }
      if (bestBelowThreshold == null ||
          candidate.confidence > bestBelowThreshold.confidence) {
        bestBelowThreshold = candidate;
      }
    }

    final CurrencyDetection? best = accepted ?? bestBelowThreshold;
    if (best == null) {
      return const CurrencyInferenceResult.uncertain();
    }

    final CurrencyRecognition recognition = CurrencyRecognition(
      kind: CurrencyKind.banknote,
      denomination: best.denomination,
      confidence: best.confidence,
      reliable: best.confidence >= threshold,
    );
    if (recognition.reliable) {
      return CurrencyInferenceResult.recognized(
        recognition,
        labelsAssumed: labelsAssumed,
      );
    }
    return CurrencyInferenceResult.uncertain(
      reason:
          'Confidence ${recognition.confidencePercent}% is below the '
          '${(threshold * 100).round()}% threshold',
    );
  }

  /// Diagnostic dump for one inference. Never announced to the user.
  ///
  /// The "before" view uses a near-zero confidence floor so rows the real
  /// filter would drop are still visible; exact-zero rows (the unused tail of
  /// the 300-row output) are excluded by that floor.
  static void _logDiagnostics(
    _LoadedDetector model,
    LetterboxTransform transform,
    Float32List output,
    List<CurrencyDetection> filtered,
    double threshold, {
    CurrencyCrop? crop,
  }) {
    final List<CurrencyDetection> all = model.detector.decode(
      output,
      transform: transform,
      confidenceThreshold: 1e-4,
    );
    final CurrencyDetection? bestAll = CurrencyDetector.best(all);
    final CurrencyDetection? best = CurrencyDetector.best(filtered);

    print(
      'CURRENCY_DEBUG_FRAME crop=${crop ?? 'full'} frame='
      '${transform.frameWidth}x${transform.frameHeight} '
      'input=${transform.inputSize} scale=${transform.scale.toStringAsFixed(4)} '
      'sourceLeft=${transform.sourceLeft} sourceTop=${transform.sourceTop} '
      'padX=${transform.padX} padY=${transform.padY} threshold=$threshold '
      'labelsAssumed=${model.labelsAssumed}',
    );
    print(
      'CURRENCY_DEBUG_CANDIDATES crop=${crop ?? 'full'} '
      'rowsAboveZero=${all.length} keptAfterFloor=${filtered.length}',
    );
    for (int i = 0; i < all.length && i < 5; i++) {
      final CurrencyDetection d = all[i];
      print(
        'CURRENCY_DEBUG_CAND[$i] cls=${d.classIndex} label=${d.label} '
        'denom=${d.denomination} conf=${d.confidence.toStringAsFixed(4)} '
        'box=${d.left.toStringAsFixed(3)},${d.top.toStringAsFixed(3)},'
        '${d.right.toStringAsFixed(3)},${d.bottom.toStringAsFixed(3)}',
      );
    }

    if (bestAll == null) {
      print('CURRENCY_DEBUG_BEST_BEFORE none');
      print(
        'CURRENCY_DEBUG_REJECTED reason=no_candidate '
        'floor=${CurrencyDetector.confidenceFloor}',
      );
      return;
    }

    print(
      'CURRENCY_DEBUG_BEST_BEFORE conf=${bestAll.confidence.toStringAsFixed(4)} '
      'cls=${bestAll.classIndex} denom=${bestAll.denomination} '
      'label=${bestAll.label} acceptedByFloor='
      '${filtered.isNotEmpty && best!.classIndex == bestAll.classIndex}',
    );
    if (bestAll.confidence < threshold) {
      print(
        'CURRENCY_DEBUG_BEST_AFTER rejected conf='
        '${bestAll.confidence.toStringAsFixed(4)} threshold=$threshold '
        'denom=${bestAll.denomination}',
      );
      print(
        'CURRENCY_DEBUG_REJECTED reason=below_threshold conf='
        '${bestAll.confidence.toStringAsFixed(4)} threshold=$threshold '
        'gap=${(threshold - bestAll.confidence).toStringAsFixed(4)}',
      );
    } else {
      print(
        'CURRENCY_DEBUG_BEST_AFTER accepted conf='
        '${bestAll.confidence.toStringAsFixed(4)} denom=${bestAll.denomination} '
        'screenDenom=${best?.denomination}',
      );
    }
  }

  static double _scaleValue(double raw, int channel, CurrencyInputScaling s) {
    switch (s) {
      case CurrencyInputScaling.raw:
        return raw;
      case CurrencyInputScaling.zeroToOne:
        return raw / 255.0;
      case CurrencyInputScaling.minusOneToOne:
        return raw / 127.5 - 1.0;
      case CurrencyInputScaling.imageNet:
        return (raw / 255.0 - _imagenetMean[channel]) / _imagenetStd[channel];
    }
  }

  /// The input scaling declared for [kind]'s retired classifier model.
  ///
  /// Exposed so a test can pin the preprocessing contract: both retired models
  /// baked in `Rescaling(1/127.5, -1)` and had to be fed raw 0..255.
  @visibleForTesting
  static CurrencyInputScaling inputScalingFor(CurrencyKind kind) {
    for (final _ClassifierInputContract c in _retiredContracts) {
      if (c.kind == kind) return c.inputScaling;
    }
    return CurrencyInputScaling.raw;
  }

  /// Apply [s] to one 0..255 channel value. Exposed for tests so the scaling
  /// maths is verified without a bundled model.
  @visibleForTesting
  static double applyScaling(double raw, int channel, CurrencyInputScaling s) =>
      _scaleValue(raw, channel, s);

  /// Interpret a raw classification output as probabilities.
  ///
  /// Retained from the classifier path: if the values already look like a
  /// probability distribution they are used as-is, otherwise a stable softmax
  /// is applied.
  @visibleForTesting
  static List<double> toProbabilities(List<double> raw) {
    double sum = 0;
    double maxVal = double.negativeInfinity;
    bool inRange = true;
    for (final double v in raw) {
      if (v < -1e-4 || v > 1.0001) inRange = false;
      if (v > maxVal) maxVal = v;
      sum += v;
    }
    if (inRange && (sum - 1.0).abs() < 0.05) return raw;

    final List<double> exps = List<double>.filled(raw.length, 0);
    double expSum = 0;
    for (int i = 0; i < raw.length; i++) {
      final double e = math.exp(raw[i] - maxVal);
      exps[i] = e;
      expSum += e;
    }
    if (expSum <= 0) return raw;
    for (int i = 0; i < exps.length; i++) {
      exps[i] /= expSum;
    }
    return exps;
  }

  /// Extract a rupee face value from a class label. Delegates to
  /// [CurrencyDetector.denominationFromLabel].
  @visibleForTesting
  static int? denominationFromLabel(String label) =>
      CurrencyDetector.denominationFromLabel(label);
}

/// Labels loaded for the detector, plus whether they came from the built-in
/// default order rather than a bundled sidecar file.
class _LabelsLoad {
  const _LabelsLoad(this.labels, {required this.assumed});

  final List<String> labels;
  final bool assumed;
}
