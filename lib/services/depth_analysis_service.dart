import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../models/app_settings.dart';
import '../models/depth_map.dart';
import '../models/depth_result.dart';
import '../models/depth_scene.dart';
import '../models/detected_object.dart';
import '../models/proximity_level.dart';
import '../models/rgb_frame.dart';
import 'depth/depth_engine.dart';
import 'depth/depth_metric_calibration.dart';
import 'depth/geometric_depth_engine.dart';
import 'settings_service.dart';

/// DepthAnalysisService turns camera frames + detections into a RELATIVE
/// depth scene.
///
/// Two operating paths:
///   1. Real depth: asks the active [DepthEngine] for a coarse depth map,
///      associates each object with the map (robust inner-box sampling),
///      assesses LEFT / CENTER / RIGHT walking regions, finds depth-only
///      ("unknown") obstacles, and applies temporal smoothing.
///   2. Fallback: the legacy box-area heuristic, used whenever depth is
///      unavailable or disabled. The camera stream is NEVER blocked by depth.
///
/// Every value produced without calibration is relative (0..1 nearness).
/// [DepthResult.estimatedDistance] is populated ONLY by the enabled metric
/// calibration (a calibrated estimate, never a fabricated measurement); when
/// calibration is off or out of range it stays null.
class DepthAnalysisService {
  // ------------------------------------------------------------------
  // Legacy heuristic (kept intact so other screens keep working)
  // ------------------------------------------------------------------

  static double _sensitivityScale(ObstacleSensitivity s) {
    switch (s) {
      case ObstacleSensitivity.low:
        return 1.25;
      case ObstacleSensitivity.medium:
        return 1.0;
      case ObstacleSensitivity.high:
        return 0.8;
    }
  }

  /// Legacy: estimate proximity from a normalized bounding box.
  static ProximityLevel estimateProximity(Rect box) {
    final double width = box.width;
    final double height = box.height;
    final double area = width * height;
    final double s = _sensitivityScale(
      SettingsService.instance.obstacleSensitivity,
    );

    if (width > 0.70 * s || height > 0.85 * s) return ProximityLevel.veryNear;
    if (area >= 0.25 * s) return ProximityLevel.veryNear;
    if (area >= 0.12 * s) return ProximityLevel.near;
    if (area >= 0.05 * s) return ProximityLevel.medium;
    return ProximityLevel.far;
  }

  /// Legacy: enrich [objects] with area-based proximity levels only.
  List<DetectedObject> analyze(List<DetectedObject> objects) {
    final List<DetectedObject> enriched = [];
    for (final obj in objects) {
      final ProximityLevel level = estimateProximity(obj.boundingBox);
      print('DEPTH_ANALYSIS: ${obj.displayName} -> ${level.label} (approximate)');
      enriched.add(obj.copyWith(proximity: level));
    }
    print('DEPTH_ANALYSIS_DONE: ${enriched.length} objects');
    return enriched;
  }

  // ------------------------------------------------------------------
  // Engine lifecycle
  // ------------------------------------------------------------------

  static const int _historyLength = 3;

  /// Ground-plane horizon (relative row). Rows below it follow the geometric
  /// nearness curve; the walking band sits between [_kWalkingBandTop] and
  /// [_kWalkingBandBottom].
  static const double _kHorizon = 0.40;
  static const double _kWalkingBandTop = 0.50;
  static const double _kWalkingBandBottom = 0.88;

  /// Cells with nearness below this are considered open/clear.
  static const double _kClearCellNear = 0.60;

  /// Blocking thresholds (scaled by obstacle sensitivity).
  static const double _kBlockedNearest = 0.75;
  static const double _kBlockedOpenRatio = 0.40;
  static const double _kPartialNearest = 0.55;
  static const double _kPartialOpenRatio = 0.60;

  /// Proximity thresholds on relative depth (scaled by sensitivity).
  static const double _kVeryNear = 0.78;
  static const double _kNear = 0.55;
  static const double _kMedium = 0.34;

  DepthEngineStatus _engineStatus = DepthEngineStatus.idle;
  String _engineStatusDetail = 'not initialized';
  DepthEngine? _activeEngine;

  DepthScene? _lastScene;

  /// Temporal EM factor applied to per-object meter estimates so displayed
  /// distances move smoothly (~5 FPS pipeline, alpha tuned for ~0.7 s of
  /// memory).
  static const double _kDistanceSmoothing = 0.35;

