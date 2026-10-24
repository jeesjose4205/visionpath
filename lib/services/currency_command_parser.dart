/// What a spoken transcript asks the Currency Recognition feature to do.
enum CurrencyCommandAction {
  /// Not a currency command at all.
  none,

  /// Start / open currency recognition.
  start,

  /// Stop / close currency recognition (or the running scan).
  stop,
}

/// Decides whether a spoken transcript is a request to open Currency
/// Recognition.
///
/// Pure and side-effect free so it can be unit tested without a microphone or a
/// speech engine. The match is deliberately conservative: a currency noun on its
/// own is **not** enough, because an ordinary scene sentence such as "I found
/// money in my bag" must never open the scanner. A match requires either
///
///  * an explicit recognize/scan/identify-style verb **together with** a
///    currency noun ("identify this coin", "recognize Indian currency"), or
///  * one of a small set of established standalone feature names
///    ("currency recognition", "money scanner").
///
/// Filler words are dropped before the verb/noun test, and a handful of common
/// speech-recognizer mis-hearings of "currency" are repaired first, so minor
/// transcription variations still match without widening the match so far that
/// unrelated sentences slip through.
///
/// The same parser also classifies stop requests ("stop currency recognition",
/// "stop scanning") through [action] / [matchesStop], so a screen can route one
/// transcript without ever treating a stop as a start or vice versa.
class CurrencyCommandParser {
  const CurrencyCommandParser._();

  /// Verbs that express an intent to look at / identify currency.
  ///
  /// Kept narrow on purpose: general verbs such as "look", "show" and "use"
  /// were deliberately excluded because they appear in unrelated sentences
  /// ("show me the money") that are not a request to scan.
  static const Set<String> _verbs = {
    'open',
    'recognize',
    'recognise',
    'identify',
    'scan',
    'read',
    'check',
    'start',
    'launch',
    'detect',
    'count',
  };

  /// Nouns that name currency, money or a physical denomination.
  static const Set<String> _nouns = {
    'currency',
    'currencies',
    'money',
    'note',
    'notes',
    'banknote',
    'banknotes',
    'coin',
    'coins',
    'cash',
    'rupee',
    'rupees',
  };

  /// Grammar / politeness words removed before matching.
  static const Set<String> _fillers = {
    'please',
    'can',
    'could',
    'would',
    'you',
    'u',
    'the',
    'a',
    'an',
    'this',
    'that',
    'these',
    'those',
    'my',
    'some',
    'to',
    'for',
    'me',
    'i',
    'is',
    'it',
    'of',
    'in',
    'on',
    'and',
    'do',
    'does',
    'will',
    'now',
    'with',
  };

  /// Whole-utterance feature names that need no verb.
  static const Set<String> _standalone = <String>{
    'currency recognition',
    'money recognition',
    'currency scanner',
    'currency scan',
    'note recognition',
    'coin recognition',
    'money scanner',
    'currency detector',
    'money detector',
    'currency identifier',
    'money identifier',
  };

  /// Verbs that express an intent to stop / leave the feature.
  ///
  /// Deliberately separate from [_verbs]: "stop" must never be able to *open*
  /// recognition, and "start" must never be able to stop it.
  static const Set<String> _stopVerbs = <String>{
    'stop',
    'cancel',
    'end',
    'quit',
    'close',
    'halt',
    'pause',
    'discontinue',
  };

  /// Nouns that can follow a stop verb and still mean "the currency feature".
  ///
  /// The scan words ("scanning", "recognition") are included so
  /// "stop scanning" is understood without the sentence having to name money.
  static const Set<String> _stopNouns = <String>{
    'currency',
    'currencies',
    'money',
    'note',
    'notes',
    'banknote',
    'banknotes',
    'coin',
    'coins',
    'cash',
    'rupee',
    'rupees',
    'scan',
    'scanning',
    'scanner',
    'recognition',
    'recognizing',
    'recognising',
    'identification',
    'detecting',
  };

  /// Bare words that stop the feature on their own.
  ///
  /// Only honoured when the caller passes `allowBareStop: true`, which the
  /// Currency Recognition screen does (there "stop" can only mean "stop
  /// scanning") and the Navigate screen does not (there a bare "stop" already
  /// has its own meaning).
  static const Set<String> _bareStop = <String>{
    'stop',
    'cancel',
    'quit',
    'nevermind',
    'never mind',
    'halt',
  };

  /// Common recognizer mis-hearings, repaired before matching.
  static const Map<String, String> _fixups = {
    'currancy': 'currency',
    'currencey': 'currency',
    'curreny': 'currency',
    'curency': 'currency',
    'currencie': 'currency',
    'currencies': 'currencies',
  };

  /// Lowercases, strips punctuation, collapses whitespace and repairs known
  /// mis-hearings. Used by both the standalone and tokenised matchers.
  static String normalize(String transcript) {
    final String cleaned = transcript
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '';
    return cleaned
        .split(' ')
        .map((String w) => _fixups[w] ?? w)
        .join(' ');
  }

  /// Normalized, filler-stripped word list for [transcript].
  static List<String> tokens(String transcript) {
    final String normalized = normalize(transcript);
    if (normalized.isEmpty) return const <String>[];
    return <String>[
      for (final String word in normalized.split(' '))
        if (word.isNotEmpty && !_fillers.contains(word)) word,
    ];
  }

  /// True when [transcript] asks to open Currency Recognition.
  static bool matches(String transcript) {
    final String normalized = normalize(transcript);
    if (normalized.isEmpty) return false;
    if (_standalone.contains(normalized)) return true;
    // A stop sentence ("stop recognizing money") must never double as a start
    // command just because it also contains a currency noun.
    if (_isStopSentence(transcript)) return false;

    final List<String> words = tokens(transcript);
    if (words.isEmpty) return false;
    final bool hasVerb = words.any(_verbs.contains);
    final bool hasNoun = words.any(_nouns.contains);
    return hasVerb && hasNoun;
  }

  /// True when [transcript] asks to stop Currency Recognition or its scan.
  ///
  /// [allowBareStop] additionally accepts utterances with no currency word at
  /// all ("stop", "cancel") — safe only inside a screen where those words can
  /// mean nothing else.
  static bool matchesStop(String transcript, {bool allowBareStop = false}) =>
      action(transcript, allowBareStop: allowBareStop) ==
      CurrencyCommandAction.stop;

  /// Classify [transcript] as start, stop or neither.
  ///
  /// Start wins only for a currency sentence ([matches]); stop only for a stop
  /// sentence ([matchesStop]). A sentence can never be both: "stop currency
  /// recognition" has no start verb, and "start currency recognition" has no
  /// stop verb.
  static CurrencyCommandAction action(
    String transcript, {
    bool allowBareStop = false,
  }) {
    final String normalized = normalize(transcript);
    if (normalized.isEmpty) return CurrencyCommandAction.none;

    if (allowBareStop && _bareStop.contains(normalized)) {
      return CurrencyCommandAction.stop;
    }

    if (_standalone.contains(normalized)) return CurrencyCommandAction.start;
    if (_isStopSentence(transcript)) return CurrencyCommandAction.stop;
    if (matches(transcript)) return CurrencyCommandAction.start;
    return CurrencyCommandAction.none;
  }

  /// True when [transcript] is a stop verb plus a currency/scan noun.
  static bool _isStopSentence(String transcript) {
    final List<String> words = tokens(transcript);
    if (words.isEmpty) return false;
    final bool hasStopVerb = words.any(_stopVerbs.contains);
    if (!hasStopVerb) return false;
    return words.any(_stopNouns.contains);
  }
}
