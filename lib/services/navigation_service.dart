import 'package:flutter/foundation.dart';

import '../models/detected_object.dart';
import '../models/navigation_decision.dart';
import '../models/object_position.dart';
import '../models/path_analysis.dart';
import '../models/proximity_level.dart';
import 'scene_announcer.dart';

/// NavigationService turns path analysis into a navigation decision.
///
/// Possible decisions: FORWARD, LEFT, RIGHT, SLOW, STOP.
///
/// The spoken message is also produced here, so a screen never has to compose
/// guidance itself:
///
///   * [NavigationDecision.stop] / [NavigationDecision.slow] produce the safety
///     line ("Stop. Person very close.") and never a long object list — a
///     collision warning is never delayed by a scene description,
///   * every other decision uses [SceneAnnouncer] to name *every* relevant
///     object with its own side and its own distance in ONE sentence.
///
/// Safety: the system never guarantees a safe path; it reports what the
/// environment "appears" to allow based on limited camera analysis.
class NavigationService with ChangeNotifier {
  /// The app-wide instance.
  ///
  /// SOS has to mute guidance for the whole app, which requires the same
  /// instance the navigate screen uses rather than a per-widget copy.
  static final NavigationService instance = NavigationService();

  NavigationDecision _lastDecision = NavigationDecision.forward;
  String _lastReason = '';
  String _lastSpokenMessage = '';

  /// Builds the multi-object sentence and remembers what was already said.
  final SceneAnnouncer _announcer = SceneAnnouncer();

  /// Most recent decision.
  NavigationDecision get lastDecision => _lastDecision;

  /// Human-readable reason for the current decision.
  String get lastReason => _lastReason;

  /// Message to be spoken for the current decision.
  String get lastSpokenMessage => _lastSpokenMessage;

  /// True when the current frame describes a scene that is meaningfully
  /// different from the last one announced — a new object, a new side, or a
  /// distance that moved far enough to matter.
  ///
  /// Stays true until [commitAnnouncement] is called, so an announcement that
  /// could not be spoken yet (voice off, muted, TTS busy) is still delivered
  /// as soon as the floor is free.
  bool get announcementChanged => _announcer.hasChange;

  /// The objects the pending announcement is about.
  List<DetectedObject> get announcedObjects =>
      _announcer.pending?.members ?? const <DetectedObject>[];

  /// One complete sentence per object that needs to be spoken, already in
  /// priority order. The caller queues these; the queue guarantees they are
  /// played one at a time and never interrupted.
  ///
  /// Empty while [sceneVoiceMuted]: the microphone has priority during a
  /// press-and-hold, so detected-object sentences are withheld here rather than
  /// being queued and played over the user. Safety decisions are not scene
  /// sentences and are unaffected.
  List<String> get pendingSentences {
    if (_sceneVoiceMuted) return const <String>[];
    // A snapshot that was already handed over is not pending any more. Without
    // this the getter keeps serving the last announcement after commit(), which
    // is exactly how stale guidance gets spoken a second time.
    if (!_announcer.hasChange) return const <String>[];
    return _announcer.pending?.sentences ?? const <String>[];
  }

  /// Suppress detected-object announcements while another voice source owns the
  /// floor, typically the press-and-hold assistant listening to the user.
  ///
  /// This is the single switch for every "Chair detected." style sentence in the
  /// app: producers keep feeding [decide] so the scene state keeps advancing,
  /// and withholding the sentences here means nothing is queued, so nothing
  /// plays and nothing stale is replayed when normal speech resumes.
  bool get sceneVoiceMuted => _sceneVoiceMuted;

  set sceneVoiceMuted(bool value) {
    if (_sceneVoiceMuted == value) return;
    _sceneVoiceMuted = value;
  }

  bool _sceneVoiceMuted = false;

  /// Evaluate a full scene and set the current decision.
  ///
  /// [includeObject] is the caller's relevance filter (the per-category
  /// announcement switches); objects it rejects are left out of the spoken
  /// sentence. Null announces every valid detection.
  void decide(
    PathAnalysisResult path,
    List<DetectedObject> objects, {
    bool Function(DetectedObject object)? includeObject,
  }) {
    String reason = '';
    final NavigationDecision decision =
        _computeDecision(path, objects, outReason: (r) => reason = r);

    final String spoken =
        _spokenMessage(decision, path.primaryBlocker, objects, includeObject);

    if (decision != _lastDecision || spoken != _lastSpokenMessage) {
      print('NAVIGATION_DECISION: $decision | $spoken | $reason');
      _logScene(spoken);
    }

    _lastDecision = decision;
    _lastReason = reason;
    _lastSpokenMessage = spoken;
    notifyListeners();
  }