  final Map<String, List<ProximityLevel>> _objectLevelWindow = {};
  final Map<String, ProximityLevel> _objectAppliedLevel = {};
  final Map<PathRegion, List<DepthBlockLevel>> _regionLevelWindow = {};
  final Map<String, double> _smoothedDistanceMeters = {};

  DepthEngineStatus get engineStatus => _engineStatus;
  String get engineStatusDetail => _engineStatusDetail;
  DepthEngine? get engine => _activeEngine;

  /// True when a depth engine is ready AND depth analysis is enabled in
  /// settings. When false, the pipeline runs the box-heuristic fallback.
  bool get engineUsable =>
      _engineStatus == DepthEngineStatus.ready &&
      SettingsService.instance.depthAnalysisEnabled;

  DepthScene? get lastScene => _lastScene;

  bool get usedFallback => _lastScene?.usedFallback ?? false;

  /// Load the depth engine. [engine] defaults to the bundled geometric
  /// engine; tests inject stubs. Never throws — failure is surfaced through
  /// [engineStatus] so the pipeline falls back gracefully.
  Future<bool> initialize({DepthEngine? engine}) async {
    _engineStatus = DepthEngineStatus.loading;
    _engineStatusDetail = 'loading depth engine...';
    print('DEPTH_INIT: starting');
    final DepthEngine chosen = engine ?? GeometricDepthEngine();
    _activeEngine = chosen;
    try {
      final bool ok = await chosen.initialize();
      if (ok && chosen.status == DepthEngineStatus.ready) {
        _engineStatus = DepthEngineStatus.ready;
        _engineStatusDetail = chosen.statusDetail;
        print('DEPTH_INIT: ready (${chosen.statusDetail})');
        return true;
      }
      _engineStatus = chosen.status == DepthEngineStatus.loading
          ? DepthEngineStatus.idle
          : chosen.status;
      _engineStatusDetail = chosen.statusDetail;
      print('DEPTH_INIT_FAILED: ${chosen.statusDetail}');
      return false;
    } catch (e) {
      _engineStatus = DepthEngineStatus.error;
      _engineStatusDetail = 'engine failed to initialize: $e';
      print('DEPTH_INIT_ERROR: $e');
      return false;
    }
  }

  /// Clear temporal smoothing state and the cached scene. Call when a
  /// navigation session starts or stops so history never leaks across runs.
  void reset() {
    _objectLevelWindow.clear();
    _objectAppliedLevel.clear();
    _regionLevelWindow.clear();
    _smoothedDistanceMeters.clear();
    _lastScene = null;
  }

  // ------------------------------------------------------------------
  // Scene analysis
  // ------------------------------------------------------------------

