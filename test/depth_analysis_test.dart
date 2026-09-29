import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionpath/models/app_settings.dart';
import 'package:visionpath/models/detected_object.dart';
import 'package:visionpath/models/depth_map.dart';
import 'package:visionpath/models/depth_result.dart';
import 'package:visionpath/models/depth_scene.dart';
import 'package:visionpath/models/navigation_decision.dart';
import 'package:visionpath/models/path_analysis.dart';
import 'package:visionpath/models/proximity_level.dart';
import 'package:visionpath/models/rgb_frame.dart';
import 'package:visionpath/services/depth/depth_engine.dart';
import 'package:visionpath/services/depth/depth_metric_calibration.dart';
import 'package:visionpath/services/depth/geometric_depth_engine.dart';
import 'package:visionpath/services/depth_analysis_service.dart';
import 'package:visionpath/services/navigation_service.dart';
import 'package:visionpath/services/path_analysis_service.dart';
import 'package:visionpath/services/settings_service.dart';
import 'package:visionpath/widgets/sound_mode_button.dart';

/// Deterministic stubs and builders for the depth pipeline. No camera, no
/// platform channels: everything is injected and computed in pure Dart.
DepthMap _flatMap(double value, {int cols = 24, int rows = 32}) => DepthMap(
      cols: cols,
      rows: rows,
      cells: List<double>.filled(cols * rows, value),
    );

DepthMap _boxMap(
  Rect box,
  double hotValue, {
  double base = 0.2,
  int cols = 24,
  int rows = 32,
}) {
  final List<double> cells = List<double>.filled(cols * rows, base);
  final int leftCol = (box.left * (cols - 1)).round().clamp(0, cols - 1);
  final int rightCol = (box.right * (cols - 1)).round().clamp(0, cols - 1);
  final int topRow = (box.top * (rows - 1)).round().clamp(0, rows - 1);
  final int bottomRow = (box.bottom * (rows - 1)).round().clamp(0, rows - 1);
  for (int row = topRow; row <= bottomRow; row++) {
    for (int col = leftCol; col <= rightCol; col++) {
      cells[row * cols + col] = hotValue;
    }
  }
  return DepthMap(cols: cols, rows: rows, cells: cells);
}

RgbFrame _frame({int width = 16, int height = 16, int fill = 128}) {
  final Uint8List bytes = Uint8List(width * height * 3);
  for (int i = 0; i < bytes.length; i++) {
    bytes[i] = fill;
  }
  return RgbFrame(rgb: bytes, width: width, height: height);
}

class _StubEngine implements DepthEngine {
  _StubEngine({
    this.detail = 'stub depth engine',
    this.resultMap,
    this.confidence = 0.4,
  });

  DepthEngineStatus engineStatus = DepthEngineStatus.ready;
  String detail;
  double confidence;
  final DepthMap Function(RgbFrame frame, List<Rect> objectBoxes)? resultMap;
  bool throwOnInfer = false;

  @override
  DepthEngineStatus get status => engineStatus;

  @override
  String get statusDetail => detail;

  @override
  double get nominalConfidence => confidence;

  @override
  Future<bool> initialize() async {
    return engineStatus == DepthEngineStatus.ready;
  }

  @override
  DepthMap? inferDepth(
    RgbFrame frame, {
    DepthParams? params,
    List<Rect> objectBoxes = const [],
  }) {
    if (throwOnInfer) throw StateError('stub inference failure');
    return resultMap?.call(frame, objectBoxes) ?? _flatMap(0.2);
  }

  @override
  void dispose() {}
}

PathRegionAssessment _assessment(
  PathRegion region,
  DepthBlockLevel level, {
  double openRatio = 1.0,
  double nearest = 0.1,
}) {
  return PathRegionAssessment(
    region: region,
    openRatio: openRatio,
    nearestDepth: nearest,
    blockLevel: level,
    confidence: 0.4,
  );
}

DetectedObject _object(
  String className,
  Rect box, {
  ProximityLevel? proximity,
  double? distanceMeters,
  double? distanceConfidence,
}) {
  return DetectedObject(
    className: className,
    confidence: 0.8,
    boundingBox: box,
    proximity: proximity,
    distanceMeters: distanceMeters,
    distanceConfidence: distanceConfidence,
  );
}

/// Merge a per-box hot depth map: each box gets its own distinct value so
/// every detection can be measured independently.
DepthMap _multiHotMap(
  List<Rect> boxes,
  List<double> hots, {
  double base = 0.2,
}) {
  const int cols = 24;
  const int rows = 32;
  final List<double> cells = List<double>.filled(cols * rows, base);
  for (int i = 0; i < boxes.length; i++) {
    final Rect b = boxes[i];
    final int left = (b.left * (cols - 1)).round().clamp(0, cols - 1);
    final int right = (b.right * (cols - 1)).round().clamp(0, cols - 1);
    final int top = (b.top * (rows - 1)).round().clamp(0, rows - 1);
    final int bottom = (b.bottom * (rows - 1)).round().clamp(0, rows - 1);
    for (int y = top; y <= bottom; y++) {
      for (int x = left; x <= right; x++) {
        cells[y * cols + x] = hots[i];
      }
    }
  }
  return DepthMap(cols: cols, rows: rows, cells: cells);
}

