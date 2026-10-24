import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/models/currency_recognition.dart';
import 'package:visionpath/services/currency_stability_verifier.dart';

CurrencyRecognition note({int denomination = 100, double confidence = 0.90}) {
  return CurrencyRecognition(
    kind: CurrencyKind.banknote,
    denomination: denomination,
    confidence: confidence,
    reliable: confidence >= 0.60,
  );
}

CurrencyRecognition coin({int denomination = 5, double confidence = 0.90}) {
  return CurrencyRecognition(
    kind: CurrencyKind.coin,
    denomination: denomination,
    confidence: confidence,
    reliable: confidence >= 0.60,
  );
}

void main() {
  group('multi-frame stability verifier', () {
    test('one reliable frame is only waiting, never an answer', () {
      final CurrencyStabilityVerifier verifier = CurrencyStabilityVerifier();
      final CurrencyStability first = verifier.feed(note());
      expect(first.outcome, CurrencyStabilityOutcome.waiting);
      expect(first.accepted, isNotNull);
      expect(verifier.agreements, 1);
    });

    test('two agreeing frames lock the result exactly once', () {
      final CurrencyStabilityVerifier verifier = CurrencyStabilityVerifier();
      verifier.feed(note(confidence: 0.90));
      final CurrencyStability second = verifier.feed(note(confidence: 0.92));
      expect(second.outcome, CurrencyStabilityOutcome.stable);
      expect(second.accepted!.denomination, 100);

      // The same note held steady in view must not be "announced" again.
      final CurrencyStability third = verifier.feed(note(confidence: 0.91));
      expect(third.outcome, CurrencyStabilityOutcome.alreadyStable);
    });

    test('a different denomination restarts the count', () {
      final CurrencyStabilityVerifier verifier = CurrencyStabilityVerifier();
      verifier.feed(note(denomination: 100));
      final CurrencyStability switched = verifier.feed(note(denomination: 50));
      expect(switched.outcome, CurrencyStabilityOutcome.waiting);
      expect(verifier.agreements, 1);
      expect(verifier.candidateKey, 'banknote_50');

      final CurrencyStability locked = verifier.feed(note(denomination: 50));
      expect(locked.outcome, CurrencyStabilityOutcome.stable);
      expect(locked.accepted!.denomination, 50);
    });

    test('a note and a coin never agree with each other', () {
      final CurrencyStabilityVerifier verifier = CurrencyStabilityVerifier();
      verifier.feed(note());
      final CurrencyStability switched = verifier.feed(coin());
      expect(switched.outcome, CurrencyStabilityOutcome.waiting);
      expect(verifier.candidateKey, 'coin_5');
    });

    test('an unreliable frame drops the streak but keeps the memory', () {
      final CurrencyStabilityVerifier verifier = CurrencyStabilityVerifier();
      verifier.feed(note(confidence: 0.90));
      verifier.feed(note(confidence: 0.91));
      final CurrencyStability blur = verifier.feed(note(confidence: 0.30));
      expect(blur.outcome, CurrencyStabilityOutcome.none);
      expect(verifier.agreements, 0);
      expect(verifier.hasCandidate, isFalse);

      // The same note is read confidently again: the streak restarts, and the
      // previously announced state is still remembered, so when it locks the
      // second time it does not count as a brand-new announcement.
      verifier.feed(note(confidence: 0.90));
      final CurrencyStability relocked = verifier.feed(note(confidence: 0.90));
      expect(relocked.outcome, CurrencyStabilityOutcome.alreadyStable);
    });

    test('a wildly different confidence restarts the streak', () {
      final CurrencyStabilityVerifier verifier = CurrencyStabilityVerifier();
      verifier.feed(note(confidence: 0.60));
      final CurrencyStability jump = verifier.feed(note(confidence: 0.99));
      expect(jump.outcome, CurrencyStabilityOutcome.waiting);
      expect(verifier.agreements, 1);
    });

    test('reset forgets both the streak and the announcement memory', () {
      final CurrencyStabilityVerifier verifier = CurrencyStabilityVerifier();
      verifier.feed(note());
      verifier.feed(note());
      verifier.reset();

      expect(verifier.hasCandidate, isFalse);
      expect(verifier.agreements, 0);
      verifier.feed(note());
      expect(verifier.feed(note()).outcome, CurrencyStabilityOutcome.stable);
    });

    test('requiredAgreements of 1 accepts the first reliable frame', () {
      final CurrencyStabilityVerifier verifier =
          CurrencyStabilityVerifier(requiredAgreements: 1);
      expect(verifier.feed(note()).outcome, CurrencyStabilityOutcome.stable);
    });
  });

  group('announcement gate', () {
    test('the same currency is only allowed once', () {
      final CurrencyAnnouncementGate gate = CurrencyAnnouncementGate();
      final CurrencyRecognition r = note();
      expect(gate.allowsResult(r), isTrue);
      gate.markResult(r);
      expect(gate.allowsResult(r), isFalse);
      // A different denomination is a new announcement again.
      expect(gate.allowsResult(note(denomination: 50)), isTrue);
    });

    test('uncertain messages are rate-limited by the cooldown', () {
      DateTime now = DateTime(2026, 1, 1, 12);
      final CurrencyAnnouncementGate gate = CurrencyAnnouncementGate(
        uncertainCooldown: const Duration(seconds: 5),
        clock: () => now,
      );
      expect(gate.allowsUncertain(), isTrue);
      gate.markUncertain();
      expect(gate.allowsUncertain(), isFalse);

      now = now.add(const Duration(seconds: 4));
      expect(gate.allowsUncertain(), isFalse);
      now = now.add(const Duration(seconds: 2));
      expect(gate.allowsUncertain(), isTrue);
    });

    test('reset re-opens both gates', () {
      final CurrencyAnnouncementGate gate = CurrencyAnnouncementGate();
      final CurrencyRecognition r = note();
      gate.markResult(r);
      gate.markUncertain();
      gate.reset();
      expect(gate.allowsResult(r), isTrue);
      expect(gate.allowsUncertain(), isTrue);
    });
  });
}
