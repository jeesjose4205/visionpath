import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/services/currency_command_parser.dart';

void main() {
  group('currency command normalization', () {
    test('normalizes punctuation, spacing and case', () {
      expect(CurrencyCommandParser.normalize('Open Currency Recognition!'),
          equals('open currency recognition'));
      expect(CurrencyCommandParser.normalize('  Recognize   MONEY  '),
          equals('recognize money'));
    });

    test('repairs common currency mishearings', () {
      expect(CurrencyCommandParser.matches('open currancy recognition'),
          isTrue);
      expect(CurrencyCommandParser.matches('identify currencey'),
          isTrue);
      expect(CurrencyCommandParser.matches('recognize curreny note'),
          isTrue);
    });
  });

  group('currency command matching', () {
    test('matches standalone feature names', () {
      expect(CurrencyCommandParser.matches('currency recognition'), isTrue);
      expect(CurrencyCommandParser.matches('money recognition'), isTrue);
      expect(CurrencyCommandParser.matches('currency scanner'), isTrue);
      expect(CurrencyCommandParser.matches('currency scan'), isTrue);
      expect(CurrencyCommandParser.matches('note recognition'), isTrue);
      expect(CurrencyCommandParser.matches('coin recognition'), isTrue);
      expect(CurrencyCommandParser.matches('money scanner'), isTrue);
      expect(CurrencyCommandParser.matches('currency detector'), isTrue);
      expect(CurrencyCommandParser.matches('money detector'), isTrue);
      expect(CurrencyCommandParser.matches('currency identifier'), isTrue);
      expect(CurrencyCommandParser.matches('money identifier'), isTrue);
    });

    test('matches verb + noun currency phrases', () {
      expect(CurrencyCommandParser.matches('open currency recognition'),
          isTrue);
      expect(CurrencyCommandParser.matches('open currency'), isTrue);
      expect(CurrencyCommandParser.matches('recognize currency'), isTrue);
      expect(CurrencyCommandParser.matches('recognise currency'), isTrue);
      expect(CurrencyCommandParser.matches('identify currency'), isTrue);
      expect(CurrencyCommandParser.matches('scan currency'), isTrue);
      expect(CurrencyCommandParser.matches('read currency'), isTrue);
      expect(CurrencyCommandParser.matches('check currency'), isTrue);
      expect(CurrencyCommandParser.matches('start currency'), isTrue);
      expect(CurrencyCommandParser.matches('launch currency'), isTrue);
      expect(CurrencyCommandParser.matches('detect currency'), isTrue);
      expect(CurrencyCommandParser.matches('count currency'), isTrue);

      expect(CurrencyCommandParser.matches('recognize money'), isTrue);
      expect(CurrencyCommandParser.matches('identify money'), isTrue);
      expect(CurrencyCommandParser.matches('open money'), isTrue);
      expect(CurrencyCommandParser.matches('recognize cash'), isTrue);
      expect(CurrencyCommandParser.matches('identify note'), isTrue);
      expect(CurrencyCommandParser.matches('scan notes'), isTrue);
      expect(CurrencyCommandParser.matches('identify this coin'), isTrue);
      expect(CurrencyCommandParser.matches('identify these coins'), isTrue);
      expect(CurrencyCommandParser.matches('recognize banknote'), isTrue);
      expect(CurrencyCommandParser.matches('recognize banknotes'), isTrue);
      expect(CurrencyCommandParser.matches('check rupee'), isTrue);
      expect(CurrencyCommandParser.matches('recognize rupees'), isTrue);
      expect(CurrencyCommandParser.matches('Please open currency recognition'),
          isTrue);
      expect(CurrencyCommandParser.matches('Can you recognize this note?'),
          isTrue);
    });

    test('rejects unrelated sentences that mention money', () {
      expect(CurrencyCommandParser.matches('I found money in my bag'),
          isFalse);
      expect(CurrencyCommandParser.matches('Show me the money'), isFalse);
      expect(CurrencyCommandParser.matches('Use money to pay'), isFalse);
      expect(CurrencyCommandParser.matches('Look at my money'), isFalse);
      expect(CurrencyCommandParser.matches('The currency market is up'),
          isFalse);
      expect(CurrencyCommandParser.matches('Money matters'), isFalse);
      expect(CurrencyCommandParser.matches('Check my balance'), isFalse);
      expect(CurrencyCommandParser.matches('Find a note pad'), isFalse);
      expect(CurrencyCommandParser.matches('Count the steps'), isFalse);
    });
  });

  group('currency command action', () {
    test('classifies start phrases as start', () {
      expect(CurrencyCommandParser.action('open currency recognition'),
          CurrencyCommandAction.start);
      expect(CurrencyCommandParser.action('currency recognition'),
          CurrencyCommandAction.start);
      expect(CurrencyCommandParser.action('identify this coin'),
          CurrencyCommandAction.start);
      expect(CurrencyCommandParser.action('start scanning money'),
          CurrencyCommandAction.start);
      expect(CurrencyCommandParser.action('recognize curreny note'),
          CurrencyCommandAction.start);
    });

    test('classifies stop phrases as stop', () {
      expect(CurrencyCommandParser.action('stop currency recognition'),
          CurrencyCommandAction.stop);
      expect(CurrencyCommandParser.action('stop scanning'),
          CurrencyCommandAction.stop);
      expect(CurrencyCommandParser.action('cancel money recognition'),
          CurrencyCommandAction.stop);
      expect(CurrencyCommandParser.action('quit currency scanner'),
          CurrencyCommandAction.stop);
      expect(CurrencyCommandParser.action('end coin recognition'),
          CurrencyCommandAction.stop);
      expect(CurrencyCommandParser.action('stop recognition'),
          CurrencyCommandAction.stop);
      expect(CurrencyCommandParser.action('close currency'),
          CurrencyCommandAction.stop);
    });

    test('a stop sentence is never also a start command', () {
      // It contains the currency nouns "recognition"/"currency" but no start
      // verb; it must not open the scanner.
      expect(CurrencyCommandParser.matches('stop currency recognition'),
          isFalse);
      expect(CurrencyCommandParser.matches('stop recognizing money'),
          isFalse);
      expect(CurrencyCommandParser.action('stop recognizing money'),
          CurrencyCommandAction.stop);
    });

    test('unrelated sentences are none', () {
      expect(CurrencyCommandParser.action('I found money in my bag'),
          CurrencyCommandAction.none);
      expect(CurrencyCommandParser.action('hello'),
          CurrencyCommandAction.none);
      expect(CurrencyCommandParser.action(''),
          CurrencyCommandAction.none);
      expect(CurrencyCommandParser.action('stop the car'),
          CurrencyCommandAction.none);
    });

    test('bare stop only counts when the caller allows it', () {
      expect(CurrencyCommandParser.action('stop'), CurrencyCommandAction.none);
      expect(CurrencyCommandParser.matchesStop('stop'), isFalse);
      expect(
        CurrencyCommandParser.action('stop', allowBareStop: true),
        CurrencyCommandAction.stop,
      );
      expect(
        CurrencyCommandParser.matchesStop('stop', allowBareStop: true),
        isTrue,
      );
      expect(
        CurrencyCommandParser.action('cancel', allowBareStop: true),
        CurrencyCommandAction.stop,
      );
      expect(
        CurrencyCommandParser.action('never mind', allowBareStop: true),
        CurrencyCommandAction.stop,
      );
      // A bare start verb without a currency noun stays none even with
      // allowBareStop: that flag only widens stop.
      expect(
        CurrencyCommandParser.action('start', allowBareStop: true),
        CurrencyCommandAction.none,
      );
    });

    test('stop words can never open the feature', () {
      expect(CurrencyCommandParser.matches('stop currency'), isFalse);
      expect(CurrencyCommandParser.matches('cancel money'), isFalse);
      expect(CurrencyCommandParser.matches('quit scanning'), isFalse);
    });
  });
}
