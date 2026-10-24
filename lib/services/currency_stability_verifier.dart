import '../models/currency_recognition.dart';

/// What a stream of per-frame predictions currently amounts to.
enum CurrencyStabilityOutcome {
  /// No usable prediction yet.
  none,

  /// Something is being seen but has not agreed with itself often enough.
  waiting,

  /// Enough frames agreed; the first time this happens for this currency.
  stable,

  /// Enough frames agreed, and this currency was already announced once.
  alreadyStable,
}

/// Result of feeding one frame's prediction to [CurrencyStabilityVerifier].
class CurrencyStability {
  const CurrencyStability._(this.outcome, this.accepted);

  /// The recognition that reached agreement, non-null for [stable] and
  /// [alreadyStable].
  final CurrencyRecognition? accepted;

  final CurrencyStabilityOutcome outcome;

  bool get isStable => outcome == CurrencyStabilityOutcome.stable;
  bool get isAlreadyStable =>
      outcome == CurrencyStabilityOutcome.alreadyStable;
  bool get hasAccepted => accepted != null;
}

/// Turns flickering per-frame model outputs into a single trustworthy answer.
///
/// Camera frames of the same note do not produce identical probabilities, and
/// a single frame can also be a genuinely wrong guess. A denomination is only
/// accepted after [requiredAgreements] consecutive reliable predictions with
/// the same identity, and a change of identity restarts the count — so a
/// half-visible second note cannot silently replace the announced one.
///
/// Pure Dart with no plugins or clock reads of its own, so behaviour is fully
/// unit-testable without a device.
class CurrencyStabilityVerifier {
  CurrencyStabilityVerifier({
    this.requiredAgreements = 2,
    this.confidenceTolerance = 0.35,
  }) : assert(requiredAgreements >= 1);

  /// How many consecutive agreeing reliable predictions are needed.
  final int requiredAgreements;

  /// How far the winning probability may move between agreeing frames before
  /// the streak restarts. A huge jump usually means the camera moved or the
  /// frame was garbage, not a steady read of one bill.
  final double confidenceTolerance;

  String? _key;
  int _agreements = 0;
  double _lastConfidence = 0;

  /// The last currency that reached agreement and was reported.
  ///
  /// Remembered per denomination, not as a one-shot flag: a single blurry
  /// frame drops the streak, and when the same note reads confidently again
  /// it must not be treated as a brand-new find.
  String? _announcedKey;

  /// True once anything has been accepted for the current streak.
  bool get hasCandidate => _key != null;

  String? get candidateKey => _key;
  int get agreements => _agreements;
  String? get announcedKey => _announcedKey;

  /// Feed one frame's [prediction] and report the current stability state.
  ///
  /// Unreliable predictions (below the service threshold) never count; they
  /// drop the streak so a run of confident frames cannot be padded by
  /// uncertain ones. The announcement memory is deliberately kept: a single
  /// blurry frame must not cause the same note to be announced all over again
  /// while it is still in view.
  CurrencyStability feed(CurrencyRecognition prediction) {
    if (!prediction.reliable) {
      _clearStreak();
      return const CurrencyStability._(CurrencyStabilityOutcome.none, null);
    }

    final String key = prediction.key;
    if (_key == null || _key != key) {
      // New (or different) currency in view: start counting from this frame.
      _key = key;
      _agreements = 1;
    } else if ((prediction.confidence - _lastConfidence).abs() >
        confidenceTolerance) {
      // Same currency but a wildly different probability; treat as fresh
      // evidence rather than an agreeing frame.
      _agreements = 1;
    } else {
      _agreements += 1;
    }
    _lastConfidence = prediction.confidence;

    if (_agreements < requiredAgreements) {
      return CurrencyStability._(
          CurrencyStabilityOutcome.waiting, prediction);
    }

    if (_announcedKey == key) {
      return CurrencyStability._(
          CurrencyStabilityOutcome.alreadyStable, prediction);
    }
    _announcedKey = key;
    return CurrencyStability._(CurrencyStabilityOutcome.stable, prediction);
  }

  /// Drop the agreement streak without forgetting what was already announced.
  void _clearStreak() {
    _key = null;
    _agreements = 0;
    _lastConfidence = 0;
  }

  /// Forget the current streak and the announcement memory (e.g. scanning was
  /// stopped and restarted, or the mode changed).
  void reset() {
    _clearStreak();
    _announcedKey = null;
  }
}

/// Decides whether an outcome is worth speaking out loud again.
///
/// A bill held steady in view keeps producing confident frames; without a
/// gate the app would repeat "one hundred rupee note" every few hundred
/// milliseconds. This keeps the first announcement per currency, and rate
/// -limits the fuzzy "try to hold it still" messages separately, because
/// those fire whenever a frame happens to be bad.
class CurrencyAnnouncementGate {
  CurrencyAnnouncementGate({
    this.uncertainCooldown = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Minimum gap between "I'm not sure" spoken messages.
  final Duration uncertainCooldown;

  final DateTime Function() _clock;

  String? _lastResultKey;
  DateTime? _lastUncertainAt;

  /// Whether [result] should be spoken now. Does not mark it as spoken.
  bool allowsResult(CurrencyRecognition result) => result.key != _lastResultKey;

  /// Record that [result] has been spoken.
  void markResult(CurrencyRecognition result) {
    _lastResultKey = result.key;
  }

  /// Whether an uncertain message should be spoken now.
  bool allowsUncertain() {
    final DateTime? last = _lastUncertainAt;
    if (last == null) return true;
    return _clock().difference(last) >= uncertainCooldown;
  }

  /// Record that an uncertain message has been spoken.
  void markUncertain() {
    _lastUncertainAt = _clock();
  }

  /// Clear both gates (new scan session).
  void reset() {
    _lastResultKey = null;
    _lastUncertainAt = null;
  }
}
