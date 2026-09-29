import '../models/depth_result.dart';
import '../models/depth_scene.dart';
import '../models/detected_object.dart';
import '../models/object_position.dart';
import '../models/path_analysis.dart';
import '../models/proximity_level.dart';

/// PathAnalysisService decides whether detected objects are likely to
/// interfere with the user's walking path.
///
/// It does NOT treat every detection as an obstacle: irrelevant distant
/// objects and objects far outside the central walking region are deprioritized.
class PathAnalysisService {
  /// Fraction of the frame used as the "central walking region" band.
  static const double walkingRegionLeft = 0.28;
  static const double walkingRegionRight = 0.72;

  /// Analyze the combined scene and return the scene classification plus free
  /// horizontal margins.
  PathAnalysisResult analyze(List<DetectedObject> objects) {
    print('PATH_ANALYSIS_START: ${objects.length} objects');

    if (objects.isEmpty) {
      print('PATH_ANALYSIS: CLEAR (no objects)');
      return const PathAnalysisResult(
        analysis: PathAnalysis.clear,
        leftMargin: 1.0,
        rightMargin: 1.0,
      );
    }

    // Free margins: measure the open normalized width on each side before
    // hitting any object's occupied span.
    double leftEdgeBlock = 1.0;
    double rightEdgeBlock = 0.0;

    for (final obj in objects) {
      final double spanLeft =
          (obj.centerX - obj.boundingBox.width / 2).clamp(0.0, 1.0);
      final double spanRight =
          (obj.centerX + obj.boundingBox.width / 2).clamp(0.0, 1.0);

      if (spanLeft < leftEdgeBlock) leftEdgeBlock = spanLeft;
      if (spanRight > rightEdgeBlock) rightEdgeBlock = spanRight;
    }

    final double leftMargin = leftEdgeBlock.clamp(0.0, 1.0);
    final double rightMargin = (1.0 - rightEdgeBlock).clamp(0.0, 1.0);

    // Pick the primary blocker: prefer objects in the central walking region,
    // then by proximity rank, then by box area.
    PathAnalysis primary;

    final List<DetectedObject> considered = objects.where((obj) {
      final bool inWalkingRegion =
          obj.centerX >= walkingRegionLeft && obj.centerX <= walkingRegionRight;
      final bool close = (obj.proximity ?? ProximityLevel.far).index >=
          ProximityLevel.medium.index;
      return inWalkingRegion || close;
    }).toList();

    final List<DetectedObject> pool =
        considered.isEmpty ? objects : considered;

    final DetectedObject primaryBlocker = pool.reduce((a, b) {
      final int proximityScoreA = a.proximity?.index ?? ProximityLevel.far.index;
      final int proximityScoreB = b.proximity?.index ?? ProximityLevel.far.index;
      if (proximityScoreA != proximityScoreB) {
        return proximityScoreA > proximityScoreB ? a : b;
      }
      final double areaA = a.boundingBox.width * a.boundingBox.height;
      final double areaB = b.boundingBox.width * b.boundingBox.height;
      return areaA >= areaB ? a : b;
    });

    final ObjectPosition blockerPos =
        primaryBlocker.position ?? ObjectPosition.fromCenterX(primaryBlocker.centerX);

    switch (blockerPos) {
      case ObjectPosition.left:
        primary = PathAnalysis.obstacleLeft;
        break;
      case ObjectPosition.center:
        primary = PathAnalysis.obstacleCenter;
        break;
      case ObjectPosition.right:
        primary = PathAnalysis.obstacleRight;
        break;
    }

    print('PATH_ANALYSIS_PRIMARY: ${primaryBlocker.displayName} pos=${blockerPos.label} proximity=${primaryBlocker.proximity?.label ?? 'N/A'}');
    print('PATH_ANALYSIS_RESULT: $primary leftMargin=${leftMargin.toStringAsFixed(2)} rightMargin=${rightMargin.toStringAsFixed(2)}');

    return PathAnalysisResult(
      analysis: primary,
      primaryBlocker: primaryBlocker,
      leftMargin: leftMargin,
      rightMargin: rightMargin,
    );
  }

  // ------------------------------------------------------------------
  // Depth-augmented path analysis
  // ------------------------------------------------------------------

