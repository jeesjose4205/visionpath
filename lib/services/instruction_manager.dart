import '../models/navigation_decision.dart';

/// InstructionManager prevents repeated/redundant voice instructions.
///
/// A new instruction is issued only when at least one of these conditions is
/// met:
/// 1. The decision changed.
/// 2. The danger level increased (e.g., FORWARD -> STOP).
/// 3. Enough time has passed since the last instruction (repeat guard).
class InstructionManager {
  /// Minimum interval between repeated instructions. Mutable so the
  /// Navigation "Guidance Frequency" setting can tune it.
  Duration repeatCooldown = const Duration(milliseconds: 3000);

  /// Escalations below this interval bypass the repeat cooldown.
  static const Duration escalationMinimumGap = Duration(milliseconds: 1200);

  NavigationDecision? _lastDecision;
  DateTime? _lastSpokenAt;

  /// Whether a new instruction should be voiced for [decision].
  bool shouldSpeak(NavigationDecision decision) {
    final DateTime now = DateTime.now();

    final bool changed = decision != _lastDecision;
    final bool escalated = changed &&
        _lastDecision != null &&
        _priority(decision) > _priority(_lastDecision!);
    final bool cooldownElapsed = _lastSpokenAt == null ||
        now.difference(_lastSpokenAt!) >=
            (escalated ? escalationMinimumGap : repeatCooldown);

    final bool speak = changed || escalated || cooldownElapsed;

    print('INSTRUCTION_MANAGER: decision=${decision.label} changed=$changed escalated=$escalated cooldownElapsed=$cooldownElapsed => speak=$speak');

    if (speak) {
      _lastDecision = decision;
      _lastSpokenAt = now;
    }
    return speak;
  }

  int _priority(NavigationDecision decision) {
    switch (decision) {
      case NavigationDecision.stop:
        return 5;
      case NavigationDecision.slow:
        return 4;
      case NavigationDecision.left:
      case NavigationDecision.right:
        return 2;
      case NavigationDecision.forward:
        return 0;
    }
  }

  /// Reset the manager (e.g., when navigation stops).
  void reset() {
    _lastDecision = null;
    _lastSpokenAt = null;
  }
}