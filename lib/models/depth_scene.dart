import 'depth_map.dart';
import 'depth_result.dart';
import 'detected_object.dart';
import 'rgb_frame.dart';

/// Horizontal walking-path region of the frame.
enum PathRegion { left, center, right }

/// How blocked a walking region appears from depth evidence alone.
enum DepthBlockLevel { open, partiallyBlocked, blocked }

/// Which depth approach produced a scene.
enum DepthEngineType { geometric, fallback }

/// Depth assessment for one walking region (LEFT / CENTER / RIGHT).
class PathRegionAssessment {
  final PathRegion region;

  /// Fraction of walkable-band cells considered open/clear (0..1).
  final double openRatio;

  /// Nearest (maximum) relative depth found in the walkable band (0..1).
  final double nearestDepth;

  /// Smoothed blocking level.
  final DepthBlockLevel blockLevel;

  /// Confidence of this assessment (0..1).
  final double confidence;

  const PathRegionAssessment({
    required this.region,
    required this.openRatio,
    required this.nearestDepth,
    required this.blockLevel,
    required this.confidence,
  });
}

/// Full depth-analysis result for one camera frame.
class DepthScene {
  /// The upright RGB frame the analysis ran on (kept for debug overlays).
  final RgbFrame? frame;

  /// The raw (unsmoothed) per-cell depth map for this frame.
  final DepthMap depthMap;

  /// Engine that produced the map ([DepthEngineType.geometric] or fallback).
  final DepthEngineType engineType;

  /// True when depth inference was unavailable and box heuristics were used.
  final bool usedFallback;

  /// Human-readable reason for the fallback (null when real depth ran).
  final String? fallbackReason;

  /// Real detected objects paired with their depth results.
  final List<ObjectWithDepth> objectsWithDepth;

  /// Objects with proximity applied, INCLUDING synthesized depth-only
  /// obstacles (className "obstacle") inserted by the pipeline.
  final List<DetectedObject> enrichedObjects;

  /// Per-region assessments (LEFT, CENTER, RIGHT order).
  final List<PathRegionAssessment> regions;

  /// Overall confidence in the scene analysis (0..1).
  final double overallConfidence;

  /// True when a region was blocked with no detected object responsible
  /// (a depth-only / unknown obstacle).
  final bool unknownObstacleDetected;

  const DepthScene({
    this.frame,
    required this.depthMap,
    required this.engineType,
    required this.usedFallback,
    this.fallbackReason,
    required this.objectsWithDepth,
    required this.enrichedObjects,
    required this.regions,
    required this.overallConfidence,
    required this.unknownObstacleDetected,
  });

  PathRegionAssessment regionOf(PathRegion region) =>
      regions.firstWhere((r) => r.region == region);

  /// Both lateral regions are at least partially blocked.
  bool get bothSidesBlocked {
    final PathRegionAssessment left = regionOf(PathRegion.left);
    final PathRegionAssessment right = regionOf(PathRegion.right);
    return left.blockLevel != DepthBlockLevel.open &&
        right.blockLevel != DepthBlockLevel.open;
  }
}