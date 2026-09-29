import 'dart:ui';

import '../../models/depth_map.dart';
import '../../models/rgb_frame.dart';

/// Lifecycle state of a depth engine.
enum DepthEngineStatus { idle, loading, ready, error }

/// Tuning parameters shared by all depth engines.
class DepthParams {
  /// Relative row fraction of the horizon (ground-plane assumption).
  /// Rows above the horizon are treated as "far"; rows below it follow the
  /// geometric nearness curve.
  final double horizonRow;

  const DepthParams({this.horizonRow = 0.40});
}

/// Abstraction over a relative-depth estimator.
///
/// A real neural model (MiDaS/DepthAnything via tflite, etc.) can be dropped
/// in behind this interface without touching the pipeline. The bundled
/// [GeometricDepthEngine] is the "most practical supported approach" for a
/// fully offline, lightweight, CPU-only build.
///
/// Every implementation produces a RELATIVE depth map (0..1 = far..near).
/// Nothing here ever produces metric distance.
abstract interface class DepthEngine {
  DepthEngineStatus get status;

  String get statusDetail;

  /// Baseline confidence of estimates from this engine (0..1). Real neural
  /// models would report calibration-driven numbers; the geometric prior is
  /// intentionally conservative.
  double get nominalConfidence;

  /// Prepare the engine (load model / allocate). Must be awaitable so a real
  /// model can be loaded asynchronously inside the same lifecycle.
  Future<bool> initialize();

  /// Produce a coarse relative depth map for [frame].
  ///
  /// [objectBoxes] carries normalized YOLO boxes so the engine can strengthen
  /// ground-plane cells occupied by detected objects. May be empty.
  DepthMap? inferDepth(
    RgbFrame frame, {
    DepthParams? params,
    List<Rect> objectBoxes = const [],
  });

  void dispose();
}