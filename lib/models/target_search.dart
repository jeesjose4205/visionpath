import 'object_position.dart';

/// Where a Target Object Navigation session currently stands.
enum TargetSearchPhase {
  /// No target requested: navigation behaves exactly as before.
  idle,

  /// A target was requested and is being looked for. Nothing confirmed yet.
  searching,

  /// The target was confirmed and is being tracked/guided towards.
  tracking,

  /// The target was reached; guidance ends and normal navigation resumes.
  reached,
}

/// The four modes the assistant can be in. Normal navigation is untouched;
/// the other three describe an active target session.
enum NavigationMode {
  /// Normal environmental navigation — no target requested.
  normal,

  /// A target was requested and is still being looked for.
  targetSearch,

  /// The target was found and is being approached.
  targetApproach,

  /// The target was reached; guidance for it is over.
  targetReached,
}

/// Maps a search phase onto the user-facing navigation mode.
extension TargetSearchPhaseMode on TargetSearchPhase {
  NavigationMode get mode {
    switch (this) {
      case TargetSearchPhase.idle:
        return NavigationMode.normal;
      case TargetSearchPhase.searching:
        return NavigationMode.targetSearch;
      case TargetSearchPhase.tracking:
        return NavigationMode.targetApproach;
      case TargetSearchPhase.reached:
        return NavigationMode.targetReached;
    }
  }
}

/// What a spoken/typed utterance asked the target navigator to do.
enum TargetCommandKind {
  /// Not a target-navigation utterance — let the assistant answer normally.
  none,

  /// "Find a chair" / "Where is the sofa?" / "Take me to the fridge".
  start,

  /// "Stop searching" / "Forget the chair".
  stop,

  /// "Find the door" — an object the detection model cannot see.
  unsupported,
}

/// A parsed target-navigation request.
class TargetCommand {
  const TargetCommand({
    required this.kind,
    this.phrase = '',
    this.classes = const <String>[],
  });

  const TargetCommand.none() : this(kind: TargetCommandKind.none);

  final TargetCommandKind kind;

  /// The object words the user said, cleaned of verbs and articles ("chair").
  final String phrase;

  /// Canonical YOLO class names [phrase] can mean. Empty when the model
  /// cannot detect the object.
  final List<String> classes;

  /// The class this command will search for (nearest match), or null.
  String? get className => classes.isEmpty ? null : classes.first;

  bool get isNone => kind == TargetCommandKind.none;

  bool get isStart => kind == TargetCommandKind.start;

  bool get isStop => kind == TargetCommandKind.stop;

  bool get isUnsupported => kind == TargetCommandKind.unsupported;
}

/// Immutable snapshot of a target session for the minimal on-screen status.
class TargetSearchState {
  const TargetSearchState({
    required this.phase,
    required this.targetName,
    this.position,
    this.distanceMeters,
    this.confirmed = false,
  });

  final TargetSearchPhase phase;

  /// Display name of the target, e.g. "Chair".
  final String targetName;

  /// Latest lateral position of the target, null while unconfirmed.
  final ObjectPosition? position;

  /// Latest calibrated distance in meters, null when depth has no estimate.
  final double? distanceMeters;

  /// True once the target survived the multi-frame confirmation window.
  final bool confirmed;

  bool get isActive =>
      phase == TargetSearchPhase.searching || phase == TargetSearchPhase.tracking;

  /// The navigation mode this state represents.
  NavigationMode get mode => phase.mode;

  /// "2.4 m • Ahead" style status line, or a phase description while hunting.
  String get statusText {
    switch (phase) {
      case TargetSearchPhase.idle:
        return '';
      case TargetSearchPhase.searching:
        return confirmed ? 'Tracking…' : 'Searching…';
      case TargetSearchPhase.tracking:
        final List<String> parts = <String>[];
        if (distanceMeters != null) parts.add(_formatMeters(distanceMeters!));
        if (position != null) parts.add(_positionLabel(position!));
        return parts.isEmpty ? 'Tracking…' : parts.join(' • ');
      case TargetSearchPhase.reached:
        return 'Reached';
    }
  }

  static String _formatMeters(double meters) {
    if (meters >= 10) return '${meters.toStringAsFixed(0)} m';
    if (meters >= 0.5) return '${meters.toStringAsFixed(1)} m';
    return '${meters.toStringAsFixed(2)} m';
  }

  static String _positionLabel(ObjectPosition position) {
    switch (position) {
      case ObjectPosition.center:
        return 'Ahead';
      case ObjectPosition.left:
        return 'On your left';
      case ObjectPosition.right:
        return 'On your right';
    }
  }
}
