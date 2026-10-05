import '../models/navigation_decision.dart';

/// InstructionManager prevents repeated/redundant voice instructions.
///
/// A new instruction is issued only when at least one of these conditions is
/// met:
/// 1. The decision changed.
/// 2. The danger level increased (e.g., FORWARD -> STOP).
/// 3. Enough time has passed since the last instruction (repeat guard).
///
/// Two user settings shape this, and they are combined here rather than being
/// applied by whichever screen happens to call it:
///
/// * **Announcement Frequency** (`announcementCooldownSeconds`) is the hard
///   floor between two spoken instructions.
/// * **Guidance Frequency** (`guidanceMode`) is the navigation-specific
///   preference, mapped to 1.5 / 3 / 6 seconds.
///
/// The two are combined by taking the **larger** of the two intervals (see
/// [repeatCooldown]). The reasoning: both settings only ever mean "do not
/// interrupt me more often than this", so honouring the more restrictive of
/// the two is the only combination that never talks faster than the user asked
/// for. A user who picks "Rarely (8 s)" gets 8 s even under "More Frequent",
/// and a user who picks "Often (2 s)" under "Minimal" gets 6 s — the
/// navigation-specific preference keeps its documented meaning and the
/// explicit announcement setting is never silently overridden downward.
/// Screen readers and safety warnings are unaffected: escalations still use
/// [escalationMinimumGap].
class InstructionManager {
  /// Minimum interval between repeated instructions.
  Duration repeatCooldown = const Duration(milliseconds: 3000);

  /// Whether an unchanged decision may be re-stated once [repeatCooldown] has
  /// elapsed.
  ///
  /// This is the "Repeat Last Instruction" setting. When off, only genuine
  /// changes and escalations are spoken, so the same "clear path" sentence is
  /// never repeated on a loop. Escalations are never suppressed.
  bool repeatEnabled = true;

  /// Escalations below this interval bypass the repeat cooldown.
  static const Duration escalationMinimumGap = Duration(milliseconds: 1200);

  NavigationDecision? _lastDecision;
  DateTime? _lastSpokenAt;

  /// The last instruction actually spoken, for an explicit user-requested
  /// repeat.
  NavigationDecision? lastSpokenDecision;

  /// The exact sentences handed to the voice engine for [lastSpokenDecision].
  ///
  /// Recorded by the screen at the moment it enqueues speech, not derived from
  /// the live scene: `NavigationService.lastSpokenMessage` is rebuilt on every
  /// analysed frame, including frames the cooldown suppressed, so repeating
  /// from it could play a sentence the user never actually heard. Empty until
  /// something has been spoken.
  List<String> lastSpokenSentences = const <String>[];

  /// Record the sentences actually delivered for the current announcement.
  void noteSpoken(List<String> sentences) {
    lastSpokenSentences = List<String>.unmodifiable(sentences);
  }

  /// Whether a new instruction should be voiced for [decision].
  bool shouldSpeak(NavigationDecision decision) {
    final DateTime now = DateTime.now();

    final bool changed = decision != _lastDecision;
    final bool escalated = changed &&
        _lastDecision != null &&
        _priority(decision) > _priority(_lastDecision!);

    // An escalation is a safety message: it is spoken on a short gap so a new
    // hazard is never hidden behind the repeat cooldown.
    final Duration gate = escalated ? escalationMinimumGap : repeatCooldown;
    final bool cooldownElapsed = _lastSpokenAt == null ||
        now.difference(_lastSpokenAt!) >= gate;

    // Repeat disabled means an unchanged decision never re-announces, no
    // matter how long ago it was last spoken.
    final bool speak = changed ? cooldownElapsed : (repeatEnabled && cooldownElapsed);

    print('INSTRUCTION_MANAGER: decision=${decision.label} changed=$changed escalated=$escalated cooldownElapsed=$cooldownElapsed repeatEnabled=$repeatEnabled => speak=$speak');

    if (speak) {
      _lastDecision = decision;
      _lastSpokenAt = now;
      lastSpokenDecision = decision;
    }
    return speak;
  }

  /// Speak the previous instruction again, on explicit user request.
  ///
  /// Returns false when there is nothing to repeat, or when
  /// [repeatInstruction] is off — which is what the setting describes. The
  /// explicit request also updates the timer so the reminder loop does not
  /// immediately re-speak the same sentence a moment later.
  bool repeatLast() {
    if (!repeatEnabled) return false;
    final NavigationDecision? previous = lastSpokenDecision;
    if (previous == null || lastSpokenSentences.isEmpty) return false;
    _lastSpokenAt = DateTime.now();
    print('INSTRUCTION_MANAGER: repeat ${previous.label}');
    return true;
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
    lastSpokenDecision = null;
    lastSpokenSentences = const <String>[];
  }
}