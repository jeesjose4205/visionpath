import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/depth_map.dart';
import '../../models/rgb_frame.dart';
import 'depth_engine.dart';

/// On-device, CPU-only, fully offline relative-depth estimator.
///
/// The engine combines two cheap, honest priors instead of a learned model:
///
/// 1. Geometric ground plane: assuming the camera is roughly level and the
///    viewing direction is horizontal, rows below a horizon row approach the
///    camera with a smooth curve. Cells above the horizon are "far".
/// 2. Texture energy: local luminance contrast in the walking band acts as a
///    weak cue for surfaces that break the floor plane (edges, clutter) even
///    when no object was classified.
///
/// Detected-object boxes strengthen the ground-plane cells they occupy, which
/// lets a box touching the bottom of the frame read as "very near".
///
/// IMPORTANT: every value is RELATIVE nearness in [0, 1] (1 = closest). This
/// is a coarse prior, NOT a calibrated distance estimate. Confidence is kept
/// intentionally low (see [nominalConfidence]).
class GeometricDepthEngine implements DepthEngine {
  static const int gridCols = 24;
  static const int gridRows = 32;

  /// Weight applied to detector-verified boxes when boosting cells.
  static const double _kBoxBoostCap = 0.92;

  /// Weight applied to texture-energy cells.
  static const double _kTextureWeight = 1.0;

  DepthEngineStatus _status = DepthEngineStatus.idle;

  @override
  DepthEngineStatus get status => _status;

  @override
  String get statusDetail => 'geometric ground-plane engine (relative depth)';

  @override
  double get nominalConfidence => 0.40;

  @override
  Future<bool> initialize() async {
    _status = DepthEngineStatus.ready;
    return true;
  }

  /// Relative nearness for a row fraction below the horizon.
  ///
  /// - r <= horizon        -> 0.0 (far)
  /// - r == 1 (bottom row) -> ~0.92 (very near to the camera)
  double _rowNearness(double rowFraction, double horizon) {
    if (rowFraction <= horizon) return 0.0;
    final double t =
        ((rowFraction - horizon) / (1.0 - horizon)).clamp(0.0, 1.0);
    return math.pow(t, 1.6).toDouble() * _kBoxBoostCap;
  }

  @override
  DepthMap inferDepth(
    RgbFrame frame, {
    DepthParams? params,
    List<Rect> objectBoxes = const [],
  }) {
    if (frame.isEmpty) return _emptyMap();

    final double horizon = (params?.horizonRow ?? DepthParams().horizonRow)
        .clamp(0.10, 0.70);

    final List<double> cells = List<double>.filled(gridCols * gridRows, 0.0);

    final Uint8List rgb = frame.rgb;
    final int width = frame.width;
    final int height = frame.height;

    // Detector boxes: precompute their boosted cell value once so the inner
    // loop stays cheap.
    final List<({int leftCol, int rightCol, int topRow, int bottomRow, double boost})>
        boxes = [];
    for (final Rect box in objectBoxes) {
      if (box.bottom <= horizon + 0.05) continue; // boxes above the horizon
      if (box.width <= 0 || box.height <= 0) continue;
      final double boost = _rowNearness(box.bottom.clamp(0.0, 1.0).toDouble(), horizon);
      if (boost <= 0.0) continue;
      boxes.add((
        leftCol: (box.left.clamp(0.0, 1.0) * (gridCols - 1)).round(),
        rightCol: (box.right.clamp(0.0, 1.0) * (gridCols - 1)).round(),
        topRow: (box.top.clamp(0.0, 1.0) * (gridRows - 1)).round(),
        bottomRow: (box.bottom.clamp(0.0, 1.0) * (gridRows - 1)).round(),
        boost: boost,
      ));
    }

    for (int row = 0; row < gridRows; row++) {
      final double ny = (row + 0.5) / gridRows;
      for (int col = 0; col < gridCols; col++) {
        final double nx = (col + 0.5) / gridCols;

        double value = _rowNearness(ny, horizon);

        // Texture energy: mean absolute vertical/horizontal luminance change
        // at the cell's pixel position, normalized to [0, 1].
        final int px =
            (nx * (width - 1)).round().clamp(0, width - 1);
        final int py =
            (ny * (height - 1)).round().clamp(0, height - 1);
        final double baseLum = _luminance(rgb, width, px, py);
        final double rightLum =
            _luminance(rgb, width, px + 1, py);
        final double downLum =
            _luminance(rgb, width, px, py + 1);
        final double energy =
            (((baseLum - rightLum).abs() + (baseLum - downLum).abs()) /
                    2.0 /
                    255.0)
                .clamp(0.0, 1.0);
        final double textured = energy * _kTextureWeight;
        if (textured > value) value = textured;

        // Detector-verified boxes boost cells they occupy.
        for (final box in boxes) {
          if (col < box.leftCol ||
              col > box.rightCol ||
              row < box.topRow ||
              row > box.bottomRow) {
            continue;
          }
          if (box.boost > value) value = box.boost;
        }

        cells[row * gridCols + col] = value.clamp(0.0, 1.0);
      }
    }

    return DepthMap(cols: gridCols, rows: gridRows, cells: cells);
  }

  double _luminance(Uint8List rgb, int width, int x, int y) {
    final int clampedX = x.clamp(0, width - 1);
    // The caller always clamps y; this is a cheap safety net for row reads.
    final int clampedY = y.clamp(0, (rgb.length ~/ (width * 3)) - 1);
    if (clampedY < 0) return 0.0;
    final int i = (clampedY * width + clampedX) * 3;
    // Guard against a buffer that is slightly short (never happens with a
    // valid RgbFrame, but keeps the loop panic-free).
    if (i + 2 >= rgb.length) return 0.0;
    return (rgb[i] + rgb[i + 1] + rgb[i + 2]) / 3.0;
  }

  DepthMap _emptyMap() => DepthMap(
        cols: gridCols,
        rows: gridRows,
        cells: List<double>.filled(gridCols * gridRows, 0.0),
      );

  @override
  void dispose() {
    _status = DepthEngineStatus.idle;
  }
}