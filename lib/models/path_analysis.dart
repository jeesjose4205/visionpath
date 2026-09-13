import 'detected_object.dart';

/// High-level assessment of whether the user's walking path is obstructed.
enum PathAnalysis {
  clear('CLEAR'),
  obstacleLeft('OBSTACLE_LEFT'),
  obstacleCenter('OBSTACLE_CENTER'),
  obstacleRight('OBSTACLE_RIGHT');

  const PathAnalysis(this.label);

  /// Display label (e.g., "CLEAR").
  final String label;
}

/// Combined result of a single path-analysis pass.
///
/// Holds the scene classification and the primary blocking object (if any).
class PathAnalysisResult {
  /// The scene classification.
  final PathAnalysis analysis;

  /// The single object considered most blocking (null when CLEAR).
  final DetectedObject? primaryBlocker;

  /// Approximate fraction of the normalized frame width that is free on the
  /// left side (0.0-1.0). Used by the navigation decision engine.
  final double leftMargin;

  /// Approximate fraction of the normalized frame width that is free on the
  /// right side (0.0-1.0).
  final double rightMargin;

  const PathAnalysisResult({
    required this.analysis,
    this.primaryBlocker,
    required this.leftMargin,
    required this.rightMargin,
  });
}