  /// Analyze a full frame: depth map -> regions -> object association ->
  /// unknown obstacles -> smoothing. Returns a complete [DepthScene].
  ///
  /// Falls back to the legacy heuristic whenever the engine is unavailable;
  /// never throws and never touches the camera stream lifecycle.
  Future<DepthScene> analyzeScene(
    RgbFrame frame,
    List<DetectedObject> objects,
  ) async {
    if (!engineUsable || _activeEngine == null || frame.isEmpty) {
      final String reason = !SettingsService.instance.depthAnalysisEnabled
          ? 'depth analysis disabled in settings'
          : frame.isEmpty
              ? 'empty frame'
              : 'depth engine unavailable (${_engineStatus.name})';
      return _fallbackScene(frame, objects, reason);
    }

    DepthMap? map;
    try {
      map = _activeEngine!.inferDepth(
        frame,
        params: const DepthParams(horizonRow: _kHorizon),
        objectBoxes: [for (final o in objects) o.boundingBox],
      );
    } catch (e) {
      print('DEPTH_ERROR: engine inference threw $e');
      return _fallbackScene(frame, objects, 'engine inference error: $e');
    }
    if (map == null) {
      return _fallbackScene(frame, objects, 'engine produced no depth map');
    }

    print('DEPTH_FRAME: ${map.cols}x${map.rows} objects=${objects.length}');

    // Region-level walking-path assessment.
    final List<PathRegionAssessment> regions = [
      _assessRegion(PathRegion.left, map),
      _assessRegion(PathRegion.center, map),
      _assessRegion(PathRegion.right, map),
    ];

    // Object <-> depth association (robust inner-region sampling).
    final List<ObjectWithDepth> objectsWithDepth = [];
    final List<DetectedObject> enriched = [];
    for (final obj in objects) {
      final DepthResult rawResult = _associateObject(obj, map);
      final ProximityLevel level = _smoothObjectLevel(
        _objectKey(obj),
        rawResult.proximity,
      );
      final double? meters = _smoothDistance(_objectKey(obj), _metersFrom(obj, rawResult));
      final DepthResult result = DepthResult(
        relativeDepth: rawResult.relativeDepth,
        normalizedDepth: rawResult.normalizedDepth,
        proximity: level,
        confidence: rawResult.confidence,
        estimatedDistance: meters,
        depthQuality: rawResult.depthQuality,
        fromFallback: false,
      );
      objectsWithDepth.add(ObjectWithDepth(object: obj, depth: result));
      enriched.add(obj.copyWith(
        proximity: level,
        distanceMeters: meters,
        distanceConfidence: meters == null ? null : rawResult.confidence,
      ));
      print(
        'DEPTH_OBJECT: ${obj.displayName} relative=${result.relativeDepth.toStringAsFixed(2)} '
        'prox=${level.label} conf=${result.confidence.toStringAsFixed(2)} '
        'distance=${meters == null ? 'n/a' : formatDistanceMeters(meters)} '
        'distanceConf=${result.confidence.toStringAsFixed(2)}',
      );
    }

    // Depth-only ("unknown") obstacles: blocked regions with no responsible
    // detected object get a synthesized low-trust obstacle.
    bool unknownObstacle = false;
    for (final PathRegionAssessment assess in regions) {
      if (assess.blockLevel == DepthBlockLevel.open) continue;
      final bool responsible = enriched.any((e) =>
          _regionForCenter(e.centerX) == assess.region &&
          (e.proximity?.index ?? ProximityLevel.far.index) >=
              ProximityLevel.near.index);
      if (!responsible) {
        unknownObstacle = true;
        enriched.add(_synthesizeObstacle(assess.region, assess));
        print('DEPTH_PATH: unknown depth-only obstacle in ${assess.region.name}');
      }
    }

    final double overallConfidence = regions.isEmpty
        ? 0.0
        : regions.fold(0.0, (a, r) => a + r.confidence) / regions.length;

    print(
      'DEPTH_PATH: L=${regions[0].blockLevel.name} '
      'C=${regions[1].blockLevel.name} R=${regions[2].blockLevel.name} '
      'unknown=$unknownObstacle',
    );

    final DepthScene scene = DepthScene(
      frame: frame,
      depthMap: map,
      engineType: DepthEngineType.geometric,
      usedFallback: false,
      objectsWithDepth: objectsWithDepth,
      enrichedObjects: enriched,
      regions: regions,
      overallConfidence: overallConfidence,
      unknownObstacleDetected: unknownObstacle,
    );
    _lastScene = scene;
    return scene;
  }

  // ------------------------------------------------------------------
  // Walking-path region assessment
  // ------------------------------------------------------------------

  PathRegionAssessment _assessRegion(PathRegion region, DepthMap map) {
    final (double from, double to) = switch (region) {
      PathRegion.left => (0.0, 1.0 / 3.0),
      PathRegion.center => (1.0 / 3.0, 2.0 / 3.0),
      PathRegion.right => (2.0 / 3.0, 1.0),
    };

    int total = 0;
    int open = 0;
    double nearest = 0.0;

    for (int row = 0; row < map.rows; row++) {
      final double ny = (row + 0.5) / map.rows;
      if (ny < _kWalkingBandTop || ny > _kWalkingBandBottom) continue;
      for (int col = 0; col < map.cols; col++) {
        final double nx = (col + 0.5) / map.cols;
        if (nx < from || nx >= to) continue;
        final double value = map.cellAt(col, row);
        if (value.isNaN) continue;
        total++;
        if (value < _kClearCellNear) open++;
        if (value > nearest) nearest = value;
      }
    }

    if (total == 0) {
      return PathRegionAssessment(
        region: region,
        openRatio: 1.0,
        nearestDepth: 0.0,
        blockLevel: DepthBlockLevel.open,
        confidence: 0.1,
      );
    }

    final double openRatio = open / total;
    final double s = _sensitivityScale(
      SettingsService.instance.obstacleSensitivity,
    );
    final double adj = (s - 1.0) * 0.10;
    final DepthBlockLevel raw = _rawBlockLevel(
      nearest,
      openRatio,
      blockedNearest: _kBlockedNearest + adj,
      partialNearest: _kPartialNearest + adj,
    );
    final DepthBlockLevel level = _smoothRegionLevel(region, raw);

    final double confidence =
        (0.25 + (1.0 - openRatio) * 0.35).clamp(0.15, 0.6);

    return PathRegionAssessment(
      region: region,
      openRatio: openRatio,
      nearestDepth: nearest,
      blockLevel: level,
      confidence: confidence,
    );
  }

