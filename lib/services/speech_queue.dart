/// Lifecycle state of the navigation speech queue.
enum SpeechState {
  /// Nothing queued and nothing being spoken.
  idle,

  /// A sentence is being spoken right now.
  speaking,

  /// Nothing is speaking, but at least one sentence is waiting.
  queued,
}

/// A strictly sequential, duplicate-free queue of complete sentences.
///
/// This is deliberately a plain Dart object with no Flutter/TTS dependency:
/// it owns *what* is waiting and *in which order*, while the TTS service owns
/// the audio. Keeping them apart makes the ordering and duplicate rules
/// testable without a platform channel and keeps a camera frame from ever
/// touching the audio layer directly.
///
/// Invariants:
///   * a sentence appears at most once in the pending list,
///   * the sentence currently being spoken is never also queued,
///   * sentences leave the queue only via [takeNext] or [clear].
class SpeechQueue {
  final List<String> _pending = <String>[];
  final Set<String> _queued = <String>{};
  String? _active;
  bool _speaking = false;

  /// Current state, derived so it can never disagree with the contents.
  SpeechState get state {
    if (_speaking) return SpeechState.speaking;
    if (_pending.isNotEmpty) return SpeechState.queued;
    return SpeechState.idle;
  }

  /// True while a sentence is being spoken.
  bool get isSpeaking => _speaking;

  /// True when at least one sentence is waiting for its turn.
  bool get hasPending => _pending.isNotEmpty;

  /// Number of sentences waiting.
  int get pendingCount => _pending.length;

  /// The sentence currently being spoken, if any.
  String? get activeSentence => _active;

  /// Waiting sentences, oldest first (read-only snapshot).
  List<String> get pending => List<String>.unmodifiable(_pending);

  /// Add a complete [sentence] to the back of the queue.
  ///
  /// Returns true when it was actually queued. Returns false when the
  /// sentence is blank, already waiting, or is the one currently being spoken
  /// — duplicate protection, so an unchanged scene can never pile up.
  bool add(String sentence) {
    final String trimmed = sentence.trim();
    if (trimmed.isEmpty) return false;
    if (_queued.contains(trimmed)) return false;
    if (_speaking && _active == trimmed) return false;
    _pending.add(trimmed);
    _queued.add(trimmed);
    return true;
  }

  /// Promote the next waiting sentence to "speaking".
  ///
  /// Returns null when the queue is empty. Call [finishCurrent] once the
  /// utterance has actually finished.
  String? takeNext() {
    if (_pending.isEmpty) return null;
    final String sentence = _pending.removeAt(0);
    _queued.remove(sentence);
    _active = sentence;
    _speaking = true;
    return sentence;
  }

  /// Mark the current utterance as finished (or as never having played).
  void finishCurrent() {
    _active = null;
    _speaking = false;
  }

  /// Drop every waiting sentence and forget the current one.
  ///
  /// Used when something more important must be spoken now (a safety warning)
  /// and when a run ends, so nothing stale is spoken later.
  void clear() {
    _pending.clear();
    _queued.clear();
    _active = null;
    _speaking = false;
  }

  /// Drop only the sentences that have not started yet, and leave the one
  /// currently being spoken alone.
  ///
  /// This is what a press-and-hold needs: nothing new may start, but the
  /// sentence already coming out of the speaker is allowed to finish. Reporting
  /// the queue as idle here would tell a waiting microphone that the speaker is
  /// free while it is still talking.
  void clearPending() {
    _pending.clear();
    _queued.clear();
  }
}