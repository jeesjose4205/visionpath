/// Kind of Indian currency the recognizer can identify.
///
/// Banknotes and coins are modelled separately because they are recognised by
/// separate models with separate label sets and separate failure modes.
enum CurrencyKind { banknote, coin }

/// Which kinds of currency a scan session analyses.
///
/// The mode never widens what the app can claim: a kind only ever contributes
/// a result when its own model actually loaded (see
/// `CurrencyRecognitionService.supportedDenominations`).
enum CurrencyScanMode {
  /// Run every loaded model and keep the most confident result.
  both,

  /// Only banknotes.
  banknote,

  /// Only coins.
  coin;

  /// The kinds this mode allows through to the models.
  Set<CurrencyKind> get kinds => switch (this) {
        CurrencyScanMode.both =>
          const <CurrencyKind>{CurrencyKind.banknote, CurrencyKind.coin},
        CurrencyScanMode.banknote => const <CurrencyKind>{CurrencyKind.banknote},
        CurrencyScanMode.coin => const <CurrencyKind>{CurrencyKind.coin},
      };

  /// Short label for the mode selector.
  String get label => switch (this) {
        CurrencyScanMode.both => 'Both',
        CurrencyScanMode.banknote => 'Notes',
        CurrencyScanMode.coin => 'Coins',
      };

  /// One-line hint about what to point the camera at.
  ///
  /// Coins are not recognised by the bundled note detector, so no mode promises
  /// coin support.
  String get guidance => switch (this) {
        CurrencyScanMode.both => 'Place one banknote in front of the camera.',
        CurrencyScanMode.banknote => 'Place one banknote in front of the camera.',
        CurrencyScanMode.coin => 'Coins are not supported in this build.',
      };
}

/// A single recognition outcome.
///
/// [confidence] is the raw model probability for the winning class; [reliable]
/// records whether that probability cleared the acceptance threshold the service
/// was configured with. They are kept apart on purpose: the UI may show a
/// confidence figure only when one was meaningfully derived, while a
/// low-confidence win is still treated as "unable to identify" rather than
/// presented as an answer.
class CurrencyRecognition {
  const CurrencyRecognition({
    required this.kind,
    required this.denomination,
    required this.confidence,
    required this.reliable,
  });

  /// Whether this is a note or a coin.
  final CurrencyKind kind;

  /// Face value in whole rupees (e.g. 100 for a ₹100 note).
  final int denomination;

  /// Winning-class probability in the range 0..1.
  final double confidence;

  /// True when [confidence] met the acceptance threshold.
  final bool reliable;

  bool get isBanknote => kind == CurrencyKind.banknote;

  /// Human phrase with the unit, e.g. "100 rupee note" / "5 rupee coin".
  String get spokenLabel =>
      '$denomination rupee ${isBanknote ? 'note' : 'coin'}';

  /// Compact on-screen label, e.g. "₹100 Banknote" / "₹5 Coin".
  String get displayLabel =>
      '₹$denomination ${isBanknote ? 'Banknote' : 'Coin'}';

  /// Confidence as a whole percentage, for display only.
  int get confidencePercent => (confidence * 100).round();

  /// Stable identity of what was recognised ("banknote_100", "coin_5").
  ///
  /// Used to suppress repeat announcements while the same note/coin stays in
  /// view and to dedupe across a mode switch.
  String get key => '${kind.name}_$denomination';

  @override
  String toString() => 'CurrencyRecognition(${kind.name}, ₹$denomination, '
      '${(confidence * 100).toStringAsFixed(1)}%, reliable=$reliable)';
}