  /// Mark the pending announcement as delivered (spoken or given as haptics),
  /// so an unchanged scene is not announced again.
  void commitAnnouncement() => _announcer.commit();

  NavigationDecision _computeDecision(
    PathAnalysisResult path,
    List<DetectedObject> objects,
    {required void Function(String) outReason}) {
    if (path.analysis == PathAnalysis.clear) {
      outReason('No obstacles detected in the walking path.');
      return NavigationDecision.forward;
    }

    // Both lateral regions blocked: there is no side to manoeuvre to.
    if (path.pathFullyBlocked) {
      outReason('Path is blocked on both sides.');
      return NavigationDecision.stop;
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

  /// Build the message for this decision.
  ///
  /// Safety decisions (STOP/SLOW) keep their own short, urgent line and drop
  /// any queued scene sentence, so a collision warning is never delayed. Every
  /// other decision is described by the scene announcer, which produces one
  /// complete sentence per object that actually changed.
  String _spokenMessage(
    NavigationDecision decision,
    DetectedObject? blocker,
    List<DetectedObject> objects,
    bool Function(DetectedObject object)? includeObject,
  ) {
    switch (decision) {
      case NavigationDecision.stop:
      case NavigationDecision.slow:
        // The safety message is driven by the decision cooldown, not by the
        // scene's change detection. The pending scene sentence is dropped so it
        // can never queue behind the warning, while object history survives so
        // an unchanged object is not re-announced once the hazard is gone.
        _announcer.suppressPending();
        return _safetyMessage(decision, blocker);
      case NavigationDecision.forward:
      case NavigationDecision.left:
      case NavigationDecision.right:
        final SceneAnnouncement? scene = _announcer.compose(
          detections: objects,
          primaryBlocker: blocker,
          include: includeObject,
        );
        if (scene == null) return _clearOrDetourMessage(decision, blocker);
        return scene.sentences.isEmpty
            ? _clearOrDetourMessage(decision, blocker)
            : scene.sentences.join(' ');
    }
  }

  /// Urgent obstacle line: names the real class, never a generic word when
  /// the model knows what it saw.
  String _safetyMessage(
    NavigationDecision decision,
    DetectedObject? blocker,
  ) {
    final String label = blocker?.displayName ?? 'Object';
    final String distance = blocker?.distanceValueText ?? '';
    switch (decision) {
      case NavigationDecision.forward:
        return 'Path appears clear. Move forward.';
      case NavigationDecision.left:
        return distance.isEmpty
            ? '$label ahead. Move slightly left.'
            : '$label ahead, $distance. Move slightly left.';
      case NavigationDecision.right:
        return distance.isEmpty
            ? '$label ahead. Move slightly right.'
            : '$label ahead, $distance. Move slightly right.';
      case NavigationDecision.slow:
        return distance.isEmpty
            ? '$label ahead. Slow down.'
            : '$label ahead, $distance. Slow down.';
      case NavigationDecision.stop:
        return blocker == null
            ? 'Stop. Obstacle very close.'
            : 'Stop. $label very close.';
    }
  }

  /// Wording when the frame holds no identifiable object at all: report the
  /// path, never invent an object.
  String _clearOrDetourMessage(
    NavigationDecision decision,
    DetectedObject? blocker,
  ) {
    if (decision == NavigationDecision.forward) {
      return 'Path appears clear. Move forward.';
    }
    final String label = blocker?.displayName ?? 'Object';
    return decision == NavigationDecision.left
        ? 'Move slightly left. $label ahead.'
        : 'Move slightly right. $label ahead.';
  }

  /// One compact block per announcement change (never per camera frame), so
  /// the log stays readable while a run is being diagnosed.
  void _logScene(String spoken) {
    final StringBuffer buffer = StringBuffer('NAV_SCENE: ');
    for (int i = 0; i < announcedObjects.length; i++) {
      final DetectedObject obj = announcedObjects[i];
      if (i > 0) buffer.write(' | ');
      buffer.write(
        '${obj.displayName} ${(obj.position ?? ObjectPosition.fromCenterX(obj.centerX)).label} '
        '${obj.distanceValueText ?? 'depth n/a'} '
        'conf=${(obj.confidence * 100).toInt()}%',
      );
    }
    buffer.write(' -> "$spoken"');
    print(buffer.toString());
  }

  /// Reset the decision to the idle state.
  void reset() {
    _lastDecision = NavigationDecision.forward;
    _lastReason = '';
    _lastSpokenMessage = '';
    // A stopped run leaves nobody listening, so the next run must not inherit a
    // mute that was only meant for a press-and-hold.
    _sceneVoiceMuted = false;
    // Nothing is pending any more: a stopped run can never announce, and the
    // next run starts from a clean scene instead of the previous one.
    _announcer.reset();
    notifyListeners();
  }
}
