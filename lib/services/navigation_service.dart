import 'package:flutter/foundation.dart';

import '../models/detected_object.dart';
import '../models/navigation_decision.dart';
import '../models/object_position.dart';
import '../models/path_analysis.dart';
import '../models/proximity_level.dart';

/// NavigationService turns path analysis into a navigation decision.
///
/// Possible decisions: FORWARD, LEFT, RIGHT, SLOW, STOP.
///
/// Safety: the system never guarantees a safe path; it reports what the
/// environment "appears" to allow based on limited camera analysis.
class NavigationService with ChangeNotifier {
  NavigationDecision _lastDecision = NavigationDecision.forward;
  String _lastReason = '';
  String _lastSpokenMessage = '';

  /// Most recent decision.
  NavigationDecision get lastDecision => _lastDecision;

  /// Human-readable reason for the current decision.
  String get lastReason => _lastReason;

  /// Message to be spoken for the current decision.
  String get lastSpokenMessage => _lastSpokenMessage;

  /// Evaluate a full scene and set the current decision.
  void decide(PathAnalysisResult path, List<DetectedObject> objects) {
    String reason = '';
    final NavigationDecision decision =
        _computeDecision(path, objects, outReason: (r) => reason = r);

    final String spoken = _spokenMessage(decision, path.primaryBlocker);

    if (decision != _lastDecision || spoken != _lastSpokenMessage) {
      print('NAVIGATION_DECISION: $decision | $spoken | $reason');
    }

    _lastDecision = decision;
    _lastReason = reason;
    _lastSpokenMessage = spoken;
    notifyListeners();
  }

  NavigationDecision _computeDecision(
    PathAnalysisResult path,
    List<DetectedObject> objects,
    {required void Function(String) outReason}) {
    if (path.analysis == PathAnalysis.clear) {
      outReason('No obstacles detected in the walking path.');
      return NavigationDecision.forward;
    }

    // 1. Immediate danger: any very-close object spanning/at the center.
    for (final obj in objects) {
      final bool spansCenter = obj.centerX >= 0.30 && obj.centerX <= 0.70;
      if (obj.proximity == ProximityLevel.veryNear && spansCenter) {
        outReason('${obj.displayName} is very close directly ahead.');
        return NavigationDecision.stop;
      }
    }

    final DetectedObject? blocker = path.primaryBlocker;
    if (blocker == null) {
      outReason('No blocking object identified.');
      return NavigationDecision.forward;
    }

    final ObjectPosition blockerPos =
        blocker.position ?? ObjectPosition.fromCenterX(blocker.centerX);
    final ProximityLevel proximity =
        blocker.proximity ?? ProximityLevel.far;

    // 2. Close obstacles demand caution.
    if (proximity == ProximityLevel.veryNear) {
      outReason('${blocker.displayName} on your ${blockerPos.label.toLowerCase()} is very close.');
      return NavigationDecision.slow;
    }
    if (proximity == ProximityLevel.near && blockerPos == ObjectPosition.center) {
      outReason('${blocker.displayName} is close and directly ahead.');
      return NavigationDecision.slow;
    }

    // 3. Manoeuvres: pick the side with more open space.
    switch (path.analysis) {
      case PathAnalysis.clear:
        outReason('Path appears clear.');
        return NavigationDecision.forward;
      case PathAnalysis.obstacleLeft:
        outReason('${blocker.displayName} on the left; right side appears free.');
        return path.rightMargin >= path.leftMargin
            ? NavigationDecision.right
            : NavigationDecision.forward;
      case PathAnalysis.obstacleRight:
        outReason('${blocker.displayName} on the right; left side appears free.');
        return path.leftMargin >= path.rightMargin
            ? NavigationDecision.left
            : NavigationDecision.forward;
      case PathAnalysis.obstacleCenter:
        final bool goLeft = path.leftMargin >= path.rightMargin;
        outReason(goLeft
            ? '${blocker.displayName} directly ahead; left side appears free.'
            : '${blocker.displayName} directly ahead; right side appears free.');
        return goLeft ? NavigationDecision.left : NavigationDecision.right;
    }
  }

  String _spokenMessage(
    NavigationDecision decision,
    DetectedObject? blocker,
  ) {
    final String label = blocker?.displayName ?? 'Object';
    switch (decision) {
      case NavigationDecision.forward:
        return 'Path appears clear. Move forward.';
      case NavigationDecision.left:
        return 'Obstacle ahead. Move slightly left.';
      case NavigationDecision.right:
        return 'Obstacle ahead. Move slightly right.';
      case NavigationDecision.slow:
        return '$label ahead. Slow down.';
      case NavigationDecision.stop:
        return 'Stop. Obstacle very close.';
    }
  }

  /// Reset the decision to the idle state.
  void reset() {
    _lastDecision = NavigationDecision.forward;
    _lastReason = '';
    _lastSpokenMessage = '';
    notifyListeners();
  }
}