  DepthBlockLevel _rawBlockLevel(
    double nearest,
    double openRatio, {
    required double blockedNearest,
    required double partialNearest,
  }) {
    if (nearest >= blockedNearest && openRatio < _kBlockedOpenRatio) {
      return DepthBlockLevel.blocked;
    }
    if (nearest >= partialNearest && openRatio < _kPartialOpenRatio) {
      return DepthBlockLevel.partiallyBlocked;
    }
    return DepthBlockLevel.open;
  }

  /// Region hysteresis: a single blocked frame must never tip the whole path
  /// decision (no aggressive calls from one uncertain measurement). Uses a
  /// 3-frame window:
  ///   - without enough history yet, trust the current measurement;
  ///   - two votes for one level decide;
  ///   - otherwise the ambiguous middle state (partially blocked) holds.
  DepthBlockLevel _smoothRegionLevel(
    PathRegion region,
    DepthBlockLevel raw,
  ) {
    final List<DepthBlockLevel> window = _regionLevelWindow
        .putIfAbsent(region, () => []);
    window.add(raw);
    if (window.length > _historyLength) window.removeAt(0);

    if (window.length < _historyLength) return raw;
    final int blocked = window.where((e) => e == DepthBlockLevel.blocked).length;
    final int open = window.where((e) => e == DepthBlockLevel.open).length;
    if (blocked >= 2) return DepthBlockLevel.blocked;
    if (open >= 2) return DepthBlockLevel.open;
    return DepthBlockLevel.partiallyBlocked;
  }

  // ------------------------------------------------------------------
  // Object <-> depth association
  // ------------------------------------------------------------------

  DepthResult _associateObject(DetectedObject obj, DepthMap map) {
    final Rect box = obj.boundingBox;
    const double inset = 0.10;
    final double left = (box.left + box.width * inset).clamp(0.0, 1.0);
    final double right = (box.right - box.width * inset).clamp(0.0, 1.0);
    final double top = (box.top + box.height * inset).clamp(0.0, 1.0);
    final double bottom = (box.bottom - box.height * inset).clamp(0.0, 1.0);

    if (left >= right || top >= bottom) {
      return _boxHeuristicResult(box);
    }

    final List<double> samples = [];
    for (int row = 0; row < map.rows; row++) {
      final double ny = (row + 0.5) / map.rows;
      if (ny < top || ny > bottom) continue;
      for (int col = 0; col < map.cols; col++) {
        final double nx = (col + 0.5) / map.cols;
        if (nx < left || nx > right) continue;
        final double value = map.cellAt(col, row);
        if (value.isNaN || value < 0.0 || value > 1.0) continue;
        samples.add(value);
      }
    }

    if (samples.isEmpty) {
      return _boxHeuristicResult(box);
    }

    final double relativeDepth = _trimmedMedian(samples);
    final double s = _sensitivityScale(
      SettingsService.instance.obstacleSensitivity,
    );
    final ProximityLevel proximity = _classifyRelative(
      relativeDepth,
      (s - 1.0) * 0.10,
    );

    final double validRatio =
        (samples.length / math.max(1.0, _expectedSampleCells(map, box))).clamp(0.0, 1.0);
    final DepthQuality quality = samples.length >= 4 && validRatio > 0.6
        ? (validRatio > 0.8 ? DepthQuality.good : DepthQuality.fair)
        : (samples.isNotEmpty ? DepthQuality.low : DepthQuality.none);

    final DepthEngine? engine = _activeEngine;
    final double confidence = (engine?.nominalConfidence ?? 0.25) *
            (0.5 + 0.5 * validRatio)
        .clamp(0.0, 1.0);

    return DepthResult(
      relativeDepth: relativeDepth,
      normalizedDepth: relativeDepth,
      proximity: proximity,
      confidence: confidence.clamp(0.1, 0.6),
      depthQuality: quality,
    );
  }

  int _expectedSampleCells(DepthMap map, Rect box) {
    const double inset = 0.10;
    final double left = (box.left + box.width * inset).clamp(0.0, 1.0);
    final double right = (box.right - box.width * inset).clamp(0.0, 1.0);
    final double top = (box.top + box.height * inset).clamp(0.0, 1.0);
    final double bottom = (box.bottom - box.height * inset).clamp(0.0, 1.0);
    if (left >= right || top >= bottom) return 0;
    final int cols = ((right - left) * map.cols).round().clamp(1, map.cols);
    final int rows = ((bottom - top) * map.rows).round().clamp(1, map.rows);
    return cols * rows;
  }

