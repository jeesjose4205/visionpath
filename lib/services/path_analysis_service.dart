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
}