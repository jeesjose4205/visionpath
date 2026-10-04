import 'package:flutter/foundation.dart';

import '../models/detected_object.dart';
import '../models/navigation_decision.dart';
import '../models/object_position.dart';
import '../models/proximity_level.dart';
import '../models/target_search.dart';
import 'object_vocabulary.dart';

/// TargetNavigationService turns "find a chair" into spoken guidance.
///
/// The service is a thin, camera-agnostic brain that sits on top of the
/// existing Navigation pipeline:
///
///   * [handleCommand] parses a spoken/typed request and starts a session
///     (or explains that the object cannot be detected),
///   * [updateFrame] is fed every analysed frame with the detections and the
///     current [NavigationDecision],
///   * guidance lines are queued for the screen to speak, and [state] feeds the
///     minimal on-screen target chip.
///
/// Safety always wins: while an obstacle is being reported the service tracks
/// silently and holds its messages back, so the obstacle is what the user
/// hears. Nothing here owns the camera, the model or the voice — it only
/// decides what to say about the target.
class TargetNavigationService with ChangeNotifier {
  /// App-wide instance used by the assistant hook and the Navigation screen.
  static final TargetNavigationService instance = TargetNavigationService();

  /// Consecutive frames a candidate must survive before it counts as the
  /// target. Two frames at the 5 FPS sampling rate filters single-frame
  /// detection flicker without feeling slow.
  static const int confirmationFrames = 2;

  /// Frames the target may stay unseen before the search falls back to
  /// searching. Six frames at 5 FPS is about a second of grace, enough to walk
  /// a target out of the frame and back in, and still inside the 1-2 second
  /// window a user tolerates before deciding the target is gone.
  static const int lostGraceFrames = 6;

  /// The grace above expressed as a duration, for documentation and tests.
  static const Duration lostGracePeriod = Duration(milliseconds: 1200);

  /// Distance bands used for guidance phrasing.
  static const double farDistanceMeters = 3.0;
  static const double nearDistanceMeters = 1.5;

  /// Close enough that the user should be told to slow down rather than keep
  /// walking. Kept above [reachedDistanceMeters] so "slow down" is spoken just
  /// before arrival instead of never.
  static const double veryCloseDistanceMeters = 1.2;

  /// How close the user has to get before the target counts as reached.
  static const double reachedDistanceMeters = 0.8;

  /// How far the target must change distance before the new distance is worth
  /// speaking. Without this the guidance repeats itself on every frame the user
  /// simply stands still.
  static const double distanceChangeThresholdMeters = 0.3;

  /// Minimum gap between two non-event guidance lines.
  static const Duration guidanceCooldown = Duration(milliseconds: 4000);

  final DateTime Function() _clock;