  double _trimmedMedian(List<double> samples) {
    final List<double> sorted = List<double>.from(samples)..sort();
    final int trim = (sorted.length * 0.10).floor();
    if (sorted.length <= 2) return sorted[sorted.length ~/ 2];
    final int lo = trim;
    final int hi = sorted.length - trim;
    if (lo >= hi) return sorted[sorted.length ~/ 2];
    final List<double> core = sorted.sublist(lo, hi);
    final int mid = core.length ~/ 2;
    if (core.length.isOdd) return core[mid];
    return (core[mid - 1] + core[mid]) / 2.0;
  }

  ProximityLevel _classifyRelative(double relativeDepth, double adj) {
    if (relativeDepth >= _kVeryNear + adj) return ProximityLevel.veryNear;
    if (relativeDepth >= _kNear + adj) return ProximityLevel.near;
    if (relativeDepth >= _kMedium + adj) return ProximityLevel.medium;
    return ProximityLevel.far;
  }

  DepthResult _boxHeuristicResult(Rect box) {
    final double area = box.width * box.height;
    final ProximityLevel proximity = estimateProximity(box);
    return DepthResult.boxHeuristic(
      relativeDepth: (area * 6.0).clamp(0.0, 1.0),
      proximity: proximity,
    );
  }

  String _objectKey(DetectedObject obj) =>
      '${obj.className}|${(obj.centerX * 20).round()}';

  /// Object hysteresis: safety upgrades (to very-near / near) apply
  /// immediately; downgrades need 2 of the last 3 frames to agree.
  ProximityLevel _smoothObjectLevel(String key, ProximityLevel raw) {
    final ProximityLevel? known = _objectAppliedLevel[key];
    if (known == null) {
      _pushObjectLevel(key, raw);
      _objectAppliedLevel[key] = raw;
      return raw;
    }
    if (raw.index > known.index) {
      _pushObjectLevel(key, raw);
      _objectAppliedLevel[key] = raw;
      return raw;
    }
    _pushObjectLevel(key, raw);
    final int count =
        _objectLevelWindow[key]!.where((l) => l == raw).length;
    if (count >= 2) {
      _objectAppliedLevel[key] = raw;
      return raw;
    }
    return known;
  }

  void _pushObjectLevel(String key, ProximityLevel level) {
    final List<ProximityLevel> window =
        _objectLevelWindow.putIfAbsent(key, () => []);
    window.add(level);
    if (window.length > _historyLength) window.removeAt(0);
  }

  // ------------------------------------------------------------------
  // Unknown obstacle synthesis
  // ------------------------------------------------------------------

  DetectedObject _synthesizeObstacle(
    PathRegion region,
    PathRegionAssessment assess,
  ) {
    final Rect bounds = switch (region) {
      PathRegion.left => const Rect.fromLTRB(0.02, 0.35, 0.31, 0.95),
      PathRegion.center => const Rect.fromLTRB(0.36, 0.30, 0.64, 0.95),
      PathRegion.right => const Rect.fromLTRB(0.69, 0.35, 0.98, 0.95),
    };
    final ProximityLevel proximity = assess.blockLevel == DepthBlockLevel.blocked
        ? ProximityLevel.veryNear
        : ProximityLevel.near;
    final double confidence =
        (assess.confidence * 0.8 + 0.15).clamp(0.2, 0.6);
    final double? meters = _metersFor(assess.nearestDepth);
    return DetectedObject(
      className: 'obstacle',
      confidence: confidence,
      boundingBox: bounds,
      proximity: proximity,
      distanceMeters: meters,
      distanceConfidence: meters == null ? null : confidence,
    );
  }

  // ------------------------------------------------------------------
  // Metric distance (calibrated meters)
  // ------------------------------------------------------------------

  /// Calibrated meters for one detection, or null when a distance cannot be
  /// produced honestly.
  ///
  /// The box-area fallback ([DepthResult.fromFallback]) is a coarse but REAL
  /// estimate: it is used when a box is too small to sample, or when its inner
  /// region holds no usable depth cell — exactly the situation for a small,
  /// very close object. It used to be discarded outright, which is why close
  /// objects sometimes showed no distance at all. It is now kept (still
  /// low-confidence, so the UI can present it as an estimate).
  ///
  /// A box with no footprint at all (zero width or height) still gets nothing:
  /// there is no evidence to convert, and inventing one would be a fabrication.
  double? _metersFrom(DetectedObject obj, DepthResult result) {
    if (result.fromFallback && !_hasFootprint(obj.boundingBox)) return null;
    return _metersFor(result.relativeDepth);
  }