DepthScene _scene({
  required PathRegionAssessment left,
  required PathRegionAssessment center,
  required PathRegionAssessment right,
  List<ObjectWithDepth> objectsWithDepth = const [],
  List<DetectedObject> enriched = const [],
  bool unknown = false,
  DepthMap? map,
}) {
  return DepthScene(
    frame: null,
    depthMap: map ?? _flatMap(0.2),
    engineType: DepthEngineType.geometric,
    usedFallback: false,
    objectsWithDepth: objectsWithDepth,
    enrichedObjects: enriched,
    regions: [left, center, right],
    overallConfidence: 0.4,
    unknownObstacleDetected: unknown,
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
  });

  tearDown(() async {
    await SettingsService.instance.setDepthAnalysisEnabled(true);
    await SettingsService.instance.setDepthDebugOverlay(false);
    await SettingsService.instance.setMetricDistanceEnabled(true);
    await SettingsService.instance.setCameraHeightMeters(1.5);
    await SettingsService.instance.setCameraPitchDegrees(20);
  });

  // ------------------------------------------------------------------
  // GeometricDepthEngine
  // ------------------------------------------------------------------

  test('geometric engine initializes ready and reports its confidence', () async {
    final GeometricDepthEngine engine = GeometricDepthEngine();
    expect(engine.status, DepthEngineStatus.idle);
    await engine.initialize();
    expect(engine.status, DepthEngineStatus.ready);
    expect(engine.nominalConfidence, greaterThan(0.0));
    expect(engine.nominalConfidence, lessThanOrEqualTo(0.5));
  });

  test('geometric engine map has the expected coarse grid dimensions', () async {
    final GeometricDepthEngine engine = GeometricDepthEngine();
    await engine.initialize();
    final DepthMap map =
        engine.inferDepth(_frame(fill: 128));
    expect(map.cols, 24);
    expect(map.rows, 32);
    expect(map.length, 24 * 32);
  });

  test('geometric engine: rows above or at the horizon are far', () async {
    final GeometricDepthEngine engine = GeometricDepthEngine();
    await engine.initialize();
    final DepthMap map = engine.inferDepth(_frame(fill: 128));
    expect(map.valueAt(0.2, 0.10), 0.0);
    expect(map.valueAt(0.8, 0.30), 0.0);
  });

  test('geometric engine: nearness grows monotonically towards the bottom',
      () async {
    final GeometricDepthEngine engine = GeometricDepthEngine();
    await engine.initialize();
    final DepthMap map = engine.inferDepth(_frame(fill: 128));
    final double mid = map.valueAt(0.3, 0.55);
    final double lower = map.valueAt(0.3, 0.80);
    final double bottom = map.valueAt(0.3, 0.95);
    expect(mid, greaterThan(0.0));
    expect(lower, greaterThan(mid));
    expect(bottom, greaterThan(lower));
    expect(bottom, lessThanOrEqualTo(1.0));
  });

  test('geometric engine is deterministic for identical inputs', () async {
    final GeometricDepthEngine engine = GeometricDepthEngine();
    await engine.initialize();
    final DepthMap a = engine.inferDepth(_frame(fill: 128));
    final DepthMap b = engine.inferDepth(_frame(fill: 128));
    for (int i = 0; i < a.length; i++) {
      expect(a.cells[i], b.cells[i]);
    }
  });

  test('geometric engine boosts cells inside detector boxes', () async {
    final GeometricDepthEngine engine = GeometricDepthEngine();
    await engine.initialize();
    const Rect box = Rect.fromLTRB(0.40, 0.55, 0.60, 1.0);
    final DepthMap map =
        engine.inferDepth(_frame(fill: 128), objectBoxes: [box]);
    final double inside = map.valueAt(0.5, 0.85);
    final double outside = map.valueAt(0.03, 0.85);
    expect(inside, greaterThan(outside));
    expect(inside, greaterThanOrEqualTo(0.9));
  });

  test('geometric engine: high-contrast texture raises cells (unknown cue)',
      () async {
    final GeometricDepthEngine engine = GeometricDepthEngine();
    await engine.initialize();
    // Column of dark pixels at the centre against an otherwise light frame.
    final int w = 16;
    final int h = 16;
    final Uint8List bytes = Uint8List(w * h * 3);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int v = (x == 7 || x == 8) ? 0 : 255;
        bytes[(y * w + x) * 3] = v;
        bytes[(y * w + x) * 3 + 1] = v;
        bytes[(y * w + x) * 3 + 2] = v;
      }
    }
    final DepthMap map =
        engine.inferDepth(RgbFrame(rgb: bytes, width: w, height: h));
    final double onColumn = map.valueAt(0.5, 0.70);
    final double offColumn = map.valueAt(0.03, 0.70);
    expect(onColumn, greaterThan(0.45));
    expect(offColumn, lessThan(0.4));
    expect(onColumn, greaterThan(offColumn));
  });

  // ------------------------------------------------------------------
  // DepthMap sampling
  // ------------------------------------------------------------------

  test('depth map nearest-neighbour sampling clamps out-of-range coords',
      () async {
    final DepthMap map = _flatMap(0.5);
    expect(map.valueAt(-1.0, 0.5), 0.5);
    expect(map.valueAt(0.5, -1.0), 0.5);
    expect(map.valueAt(2.0, 2.0), 0.5);
  });

  test('depth map bilinear sampling averages between cells', () async {
    final List<double> cells = List<double>.filled(4 * 4, 0.0);
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        cells[row * 4 + col] = ((row + col) % 2 == 0) ? 0.0 : 1.0;
      }
    }
    final DepthMap map = DepthMap(cols: 4, rows: 4, cells: cells);
    final double bilinear = map.sampleBilinear(0.5, 0.5);
    expect(bilinear, greaterThan(0.0));
    expect(bilinear, lessThan(1.0));
  });

  // ------------------------------------------------------------------
  // DepthAnalysisService: fallback behaviour
  // ------------------------------------------------------------------

  test('analyzeScene falls back when the engine is in error state', () async {
    final DepthAnalysisService service = DepthAnalysisService();
    await service.initialize(
      engine: _StubEngine(detail: 'x')..engineStatus = DepthEngineStatus.error,
    );
    expect(service.engineStatus, DepthEngineStatus.error);
    final DepthScene scene = await service.analyzeScene(
      _frame(),
      [_object('chair', const Rect.fromLTRB(0.2, 0.3, 0.5, 0.9))],
    );
    expect(scene.usedFallback, isTrue);
    expect(scene.engineType, DepthEngineType.fallback);
    expect(scene.fallbackReason, isNotNull);
  });

  test('analyzeScene falls back when depth analysis is disabled in settings',
      () async {
    await SettingsService.instance.setDepthAnalysisEnabled(false);
    final DepthAnalysisService service = DepthAnalysisService();
    await service.initialize(engine: _StubEngine());
    expect(service.engineUsable, isFalse);
    final DepthScene scene = await service.analyzeScene(
      _frame(),
      [_object('person', const Rect.fromLTRB(0.3, 0.2, 0.6, 0.8))],
    );
    expect(scene.usedFallback, isTrue);
  });

  test('analyzeScene falls back when the engine produces no map', () async {
    final DepthAnalysisService service = DepthAnalysisService();
    await service.initialize(engine: _StubEngine()..throwOnInfer = true);
    final DepthScene scene = await service.analyzeScene(
      _frame(),
      [_object('person', const Rect.fromLTRB(0.3, 0.2, 0.6, 0.8))],
    );
    expect(scene.usedFallback, isTrue);
  });

  test('legacy analyze() still enriches objects with heuristic proximity',
      () async {
    final DepthAnalysisService service = DepthAnalysisService();
    final List<DetectedObject> enriched = service.analyze([
      _object('car', const Rect.fromLTRB(0.2, 0.2, 0.8, 0.9)),
      _object('person', const Rect.fromLTRB(0.1, 0.1, 0.2, 0.2)),
    ]);
    expect(enriched[0].proximity, ProximityLevel.veryNear);
    expect(enriched[1].proximity, ProximityLevel.far);
  });

  // ------------------------------------------------------------------
  // DepthAnalysisService: object <-> depth association
  // ------------------------------------------------------------------

  test('associates depth for an object sitting low in the frame', () async {
    final DepthAnalysisService service = DepthAnalysisService();
    final Rect box = const Rect.fromLTRB(0.4, 0.55, 0.6, 0.95);
    await service.initialize(
      engine: _StubEngine(
        resultMap: (frame, boxes) => _boxMap(box, 0.92),
      ),
    );
    final DepthScene scene = await service.analyzeScene(
      _frame(),
      [_object('person', box)],
    );
    expect(scene.usedFallback, isFalse);
    expect(scene.objectsWithDepth, hasLength(1));
    final DepthResult depth = scene.objectsWithDepth.first.depth;
    expect(depth.relativeDepth, greaterThan(0.8));
    expect(depth.proximity, ProximityLevel.veryNear);
    // Metric calibration (enabled by default) attaches a meter estimate.
    expect(depth.estimatedDistance, isNotNull);
    expect(depth.estimatedDistance, greaterThan(0));
    expect(depth.fromFallback, isFalse);
  });

  test('classifies a mid-frame distant object as far', () async {
    final DepthAnalysisService service = DepthAnalysisService();
    final Rect box = const Rect.fromLTRB(0.4, 0.1, 0.6, 0.35);
    await service.initialize(
      engine: _StubEngine(
        resultMap: (frame, boxes) => _boxMap(box, 0.1),
      ),
    );
    final DepthScene scene = await service.analyzeScene(
      _frame(),
      [_object('person', box)],
    );
    expect(scene.objectsWithDepth.single.depth.proximity, ProximityLevel.far);
  });

  test('robust inner sampling ignores depth outliers', () async {
    final DepthAnalysisService service = DepthAnalysisService();
    const Rect box = Rect.fromLTRB(0.4, 0.4, 0.6, 0.9);
    // Box cells are low except one hot column -> trimmed median must stay low
    // so a single anomalous cell never flips the classification.
    final DepthMap map = _boxMap(box, 0.1);
    for (int row = 16; row <= 26; row++) {
      map.cells[row * map.cols + 10] = 1.0;
    }
    await service.initialize(
      engine: _StubEngine(resultMap: (frame, boxes) => map),
    );
    final DepthScene scene = await service.analyzeScene(
      _frame(),
      [_object('person', box)],
    );
    final DepthResult depth = scene.objectsWithDepth.single.depth;
    expect(depth.relativeDepth, lessThan(0.34));
    expect(depth.proximity, ProximityLevel.far);
  });

  test('sensitivity shifts the proximity classification threshold', () async {
    const Rect box = Rect.fromLTRB(0.35, 0.3, 0.6, 0.9);

    DepthAnalysisService runService() {
      final DepthAnalysisService s = DepthAnalysisService();
      return s;
    }

    await SettingsService.instance.setObstacleSensitivity(
      ObstacleSensitivity.high,
    );
    final DepthAnalysisService high = runService();
    await high.initialize(
      engine: _StubEngine(resultMap: (f, b) => _boxMap(box, 0.8)),
    );
    final DepthScene highScene =
        await high.analyzeScene(_frame(), [_object('person', box)]);
    expect(
      highScene.objectsWithDepth.single.depth.proximity,
      ProximityLevel.veryNear,
    );

    await SettingsService.instance.setObstacleSensitivity(
      ObstacleSensitivity.low,
    );
    final DepthAnalysisService low = runService();
    await low.initialize(
      engine: _StubEngine(resultMap: (f, b) => _boxMap(box, 0.8)),
    );
    final DepthScene lowScene =
        await low.analyzeScene(_frame(), [_object('person', box)]);
    expect(
      lowScene.objectsWithDepth.single.depth.proximity,
      ProximityLevel.near,
    );
  });

  // ------------------------------------------------------------------
  // DepthAnalysisService: temporal smoothing
  // ------------------------------------------------------------------

  test('first-frame object depth classification applies immediately', () async {
    const Rect box = Rect.fromLTRB(0.4, 0.4, 0.6, 0.9);
    final DepthAnalysisService service = DepthAnalysisService();
    await service.initialize(
      engine: _StubEngine(resultMap: (f, b) => _boxMap(box, 0.8)),
    );
    final DetectedObject obj = _object('person', box);
    final DepthScene first = await service.analyzeScene(_frame(), [obj]);
    expect(
      first.objectsWithDepth.single.depth.proximity,
      ProximityLevel.veryNear,
    );
  });

  test('object downgrade requires two consecutive weaker frames', () async {
    const Rect box = Rect.fromLTRB(0.4, 0.4, 0.6, 0.9);
    final DepthAnalysisService service = DepthAnalysisService();
    final DetectedObject obj = _object('person', box);
    double frameValue = 0.92;
    await service.initialize(
      engine: _StubEngine(resultMap: (f, b) => _boxMap(box, frameValue)),
    );

    final DepthScene f1 = await service.analyzeScene(_frame(), [obj]);
    expect(f1.objectsWithDepth.single.depth.proximity, ProximityLevel.veryNear);

    // One weaker frame is not enough to downgrade (hysteresis holds).
    frameValue = 0.6;
    final DepthScene f2 = await service.analyzeScene(_frame(), [obj]);
    expect(
      f2.objectsWithDepth.single.depth.proximity,
      ProximityLevel.veryNear,
    );

    // Two consecutive weaker frames downgrade.
    final DepthScene f3 = await service.analyzeScene(_frame(), [obj]);
    expect(f3.objectsWithDepth.single.depth.proximity, ProximityLevel.near);
  });

  // ------------------------------------------------------------------
  // DepthAnalysisService: regions + unknown obstacles
  // ------------------------------------------------------------------

  test('empty floor scene yields all-open regions', () async {
    final DepthAnalysisService service = DepthAnalysisService();
    await service.initialize(
      engine: _StubEngine(resultMap: (f, b) => _flatMap(0.2)),
    );
    final DepthScene scene = await service.analyzeScene(_frame(), []);
    for (final PathRegionAssessment r in scene.regions) {
      expect(r.blockLevel, DepthBlockLevel.open);
    }
    expect(scene.unknownObstacleDetected, isFalse);
    expect(scene.regions, hasLength(3));
  });

  test('a hot centre band blocks the centre region', () async {
    final DepthAnalysisService service = DepthAnalysisService();
    await service.initialize(
      engine: _StubEngine(
        resultMap: (f, b) => _flatMap(0.9),
      ),
    );
    final DepthScene scene = await service.analyzeScene(
      _frame(),
      [_object('person', const Rect.fromLTRB(0.35, 0.3, 0.65, 1.0))],
    );
    expect(
      scene.regionOf(PathRegion.center).blockLevel,
      DepthBlockLevel.blocked,
    );
  });

  test('blocked region without any object is a depth-only unknown obstacle',
      () async {
    final DepthAnalysisService service = DepthAnalysisService();
    // Left band hot, nothing detected there.
    await service.initialize(
      engine: _StubEngine(
        resultMap: (f, b) => _flatMap(0.9),
      ),
    );
    final DepthScene scene = await service.analyzeScene(
      _frame(),
      [_object('person', const Rect.fromLTRB(0.5, 0.3, 0.7, 0.9))],
    );
    expect(scene.unknownObstacleDetected, isTrue);
    final bool hasUnknown = scene.enrichedObjects
        .any((o) => o.className == 'obstacle');
    expect(hasUnknown, isTrue);
  });

  // ------------------------------------------------------------------
  // PathAnalysisService.analyzeWithDepth
  // ------------------------------------------------------------------

  test('all regions open -> CLEAR with full margins', () {
    final PathAnalysisService service = PathAnalysisService();
    final PathRegionAssessment open =
        _assessment(PathRegion.center, DepthBlockLevel.open);
    final DepthScene scene = _scene(
      left: _assessment(PathRegion.left, DepthBlockLevel.open),
      center: open,
      right: _assessment(PathRegion.right, DepthBlockLevel.open),
    );
    final PathAnalysisResult result = service.analyzeWithDepth([], scene);
    expect(result.analysis, PathAnalysis.clear);
    expect(result.leftMargin, 1.0);
    expect(result.rightMargin, 1.0);
    expect(result.pathFullyBlocked, isFalse);
    expect(result.primaryBlocker, isNull);
  });

  test('left region blocked -> OBSTACLE_LEFT with tight left margin', () {
    final PathAnalysisService service = PathAnalysisService();
    final DetectedObject synth = _object(
      'obstacle',
      const Rect.fromLTRB(0.02, 0.35, 0.31, 0.95),
      proximity: ProximityLevel.veryNear,
    );
    final DepthScene scene = _scene(
      left: _assessment(PathRegion.left, DepthBlockLevel.blocked, openRatio: 0.1, nearest: 0.9),
      center: _assessment(PathRegion.center, DepthBlockLevel.open),
      right: _assessment(PathRegion.right, DepthBlockLevel.open),
      enriched: [synth],
    );
    final PathAnalysisResult result = service.analyzeWithDepth([], scene);
    expect(result.analysis, PathAnalysis.obstacleLeft);
    expect(result.leftMargin, 0.05);
    expect(result.pathFullyBlocked, isFalse);
    expect(result.primaryBlocker?.className, 'obstacle');
  });

  test('centre region blocked -> OBSTACLE_CENTER with reduced margins', () {
    final PathAnalysisService service = PathAnalysisService();
    final DepthScene scene = _scene(
      left: _assessment(PathRegion.left, DepthBlockLevel.open),
      center: _assessment(PathRegion.center, DepthBlockLevel.blocked, openRatio: 0.1, nearest: 0.9),
      right: _assessment(PathRegion.right, DepthBlockLevel.open),
      enriched: [
        _object(
          'obstacle',
          const Rect.fromLTRB(0.36, 0.30, 0.64, 0.95),
          proximity: ProximityLevel.veryNear,
        ),
      ],
    );
    final PathAnalysisResult result = service.analyzeWithDepth([], scene);
    expect(result.analysis, PathAnalysis.obstacleCenter);
    expect(result.leftMargin, 0.10);
    expect(result.rightMargin, 0.10);
  });

  test('right region blocked -> OBSTACLE_RIGHT with tight right margin', () {
    final PathAnalysisService service = PathAnalysisService();
    final DepthScene scene = _scene(
      left: _assessment(PathRegion.left, DepthBlockLevel.open),
      center: _assessment(PathRegion.center, DepthBlockLevel.open),
      right: _assessment(PathRegion.right, DepthBlockLevel.blocked, openRatio: 0.1, nearest: 0.9),
      enriched: [
        _object(
          'obstacle',
          const Rect.fromLTRB(0.69, 0.35, 0.98, 0.95),
          proximity: ProximityLevel.veryNear,
        ),
      ],
    );
    final PathAnalysisResult result = service.analyzeWithDepth([], scene);
    expect(result.analysis, PathAnalysis.obstacleRight);
    expect(result.rightMargin, 0.05);
  });

  test('both lateral regions blocked -> OBSTACLE_CENTER, pathFullyBlocked', () {
    final PathAnalysisService service = PathAnalysisService();
    final DepthScene scene = _scene(
      left: _assessment(PathRegion.left, DepthBlockLevel.blocked, openRatio: 0.1, nearest: 0.9),
      center: _assessment(PathRegion.center, DepthBlockLevel.open),
      right: _assessment(PathRegion.right, DepthBlockLevel.blocked, openRatio: 0.1, nearest: 0.9),
      enriched: [
        _object(
          'obstacle',
          const Rect.fromLTRB(0.02, 0.35, 0.31, 0.95),
          proximity: ProximityLevel.veryNear,
        ),
        _object(
          'obstacle',
          const Rect.fromLTRB(0.69, 0.35, 0.98, 0.95),
          proximity: ProximityLevel.veryNear,
        ),
      ],
    );
    final PathAnalysisResult result = service.analyzeWithDepth([], scene);
    expect(result.analysis, PathAnalysis.obstacleCenter);
    expect(result.pathFullyBlocked, isTrue);
  });

  test('no blocked regions but a very-near object -> OBSTACLE_CENTER', () {
    final PathAnalysisService service = PathAnalysisService();
    final DetectedObject person = _object(
      'person',
      const Rect.fromLTRB(0.45, 0.2, 0.6, 0.8),
      proximity: ProximityLevel.veryNear,
    );
    final ObjectWithDepth od = ObjectWithDepth(
      object: person,
      depth: const DepthResult(
        relativeDepth: 0.9,
        normalizedDepth: 0.9,
        proximity: ProximityLevel.veryNear,
        confidence: 0.4,
      ),
    );
    final DepthScene scene = _scene(
      left: _assessment(PathRegion.left, DepthBlockLevel.open),
      center: _assessment(PathRegion.center, DepthBlockLevel.open),
      right: _assessment(PathRegion.right, DepthBlockLevel.open),
      objectsWithDepth: [od],
      enriched: [person],
    );
    final PathAnalysisResult result = service.analyzeWithDepth([od], scene);
    expect(result.analysis, PathAnalysis.obstacleCenter);
  });

  // ------------------------------------------------------------------
  // NavigationService decision integration
  // ------------------------------------------------------------------

  test('navigation: pathFullyBlocked yields STOP', () {
    final NavigationService nav = NavigationService();
    final DetectedObject obj = _object(
      'obstacle',
      const Rect.fromLTRB(0.36, 0.30, 0.64, 0.95),
      proximity: ProximityLevel.veryNear,
    );
    nav.decide(
      const PathAnalysisResult(
        analysis: PathAnalysis.obstacleCenter,
        leftMargin: 0.1,
        rightMargin: 0.1,
        pathFullyBlocked: true,
      ),
      [obj],
    );
    expect(nav.lastDecision, NavigationDecision.stop);
    expect(nav.lastSpokenMessage, 'Stop. Obstacle very close.');
  });

  test('navigation: very-near spanning blocker still yields STOP', () {
    final NavigationService nav = NavigationService();
    nav.decide(
      const PathAnalysisResult(
        analysis: PathAnalysis.obstacleCenter,
        leftMargin: 0.1,
        rightMargin: 0.1,
      ),
      [
        _object(
          'person',
          const Rect.fromLTRB(0.4, 0.2, 0.6, 1.0),
          proximity: ProximityLevel.veryNear,
        ),
      ],
    );
    expect(nav.lastDecision, NavigationDecision.stop);
  });

  test('navigation: obstacle on the left with right space -> RIGHT', () {
    final NavigationService nav = NavigationService();
    final DetectedObject chair = _object(
      'chair',
      const Rect.fromLTRB(0.0, 0.3, 0.3, 1.0),
      proximity: ProximityLevel.medium,
    );
    nav.decide(
      PathAnalysisResult(
        analysis: PathAnalysis.obstacleLeft,
        leftMargin: 0.05,
        rightMargin: 0.6,
        primaryBlocker: chair,
      ),
      [chair],
    );
    expect(nav.lastDecision, NavigationDecision.right);
  });

  test('navigation: clear path yields FORWARD', () {
    final NavigationService nav = NavigationService();
    nav.decide(
      const PathAnalysisResult(
        analysis: PathAnalysis.clear,
        leftMargin: 1.0,
        rightMargin: 1.0,
      ),
      [],
    );
    expect(nav.lastDecision, NavigationDecision.forward);
  });

  test('navigation: both-sides STOP beats a null primary blocker', () {
    final NavigationService nav = NavigationService();
    nav.decide(
      const PathAnalysisResult(
        analysis: PathAnalysis.obstacleCenter,
        leftMargin: 0.1,
        rightMargin: 0.1,
        pathFullyBlocked: true,
      ),
      [],
    );
    expect(nav.lastDecision, NavigationDecision.stop);
  });

  // ------------------------------------------------------------------
  // Round-trip: full analyzeScene -> path -> decision
  // ------------------------------------------------------------------

  test('end-to-end: hot centre obstacle drives an obstacle result', () async {
    final DepthAnalysisService service = DepthAnalysisService();
    await service.initialize(
      engine: _StubEngine(
        resultMap: (f, b) => _flatMap(0.9),
      ),
    );
    final List<DetectedObject> detections = [
      _object('person', const Rect.fromLTRB(0.4, 0.2, 0.6, 0.9)),
    ];
    final DepthScene scene =
        await service.analyzeScene(_frame(), detections);

    final PathAnalysisService pathService = PathAnalysisService();
    final PathAnalysisResult path =
        pathService.analyzeWithDepth(scene.objectsWithDepth, scene);
    expect(path.analysis, PathAnalysis.obstacleCenter);

    final NavigationService nav = NavigationService();
    nav.decide(path, scene.enrichedObjects);
    expect(nav.lastDecision, NavigationDecision.stop);
  });

  // ------------------------------------------------------------------
  // Metric distance: calibration, per-object sampling, smoothing,
  // formatting, unavailable fallback
  // ------------------------------------------------------------------

  test('calibration: nearer relative depth maps to fewer meters', () {
    const DepthMetricCalibration cal = DepthMetricCalibration();
    final double? near = cal.metersFromRelative(0.85);
    final double? far = cal.metersFromRelative(0.15);
    expect(near, isNotNull);
    expect(far, isNotNull);
    expect(near!, lessThan(far!));
    expect(far, lessThanOrEqualTo(DepthMetricCalibration.maxDistanceMeters));
    expect(cal.metersFromRelative(double.nan), isNull);
    expect(cal.metersFromRelative(double.infinity), isNull);
  });

  test('formatDistanceMeters rounds cleanly for display', () {
    expect(formatDistanceMeters(0.37), '0.37');
    expect(formatDistanceMeters(0.74), '0.7');
    expect(formatDistanceMeters(1.26), '1.3');
    expect(formatDistanceMeters(2.43), '2.4');
    expect(formatDistanceMeters(3.82), '3.8');
    expect(formatDistanceMeters(12.4), '12');
    expect(formatDistanceMeters(0), '0 m');
  });

  test('every detected object gets its OWN calibrated distance', () async {
    final DepthAnalysisService service = DepthAnalysisService();
    await service.initialize(
      engine: _StubEngine(
        resultMap: (f, boxes) => _multiHotMap(boxes, [0.85, 0.60, 0.30]),
      ),
    );
    final List<DetectedObject> detections = [
      _object('chair', const Rect.fromLTRB(0.05, 0.55, 0.25, 0.95)),
      _object('person', const Rect.fromLTRB(0.40, 0.35, 0.60, 0.80)),
      _object('table', const Rect.fromLTRB(0.72, 0.50, 0.95, 0.90)),
    ];
    final DepthScene scene = await service.analyzeScene(_frame(), detections);

    expect(scene.enrichedObjects.length, 3);
    final Map<String, double> byName = {
      for (final e in scene.enrichedObjects) e.className: e.distanceMeters!,
    };
    // Three distinct distances, all within a sane calibrated band.
    expect(byName['chair'], isNotNull);
    expect(byName['person'], isNotNull);
    expect(byName['table'], isNotNull);
    expect(byName['chair']!, lessThan(byName['table']!));
    expect(byName.values.toSet().length, 3);
    for (final e in scene.enrichedObjects) {
      expect(e.distanceMeters, isNotNull);
      expect(e.distanceConfidence, isNotNull);
      expect(e.distanceValueText, endsWith('m'));
      expect(e.distanceLabel, endsWith('m'));
    }
  });

  test('objects at different horizontal positions keep independent meters',
      () async {
    final DepthAnalysisService service = DepthAnalysisService();
    await service.initialize(
      engine: _StubEngine(
        resultMap: (f, boxes) => _multiHotMap(
          boxes,
          [0.85, 0.85, 0.30],
        ),
      ),
    );
    final List<DetectedObject> detections = [
      _object('left', const Rect.fromLTRB(0.02, 0.55, 0.30, 0.95)),
      _object('center', const Rect.fromLTRB(0.38, 0.35, 0.62, 0.80)),
      _object('right', const Rect.fromLTRB(0.70, 0.55, 0.98, 0.95)),
    ];
    final DepthScene scene = await service.analyzeScene(_frame(), detections);
    final Map<String, double> byName = {
      for (final e in scene.enrichedObjects) e.className: e.distanceMeters!,
    };
    // The two near boxes (left + center) are closer than the far-right one.
    expect(byName['left'], isNotNull);
    expect(byName['center'], isNotNull);
    expect(byName['right'], isNotNull);
    expect(byName['left']!, lessThan(byName['right']!));
    expect(byName['center']!, lessThan(byName['right']!));
  });

  test('moving object distance is temporally smoothed (EMA)', () async {
    final DepthAnalysisService service = DepthAnalysisService();
    double frameValue = 0.9;
    await service.initialize(
      engine: _StubEngine(resultMap: (f, b) => _flatMap(frameValue)),
    );
    final List<DetectedObject> detections = [
      _object('person', const Rect.fromLTRB(0.4, 0.2, 0.6, 0.9)),
    ];

    final DepthScene scene1 =
        await service.analyzeScene(_frame(), detections);
    final DetectedObject person1 =
        scene1.enrichedObjects.firstWhere((o) => o.className == 'person');
    final double first = person1.distanceMeters!;
    expect(person1.distanceMeters,
        scene1.objectsWithDepth.single.depth.estimatedDistance);

    // Raw estimate moves to 0.7-nearness (farther) on frame 2.
    frameValue = 0.7;
    final DepthScene scene2 = await service.analyzeScene(_frame(), detections);
    const DepthMetricCalibration cal = DepthMetricCalibration();
    final double raw2 = cal.metersFromRelative(0.7)!;
    final double expected = first + 0.35 * (raw2 - first);
    expect(scene2.enrichedObjects.firstWhere((o) => o.className == 'person').distanceMeters,
        closeTo(expected, 0.001));
    // Frame 3 continues the glide, never jumping to the raw value.
    frameValue = 0.55;
    final DepthScene scene3 = await service.analyzeScene(_frame(), detections);
    final double expected3 =
        expected + 0.35 * (cal.metersFromRelative(0.55)! - expected);
    expect(scene3.enrichedObjects.firstWhere((o) => o.className == 'person').distanceMeters,
        closeTo(expected3, 0.001));
  });

  test('low-confidence distance is labeled approximate', () async {
    final DepthAnalysisService service = DepthAnalysisService();
    await service.initialize(
      engine: _StubEngine(
        confidence: 0.2,
        resultMap: (f, b) => _flatMap(0.85),
      ),
    );
    final List<DetectedObject> detections = [
      _object('chair', const Rect.fromLTRB(0.35, 0.55, 0.65, 0.90)),
    ];
    final DepthScene scene = await service.analyzeScene(_frame(), detections);
    final DetectedObject chair =
        scene.enrichedObjects.firstWhere((o) => o.className == 'chair');
    expect(chair.distanceMeters, isNotNull);
    expect(chair.distanceConfidence, lessThan(0.35));
    expect(chair.distanceLowConfidence, isTrue);
    expect(chair.distanceLabel, startsWith('≈'));
  });

  test('metric distance disabled -> no meters on any object', () async {
    await SettingsService.instance.setMetricDistanceEnabled(false);
    final DepthAnalysisService service = DepthAnalysisService();
    await service.initialize(
      engine: _StubEngine(resultMap: (f, b) => _flatMap(0.85)),
    );
    final List<DetectedObject> detections = [
      _object('chair', const Rect.fromLTRB(0.35, 0.55, 0.65, 0.90)),
    ];
    final DepthScene scene = await service.analyzeScene(_frame(), detections);
    final DetectedObject chair =
        scene.enrichedObjects.firstWhere((o) => o.className == 'chair');
    expect(chair.distanceMeters, isNull);
    expect(chair.distanceValueText, isNull);
    expect(chair.distanceLabel, isNull);
    expect(chair.proximity, isNotNull); // rest of pipeline keeps working
  });

  test('degenerate box boxes out -> no fabricated meters', () async {
    final DepthAnalysisService service = DepthAnalysisService();
    await service.initialize(
      engine: _StubEngine(resultMap: (f, b) => _flatMap(0.85)),
    );
    final List<DetectedObject> detections = [
      _object('chair', Rect.fromLTRB(0.5, 0.5, 0.5, 0.6)), // zero width
    ];
    final DepthScene scene = await service.analyzeScene(_frame(), detections);
    final DetectedObject chair =
        scene.enrichedObjects.firstWhere((o) => o.className == 'chair');
    expect(chair.distanceMeters, isNull);
  });

  test('normalized depth mapping is independent of frame dimensions',
      () async {
    final GeometricDepthEngine engine = GeometricDepthEngine();
    await engine.initialize();
    final DepthMap tall = engine.inferDepth(_frame(width: 16, height: 32));
    final DepthMap wide = engine.inferDepth(_frame(width: 32, height: 16));
    expect(tall.valueAt(0.5, 0.80), wide.valueAt(0.5, 0.80));
    expect(tall.valueAt(0.9, 0.50), wide.valueAt(0.9, 0.50));
  });

  test('navigation voice includes the blocker distance when available', () {
    final NavigationService nav = NavigationService();
    final DetectedObject chair = _object(
      'chair',
      const Rect.fromLTRB(0.0, 0.3, 0.3, 1.0),
      proximity: ProximityLevel.medium,
      distanceMeters: 2.43,
      distanceConfidence: 0.8,
    );
    nav.decide(
      PathAnalysisResult(
        analysis: PathAnalysis.obstacleLeft,
        leftMargin: 0.05,
        rightMargin: 0.6,
        primaryBlocker: chair,
      ),
      [chair],
    );
    expect(nav.lastDecision, NavigationDecision.right);
    expect(nav.lastSpokenMessage, 'Chair ahead, 2.4 m. Move slightly right.');
  });

  test('navigation voice without distance keeps the existing message', () {
    final NavigationService nav = NavigationService();
    final DetectedObject chair =
        _object('chair', const Rect.fromLTRB(0.0, 0.3, 0.3, 1.0));
    nav.decide(
      PathAnalysisResult(
        analysis: PathAnalysis.obstacleLeft,
        leftMargin: 0.05,
        rightMargin: 0.6,
        primaryBlocker: chair,
      ),
      [chair],
    );
    expect(nav.lastDecision, NavigationDecision.right);
    expect(nav.lastSpokenMessage, 'Chair ahead. Move slightly right.');
  });

  test('STOP message names the primary blocker when known', () {
    final NavigationService nav = NavigationService();
    final DetectedObject person =
        _object('person', const Rect.fromLTRB(0.4, 0.2, 0.6, 0.8));
    nav.decide(
      PathAnalysisResult(
        analysis: PathAnalysis.obstacleCenter,
        leftMargin: 0.1,
        rightMargin: 0.1,
        pathFullyBlocked: true,
        primaryBlocker: person,
      ),
      [person],
    );
    expect(nav.lastDecision, NavigationDecision.stop);
    expect(nav.lastSpokenMessage, 'Stop. Person very close.');
  });

  test('depth blocker prefers a named object over the synthesized ghost', () {
    final DetectedObject ghost = _object(
      'obstacle',
      const Rect.fromLTRB(0.36, 0.30, 0.64, 0.95),
      proximity: ProximityLevel.veryNear,
    );
    final DetectedObject chair = _object(
      'chair',
      const Rect.fromLTRB(0.35, 0.40, 0.65, 0.80),
      proximity: ProximityLevel.far,
    );
    final DepthScene scene = DepthScene(
      depthMap: _flatMap(0.2),
      engineType: DepthEngineType.geometric,
      usedFallback: false,
      objectsWithDepth: const [],
      enrichedObjects: [chair, ghost],
      regions: [
        _assessment(PathRegion.left, DepthBlockLevel.open),
        _assessment(PathRegion.center, DepthBlockLevel.blocked),
        _assessment(PathRegion.right, DepthBlockLevel.open),
      ],
      overallConfidence: 0.4,
      unknownObstacleDetected: true,
    );

    final PathAnalysisResult result =
        PathAnalysisService().analyzeWithDepth(const [], scene);
    expect(result.analysis, PathAnalysis.obstacleCenter);
    expect(result.primaryBlocker?.className, 'chair');
  });

  // ------------------------------------------------------------------
  // Alert mode ringer (sound / vibrate / muted)
  // ------------------------------------------------------------------

  group('alert mode ringer', () {
    tearDown(() async {
      await SettingsService.instance.setAlertMode(AlertMode.sound);
    });

    test('nextOf toggles sound <-> muted -> sound', () {
      expect(SoundModeButton.nextOf(AlertMode.sound), AlertMode.muted);
      expect(SoundModeButton.nextOf(AlertMode.muted), AlertMode.sound);
    });

    test('icon mapping covers the two remaining states', () {
      expect(SoundModeButton.iconFor(AlertMode.sound), Icons.volume_up);
      expect(SoundModeButton.iconFor(AlertMode.muted), Icons.volume_off);
    });

    test('semantic labels describe the mode without color alone', () {
      expect(SoundModeButton.labelFor(AlertMode.sound), 'Speaker mode');
      expect(SoundModeButton.labelFor(AlertMode.muted), 'Mute mode');
    });

    test('vibrate mode is removed and never reported', () async {
      final SettingsService s = SettingsService.instance;
      expect(s.vibrateMode, isFalse);
      await s.setAlertMode(AlertMode.sound);
      expect(s.vibrateMode, isFalse);
      await s.setAlertMode(AlertMode.muted);
      expect(s.vibrateMode, isFalse);
    });

    test('quick-mute from a screen syncs ringer to muted; un-mute returns to sound',
        () async {
      final SettingsService s = SettingsService.instance;
      await s.setAlertMode(AlertMode.sound);
      s.setGlobalVoiceMuted(true);
      expect(s.alertMode, AlertMode.muted);
      expect(s.globalVoiceMuted, isTrue);
      s.setGlobalVoiceMuted(false);
      expect(s.alertMode, AlertMode.sound);
      expect(s.soundAlertsEnabled, isTrue);
    });

    test('alertMode survives a reload from preferences', () async {
      await SettingsService.instance.setAlertMode(AlertMode.muted);
      await SettingsService.instance.load();
      expect(SettingsService.instance.alertMode, AlertMode.muted);
      expect(SettingsService.instance.globalVoiceMuted, isTrue);
    });

    test('legacy persisted vibrate state migrates back to sound', () async {
      SharedPreferences.setMockInitialValues({
        'setting.alertMode': 1,
        'setting.globalVoiceMuted': false,
      });
      await SettingsService.instance.load();
      expect(SettingsService.instance.alertMode, AlertMode.sound);
      expect(SettingsService.instance.globalVoiceMuted, isFalse);
    });

    test('legacy globalVoiceMuted preference migrates to muted alert mode',
        () async {
      SharedPreferences.setMockInitialValues({
        'setting.globalVoiceMuted': true,
      });
      await SettingsService.instance.load();
      expect(SettingsService.instance.alertMode, AlertMode.muted);
      expect(SettingsService.instance.globalVoiceMuted, isTrue);
    });
  });
}