  TargetNavigationService({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  // ------------------------------------------------------------------
  // State
  // ------------------------------------------------------------------

  TargetSearchPhase _phase = TargetSearchPhase.idle;
  String _targetName = '';

  /// Every YOLO class name the request can refer to ("sofa" -> {couch}).
  final Set<String> _targetClasses = <String>{};

  /// Incremented per started session; late frames from an older session are
  /// dropped by [updateFrame] so a previous target can never speak again.
  int _sessionId = 0;
  int? _runId;

  bool _pipelineActive = false;
  bool _confirmed = false;
  int _confirmCount = 0;
  int _lostCount = 0;
  bool _clearAfterReached = false;

  ObjectPosition? _position;
  double? _distanceMeters;
  ObjectPosition? _lastGuidancePosition;
  String? _lastGuidanceBand;

  /// Distance already spoken to the user, used to apply
  /// [distanceChangeThresholdMeters].
  double? _lastGuidanceMeters;

  /// Queued event lines (found / lost / reached) — always delivered, in order,
  /// and never dropped because an obstacle took priority this frame.
  final List<String> _events = <String>[];

  /// Latest non-event guidance line (position / distance update).
  String? _guidance;
  DateTime? _lastGuidanceAt;

  /// Lines waiting to be spoken by the owner of the voice channel.
  final List<String> _outbox = <String>[];

  bool _disposed = false;

  /// Immutable snapshot for the status chip.
  TargetSearchState get state => TargetSearchState(
        phase: _phase,
        targetName: _targetName,
        position: _position,
        distanceMeters: _distanceMeters,
        confirmed: _confirmed,
      );

  /// True while a search is running (target requested, not yet reached).
  bool get isActive =>
      _phase == TargetSearchPhase.searching ||
      _phase == TargetSearchPhase.tracking;

  TargetSearchPhase get phase => _phase;

  /// Identifier of the current/most recent session (0 when never started).
  int get sessionId => _sessionId;

  /// Display name of the target ("Chair"), empty when idle.
  String get targetName => _targetName;

  /// Canonical YOLO class names being searched for.
  Set<String> get targetClasses => Set<String>.unmodifiable(_targetClasses);

  /// Lines queued but not yet spoken.
  List<String> get pendingMessages => List<String>.unmodifiable(_outbox);

  // ------------------------------------------------------------------
  // Command parsing
  // ------------------------------------------------------------------

  /// Utterances that start a target search.
  static final List<RegExp> _startPatterns = <RegExp>[
    RegExp(r'\b(?:please\s+)?(?:find|locate)\b'),
    RegExp(r'\b(?:look|search)\s+for\b'),
    RegExp(r'\bwhere\s+(?:is|are)\b'),
    RegExp(r'\b(?:go|navigate|head|walk|travel|move)\s+(?:over\s+)?to\b'),
    RegExp(r'\b(?:take|bring|lead|show|get)\s+(?:me\s+)?to\b'),
    RegExp(r'\b(?:find|show|get)\s+me\b'),
  ];

  /// Utterances that end the current search.
  static final List<RegExp> _stopPatterns = <RegExp>[
    RegExp(r'\bstop\s+(?:searching|looking|seeking|target|finding)\b'),
    RegExp(r'\bcancel\s+(?:the\s+)?(?:search|searching|target|look|navigation|guidance)\b'),
    RegExp(r'\bstop\s+(?:navigating|going|guiding)\b'),
    RegExp(r'\bnever\s?mind\b'),
    RegExp(r'\bforget\s+(?:it|that|the\s+\w+|about\s+it)\b'),
    RegExp(r'\bno\s+more\s+(?:searching|looking|tracking)\b'),
  ];

  /// Bare "Stop." / "Cancel." only end a search, they never start one. They are
  /// matched on the whole utterance so "Take me to the bus stop" is unaffected.
  static const Set<String> _bareStopWords = <String>{
    'stop',
    'cancel',
    'nevermind',
    'never mind',
    'forget it',
  };

  /// Words that carry no object meaning and are stripped from the phrase.
  static const Set<String> _fillerWords = <String>{
    'the', 'a', 'an', 'my', 'me', 'is', 'are', 'am', 'to', 'for', 'of', 'it',
    'that', 'this', 'one', 'please', 'can', 'you', 'could', 'would', 'will',
    'near', 'nearest', 'closest', 'some', 'any', 'over', 'there', 'here',
    'just', 'now', 'then', 'and',
  };

  /// Parse [utterance] into a target command. Never throws and never guesses:
  /// an object the model cannot see comes back as
  /// [TargetCommandKind.unsupported] instead of a silent no-op.
  static TargetCommand parseCommand(String utterance) {
    final String cleaned = utterance
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .join(' ')
        .trim();
    if (cleaned.isEmpty) return const TargetCommand.none();

    if (_bareStopWords.contains(cleaned)) {
      return const TargetCommand(kind: TargetCommandKind.stop);
    }

    for (final pattern in _stopPatterns) {
      if (pattern.hasMatch(cleaned)) {
        return const TargetCommand(kind: TargetCommandKind.stop);
      }
    }

    int tailStart = -1;
    for (final pattern in _startPatterns) {
      final match = pattern.firstMatch(cleaned);
      if (match != null) {
        tailStart = match.end;
        break;
      }
    }
    if (tailStart < 0) return const TargetCommand.none();

    final String tail = cleaned.substring(tailStart);
    final List<String> words = tail
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !_fillerWords.contains(w))
        .map(ObjectVocabulary.singular)
        .toList();
    if (words.isEmpty) return const TargetCommand.none();

    final String phrase = words.join(' ');
    final List<String> classes = ObjectVocabulary.resolvePhrase(phrase);
    if (classes.isEmpty) {
      return TargetCommand(kind: TargetCommandKind.unsupported, phrase: phrase);
    }
    return TargetCommand(
      kind: TargetCommandKind.start,
      phrase: phrase,
      classes: classes,
    );
  }

  /// Handle a spoken or typed request. Returns true when the utterance was a
  /// target-navigation command (so the assistant must not also answer it).
  bool handleCommand(String utterance) {
    final TargetCommand command = parseCommand(utterance);
    switch (command.kind) {
      case TargetCommandKind.none:
        return false;
      case TargetCommandKind.start:
        _startTarget(command);
        return true;
      case TargetCommandKind.stop:
        _stopFromCommand();
        return true;
      case TargetCommandKind.unsupported:
        _enqueue("I can't identify that object with the current camera.");
        print('TARGET_NAV_UNSUPPORTED: "${command.phrase}"');
        _notify();
        return true;
    }
  }

  // ------------------------------------------------------------------
  // Session control
  // ------------------------------------------------------------------

  /// Tell the service whether the camera pipeline is running, so a request
  /// given before navigation starts is answered instead of silently hanging.
  void setPipelineActive(bool active, {int? runId}) {
    _pipelineActive = active;
    if (active) {
      _runId = runId;
      return;
    }
    // Navigation stopped: any target session dies with it, without speaking.
    _reset();
    _runId = null;
    _notify();
  }

  void _startTarget(TargetCommand command) {
    if (!_pipelineActive) {
      _enqueue('Start navigation first, then ask me to find it.');
      print('TARGET_NAV_PIPELINE_INACTIVE: "${command.phrase}"');
      _notify();
      return;
    }

    _sessionId++;
    _targetClasses
      ..clear()
      ..addAll(command.classes);
    _targetName = _displayName(command.className!);
    _phase = TargetSearchPhase.searching;
    _confirmed = false;
    _confirmCount = 0;
    _lostCount = 0;
    _clearAfterReached = false;
    _position = null;
    _distanceMeters = null;
    _lastGuidancePosition = null;
    _lastGuidanceBand = null;
    _lastGuidanceMeters = null;
    _events.clear();
    _guidance = null;
    _lastGuidanceAt = null;

    _enqueue('Searching for a $_targetName.');
    print('TARGET_NAV_START: session=$_sessionId target=$_targetName '
        'classes=$_targetClasses');
    _notify();
  }

  void _stopFromCommand() {
    if (!isActive && _targetName.isEmpty) {
      _enqueue('There is no target search running.');
      _notify();
      return;
    }
    final String name = _targetName;
    _reset();
    _enqueue('Stopped looking for the $name.');
    print('TARGET_NAV_STOPPED_BY_COMMAND: $name');
    _notify();
  }

  /// End the current search, announcing it to the user.
  void stopTarget() {
    if (_targetName.isEmpty) return;
    final String name = _targetName;
    _reset();
    _enqueue('Stopped looking for the $name.');
    _notify();
  }

  void _reset() {
    _phase = TargetSearchPhase.idle;
    _targetClasses.clear();
    _targetName = '';
    _confirmed = false;
    _confirmCount = 0;
    _lostCount = 0;
    _clearAfterReached = false;
    _position = null;
    _distanceMeters = null;
    _lastGuidancePosition = null;
    _lastGuidanceBand = null;
    _lastGuidanceMeters = null;
    _events.clear();
    _guidance = null;
    _lastGuidanceAt = null;
  }

  // ------------------------------------------------------------------
  // Per-frame tracking
  // ------------------------------------------------------------------

  /// Feed one analysed frame.
  ///
  /// [detections] are the enriched detections of this frame (position and
  /// calibrated distance already applied) and [decision] is the safety
  /// decision produced for the same frame. Target guidance is only queued when
  /// the path is clear; an obstacle always takes the floor.
  void updateFrame({
    required List<DetectedObject> detections,
    required NavigationDecision decision,
    int? runId,
  }) {
    if (runId != null && _runId != null && runId != _runId) return;

    // Reached is reported once, then the session ends and normal navigation
    // takes over completely.
    if (_clearAfterReached) {
      _clearAfterReached = false;
      _reset();
      _notify();
      return;
    }
    if (!isActive) return;

    final DetectedObject? best = _nearestTarget(detections);
    final bool pathClear = decision == NavigationDecision.forward;

    if (best != null) {
      _lostCount = 0;
      _confirmCount++;
      _position = best.position ?? ObjectPosition.fromCenterX(best.centerX);
      _distanceMeters = best.distanceMeters;

      if (!_confirmed && _confirmCount >= confirmationFrames) {
        _confirmed = true;
        _phase = TargetSearchPhase.tracking;
        _events.add(_foundMessage());
        print('TARGET_NAV_FOUND: session=$_sessionId $_targetName '
            'pos=$_position dist=$_distanceMeters');
      } else if (_confirmed) {
        if (_isReached(best)) {
          _events.add('You have reached the $_targetName.');
          _phase = TargetSearchPhase.reached;
          _clearAfterReached = true;
          _confirmed = false;
          print('TARGET_NAV_REACHED: session=$_sessionId $_targetName');
        } else {
          _updateGuidance(best);
        }
      }
    } else {
      _confirmCount = 0;
      if (_confirmed) {
        _lostCount++;
        if (_lostCount > lostGraceFrames) {
          _confirmed = false;
          _lostCount = 0;
          _phase = TargetSearchPhase.searching;
          _position = null;
          _distanceMeters = null;
          _events.add(
            "I can't see the $_targetName right now. Please turn slowly.",
          );
          print('TARGET_NAV_LOST: session=$_sessionId $_targetName');
        }
      }
    }

    if (pathClear) {
      if (_events.isNotEmpty) {
        // Events (found / lost / reached) are rare and important: they never
        // consume the guidance cooldown, so the first position or distance
        // update after "Found the chair" still comes through.
        _enqueue(_events.removeAt(0));
        _guidance = null;
      } else if (_guidance != null && _cooldownElapsed()) {
        // Guidance repeats (a target flip-flopping between two sides at the
        // 5 FPS sampling rate) is held back by the cooldown.
        _enqueue(_guidance!);
        _lastGuidanceAt = _clock();
        _guidance = null;
      }
    }

    _notify();
  }

  /// The closest detection belonging to the target classes.
  ///
  /// Calibrated meters decide when any target detection carries one; otherwise
  /// the biggest box wins, which is the same apparent-size cue the proximity
  /// heuristic uses.
  DetectedObject? _nearestTarget(List<DetectedObject> detections) {
    final List<DetectedObject> matches = detections
        .where((o) => _targetClasses.contains(o.className.toLowerCase()))
        .toList();
    if (matches.isEmpty) return null;

    final List<DetectedObject> measured =
        matches.where((o) => o.distanceMeters != null).toList();
    if (measured.isNotEmpty) {
      measured.sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
      return measured.first;
    }

    DetectedObject best = matches.first;
    double bestArea = best.boundingBox.width * best.boundingBox.height;
    for (final obj in matches.skip(1)) {
      final double area = obj.boundingBox.width * obj.boundingBox.height;
      if (area > bestArea) {
        bestArea = area;
        best = obj;
      }
    }
    return best;
  }

  bool _isReached(DetectedObject target) {
    final double? distance = target.distanceMeters;
    if (distance != null && distance <= reachedDistanceMeters) return true;
    // No metric estimate: the app's own proximity scale still says the object
    // fills the view, which is the same "you are there" cue used elsewhere.
    return target.proximity == ProximityLevel.veryNear;
  }

  /// First sighting of the target: "Chair detected, 4.2 meters to your left."
  /// A distance is always included when depth produced one, however close.
  String _foundMessage() {
    final String where = _positionPhrase(_position);
    final String distance = _spokenDistance(_distanceMeters);
    if (distance.isEmpty) return '$_targetName detected, $where.';
    return '$_targetName detected, $distance $where.';
  }

  void _updateGuidance(DetectedObject target) {
    final ObjectPosition position =
        target.position ?? ObjectPosition.fromCenterX(target.centerX);
    final String where = _positionPhrase(position);
    final double? meters = target.distanceMeters;
    final String spoken = _spokenDistance(meters);

    // A new side is always worth saying, whatever the distance did.
    if (position != _lastGuidancePosition) {
      _lastGuidancePosition = position;
      _lastGuidanceMeters = meters;
      _lastGuidanceBand = _distanceBand(target);
      _guidance = _approachSentence(target, where, spoken);
      return;
    }

    if (meters != null) {
      // With a calibrated distance the 0.3 m rule is the only thing that
      // decides: a smaller wobble would just repeat the same sentence with new
      // numbers, and crossing a coarse band is not news on its own.
      if (!_distanceMovedEnough(meters)) return;
      _lastGuidanceMeters = meters;
      _lastGuidanceBand = _distanceBand(target);
      _guidance = _approachSentence(target, where, spoken);
      return;
    }

    // Without depth, the box-size proximity band is all there is to go on.
    final String band = _distanceBand(target);
    if (band == _lastGuidanceBand) return;
    _lastGuidanceMeters = null;
    _lastGuidanceBand = band;
    _guidance = _approachSentence(target, where, spoken);
  }

  /// One approach line, reusing the same direction wording the navigation
  /// service already speaks so a target and an obstacle read the same way:
  /// "Move slightly left. Chair is 2.8 meters to your left."
  String _approachSentence(
    DetectedObject target,
    String where,
    String spoken,
  ) {
    final String target_clause = spoken.isEmpty
        ? '$_targetName is $where.'
        : '$_targetName is $spoken $where.';

    // Very close: stop walking forward before anything else is said.
    if (target.proximity == ProximityLevel.veryNear ||
        (_distanceMeters != null &&
            _distanceMeters! <= veryCloseDistanceMeters)) {
      return spoken.isEmpty
          ? '$_targetName is very close. Slow down.'
          : '$target_clause Slow down.';
    }

    return '${_steerPhrase(target)} $target_clause';
  }

  /// The steering half of an approach line, taken from the target's own box
  /// position rather than a second navigation engine.
  static String _steerPhrase(DetectedObject target) {
    final ObjectPosition position =
        target.position ?? ObjectPosition.fromCenterX(target.centerX);
    switch (position) {
      case ObjectPosition.left:
        return 'Move slightly left.';
      case ObjectPosition.right:
        return 'Move slightly right.';
      case ObjectPosition.center:
        return 'Continue straight.';
    }
  }

  /// True when [meters] differs from the last spoken distance by at least
  /// [distanceChangeThresholdMeters]. A distance that was never spoken is
  /// always news; an unknown one never is.
  ///
  /// The comparison carries a small epsilon because binary floating point makes
  /// 3.3 - 3.0 a hair under 0.3, which would silently drop the exact reading
  /// the threshold is meant to speak.
  bool _distanceMovedEnough(double? meters) {
    if (meters == null) return false;
    final double? last = _lastGuidanceMeters;
    if (last == null) return true;
    return (meters - last).abs() >=
        distanceChangeThresholdMeters - _distanceEpsilon;
  }

  /// Slack for the threshold comparison, well below any real movement.
  static const double _distanceEpsilon = 1e-6;

  String _distanceBand(DetectedObject target) {
    final double? meters = target.distanceMeters;
    if (meters != null) {
      if (meters <= nearDistanceMeters) return 'close';
      if (meters <= farDistanceMeters) return 'medium';
      return 'far';
    }
    // No metric estimate: the app's own box-size proximity is still a usable,
    // if coarser, signal that the target is getting nearer.
    switch (target.proximity) {
      case ProximityLevel.veryNear:
      case ProximityLevel.near:
        return 'close';
      case ProximityLevel.medium:
        return 'medium';
      case ProximityLevel.far:
        return 'far';
      case null:
        return 'unknown';
    }
  }

  bool _cooldownElapsed() {
    final DateTime? last = _lastGuidanceAt;
    if (last == null) return true;
    return _clock().difference(last) >= guidanceCooldown;
  }

  // ------------------------------------------------------------------
  // Output
  // ------------------------------------------------------------------

  void _enqueue(String message) => _outbox.add(message);

  /// Take every queued line, leaving the outbox empty. The owner of the voice
  /// channel speaks them in order; nothing is spoken while the queue is empty.
  List<String> drainMessages() {
    if (_outbox.isEmpty) return const <String>[];
    final List<String> messages = List<String>.of(_outbox);
    _outbox.clear();
    return messages;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reset();
    _outbox.clear();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Wording helpers
  // ------------------------------------------------------------------

  String _displayName(String className) => className.isEmpty
      ? className
      : className[0].toUpperCase() + className.substring(1);

  /// "4.2 meters to your left" — reads as a distance, not a bare direction.
  static String _positionPhrase(ObjectPosition? position) {
    switch (position) {
      case ObjectPosition.center:
        return 'ahead';
      case ObjectPosition.left:
        return 'to your left';
      case ObjectPosition.right:
        return 'to your right';
      case null:
        return 'nearby';
    }
  }

  static String _spokenDistance(double? meters) {
    if (meters == null || !meters.isFinite || meters <= 0) return '';
    return '${formatDistanceMeters(meters)} meters';
  }
}