  /// Analyze the scene using depth evidence as the primary signal.
  ///
  /// Region blocking levels from the depth map (including depth-only,
  /// "unknown" obstacles) drive the classification; detected-object proximity
  /// from depth fills in the remaining object-driven cases. Both lateral
  /// regions blocked -> [PathAnalysis.obstacleCenter] with
  /// [PathAnalysisResult.pathFullyBlocked] so navigation stops.
  PathAnalysisResult analyzeWithDepth(
    List<ObjectWithDepth> objectsWithDepth,
    DepthScene scene,
  ) {
    print('PATH_ANALYSIS_DEPTH_START: ${objectsWithDepth.length} objects');

    final PathRegionAssessment left = scene.regionOf(PathRegion.left);
    final PathRegionAssessment center = scene.regionOf(PathRegion.center);
    final PathRegionAssessment right = scene.regionOf(PathRegion.right);

    final bool leftBlocked = left.blockLevel != DepthBlockLevel.open;
    final bool centerBlocked = center.blockLevel != DepthBlockLevel.open;
    final bool rightBlocked = right.blockLevel != DepthBlockLevel.open;

    // Free margins from depth evidence.
    double leftMargin = 1.0;
    double rightMargin = 1.0;
    if (centerBlocked) {
      leftMargin = 0.10;
      rightMargin = 0.10;
    }
    if (leftBlocked) {
      leftMargin =
          left.blockLevel == DepthBlockLevel.blocked ? 0.05 : 0.25;
    }
    if (rightBlocked) {
      rightMargin =
          right.blockLevel == DepthBlockLevel.blocked ? 0.05 : 0.25;
    }
    leftMargin = leftMargin.clamp(0.0, 1.0);
    rightMargin = rightMargin.clamp(0.0, 1.0);

    PathAnalysis primary;
    bool fullyBlocked = false;
    if (leftBlocked && rightBlocked) {
      primary = PathAnalysis.obstacleCenter;
      fullyBlocked = true;
    } else if (centerBlocked) {
      primary = PathAnalysis.obstacleCenter;
    } else if (leftBlocked) {
      primary = PathAnalysis.obstacleLeft;
    } else if (rightBlocked) {
      primary = PathAnalysis.obstacleRight;
    } else {
      // No depth-blocked region: fall back to object-driven assessment.
      final bool veryNear =
          objectsWithDepth.any((od) => od.depth.proximity == ProximityLevel.veryNear);
      primary = veryNear
          ? PathAnalysis.obstacleCenter
          : PathAnalysis.clear;
    }

    final DetectedObject? blocker = _pickBlocker(
      scene.enrichedObjects,
      primary,
    );

    print(
      'PATH_ANALYSIS_DEPTH_RESULT: $primary '
      'leftMargin=${leftMargin.toStringAsFixed(2)} '
      'rightMargin=${rightMargin.toStringAsFixed(2)} '
      'fullyBlocked=$fullyBlocked '
      'blocker=${blocker?.displayName ?? 'none'}',
    );

    return PathAnalysisResult(
      analysis: primary,
      primaryBlocker: blocker,
      leftMargin: leftMargin,
      rightMargin: rightMargin,
      pathFullyBlocked: fullyBlocked,
    );
  }

  /// Pick the primary blocker from the enriched object list (which includes
  /// synthesized depth-only obstacles) matching [primary]'s region, highest
  /// proximity first, then box area.
  DetectedObject? _pickBlocker(
    List<DetectedObject> enriched,
    PathAnalysis primary,
  ) {
    if (primary == PathAnalysis.clear) return null;

    final List<DetectedObject> matching = enriched.where((obj) {
      final double cx = obj.centerX;
      return switch (primary) {
        PathAnalysis.clear => false,
        PathAnalysis.obstacleLeft => cx < 1.0 / 3.0,
        PathAnalysis.obstacleCenter => cx >= 1.0 / 3.0 && cx <= 2.0 / 3.0,
        PathAnalysis.obstacleRight => cx > 2.0 / 3.0,
      };
    }).toList();
    if (matching.isEmpty) return null;

    matching.sort((a, b) {
      // Prefer real, named detections over synthesized depth-only "obstacle"
      // ghosts so guidance announces "Chair ahead..." instead of the generic
      // "Obstacle ahead...". The synthesized blob is still the fallback when
      // no named object occupies the blocked region.
      final bool ghostA = a.className.toLowerCase() == 'obstacle';
      final bool ghostB = b.className.toLowerCase() == 'obstacle';
      if (ghostA != ghostB) return ghostA ? 1 : -1;
      final int proxDiff = (b.proximity?.index ?? 0) - (a.proximity?.index ?? 0);
      if (proxDiff != 0) return proxDiff;
      final double areaA = a.boundingBox.width * a.boundingBox.height;
      final double areaB = b.boundingBox.width * b.boundingBox.height;
      return areaB.compareTo(areaA);
    });
    return matching.first;
  }
}