  bool _hasFootprint(Rect box) => box.width > 0 && box.height > 0;

  /// Convert a relative-depth value to calibrated meters using the enabled
  /// metric calibration. Returns null when metric distance is disabled in
  /// settings or the value is out of range — the object simply shows no
  /// distance (never a fabricated number).
  double? _metersFor(double relativeDepth) {
    final SettingsService s = SettingsService.instance;
    if (!s.metricDistanceEnabled) return null;
    return DepthMetricCalibration(
      cameraHeightMeters: s.cameraHeightMeters,
      downwardPitchDegrees: s.cameraPitchDegrees,
    ).metersFromRelative(relativeDepth);
  }

  /// Temporal EMA on calibrated meters per object key so on-screen distances
  /// glide instead of jumping. A transient null frame keeps the previous
  /// smoothed value; the map is cleared on reset().
  double? _smoothDistance(String key, double? raw) {
    final double? prev = _smoothedDistanceMeters[key];
    if (raw == null) return prev;
    final double next = prev == null
        ? raw
        : prev + _kDistanceSmoothing * (raw - prev);
    _smoothedDistanceMeters[key] = next;
    return next;
  }

  PathRegion _regionForCenter(double centerX) {
    if (centerX < 1.0 / 3.0) return PathRegion.left;
    if (centerX > 2.0 / 3.0) return PathRegion.right;
    return PathRegion.center;
  }

  // ------------------------------------------------------------------
  // Fallback
  // ------------------------------------------------------------------

  DepthScene _fallbackScene(
    RgbFrame frame,
    List<DetectedObject> objects,
    String reason,
  ) {
    print('DEPTH_FALLBACK: $reason');
    final List<DetectedObject> enriched = analyze(objects);
    final List<ObjectWithDepth> objectsWithDepth = [];
    for (final obj in enriched) {
      final double area = obj.boundingBox.width * obj.boundingBox.height;
      objectsWithDepth.add(ObjectWithDepth(
        object: obj,
        depth: DepthResult.boxHeuristic(
          relativeDepth: (area * 6.0).clamp(0.0, 1.0),
          proximity: obj.proximity ?? ProximityLevel.far,
        ),
      ));
    }

    final DepthMap map = _fallbackMap(objects);
    final List<PathRegionAssessment> regions = [
      for (final region in PathRegion.values)
        PathRegionAssessment(
          region: region,
          openRatio: 1.0,
          nearestDepth: 0.0,
          blockLevel: DepthBlockLevel.open,
          confidence: 0.1,
        ),
    ];

    final DepthScene scene = DepthScene(
      frame: frame,
      depthMap: map,
      engineType: DepthEngineType.fallback,
      usedFallback: true,
      fallbackReason: reason,
      objectsWithDepth: objectsWithDepth,
      enrichedObjects: enriched,
      regions: regions,
      overallConfidence: 0.1,
      unknownObstacleDetected: false,
    );
    _lastScene = scene;
    return scene;
  }

  /// A coarse map derived from box footprints only, so the debug overlay and
  /// downstream code always get a valid map even during fallback.
  DepthMap _fallbackMap(List<DetectedObject> objects) {
    const int cols = 24;
    const int rows = 32;
    final List<double> cells = List<double>.filled(cols * rows, 0.0);
    for (final obj in objects) {
      final Rect box = obj.boundingBox;
      final double areaScore = (box.width * box.height * 6.0).clamp(0.0, 1.0);
      final int leftCol = (box.left * (cols - 1)).round().clamp(0, cols - 1);
      final int rightCol =
          (box.right * (cols - 1)).round().clamp(0, cols - 1);
      final int topRow = (box.top * (rows - 1)).round().clamp(0, rows - 1);
      final int bottomRow =
          (box.bottom * (rows - 1)).round().clamp(0, rows - 1);
      for (int row = topRow; row <= bottomRow; row++) {
        for (int col = leftCol; col <= rightCol; col++) {
          final int i = row * cols + col;
          if (areaScore > cells[i]) cells[i] = areaScore;
        }
      }
    }
    return DepthMap(cols: cols, rows: rows, cells: cells);
  }
}