import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/models/currency_recognition.dart';
import 'package:visionpath/services/currency_recognition_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('label to denomination mapping', () {
    test('parses rupee-prefixed and bare digit labels', () {
      expect(CurrencyRecognitionService.denominationFromLabel('₹100'), 100);
      expect(CurrencyRecognitionService.denominationFromLabel('100'), 100);
      expect(CurrencyRecognitionService.denominationFromLabel('₹20'), 20);
      expect(CurrencyRecognitionService.denominationFromLabel('1'), 1);
    });

    test('parses labels that carry a unit or class prefix', () {
      expect(
        CurrencyRecognitionService.denominationFromLabel('100 rupees'),
        100,
      );
      expect(CurrencyRecognitionService.denominationFromLabel('coin_10'), 10);
      expect(CurrencyRecognitionService.denominationFromLabel('note_500'), 500);
    });

    test('resolves number words longest-first', () {
      expect(
        CurrencyRecognitionService.denominationFromLabel('two hundred'),
        200,
      );
      expect(
        CurrencyRecognitionService.denominationFromLabel('five hundred'),
        500,
      );
      expect(
        CurrencyRecognitionService.denominationFromLabel('two thousand'),
        2000,
      );
      expect(CurrencyRecognitionService.denominationFromLabel('fifty'), 50);
      expect(CurrencyRecognitionService.denominationFromLabel('twenty'), 20);
      expect(CurrencyRecognitionService.denominationFromLabel('five'), 5);
    });

    test('returns null for labels that carry no denomination', () {
      expect(CurrencyRecognitionService.denominationFromLabel(''), isNull);
      expect(CurrencyRecognitionService.denominationFromLabel('   '), isNull);
      expect(CurrencyRecognitionService.denominationFromLabel('note'), isNull);
      expect(
        CurrencyRecognitionService.denominationFromLabel('banknote'),
        isNull,
      );
      expect(
        CurrencyRecognitionService.denominationFromLabel('unknown'),
        isNull,
      );
      expect(CurrencyRecognitionService.denominationFromLabel('₹'), isNull);
      expect(CurrencyRecognitionService.denominationFromLabel('0'), isNull);
    });
  });

  group('model output to probabilities', () {
    test('leaves an already-normalised distribution untouched', () {
      final List<double> raw = <double>[0.7, 0.2, 0.1];
      final List<double> out = CurrencyRecognitionService.toProbabilities(raw);
      expect(identical(out, raw), isTrue);
    });

    test('applies a stable softmax to logits', () {
      final List<double> out = CurrencyRecognitionService.toProbabilities(
        <double>[1.0, 2.0, 3.0],
      );
      expect(out, hasLength(3));
      expect(out.reduce((double a, double b) => a + b), closeTo(1.0, 1e-9));
      expect(out[2], greaterThan(out[1]));
      expect(out[1], greaterThan(out[0]));
    });

    test('handles large negative logits without overflow', () {
      final List<double> out = CurrencyRecognitionService.toProbabilities(
        <double>[-5.0, -50.0, -100.0],
      );
      expect(out.reduce((double a, double b) => a + b), closeTo(1.0, 1e-9));
      expect(out[0], closeTo(1.0, 1e-6));
    });
  });

  group('model input scaling contract', () {
    test('both bundled models are fed raw 0..255, not pre-normalised', () {
      // Regression: every frame read as a ₹2 coin because the models bake in an
      // internal Rescaling(1/127.5, -1) *and* the service pre-scaled the frame,
      // double-normalising the input down to a near-constant tensor.
      expect(
        CurrencyRecognitionService.inputScalingFor(CurrencyKind.banknote),
        CurrencyInputScaling.raw,
      );
      expect(
        CurrencyRecognitionService.inputScalingFor(CurrencyKind.coin),
        CurrencyInputScaling.raw,
      );
    });

    test('raw scaling passes byte values through unchanged', () {
      for (final double value in <double>[0, 1, 127.5, 200, 255]) {
        expect(
          CurrencyRecognitionService.applyScaling(
            value,
            0,
            CurrencyInputScaling.raw,
          ),
          value,
        );
      }
    });

    test(
      'double normalisation squeezes the whole 0..255 range into a sliver',
      () {
        // Pre-scaling to [-1, 1] and then letting the graph rescale again maps
        // 0..255 into roughly [-1.008, -0.992]: a constant image, which is why the
        // model always answered ₹2. Confirm raw scaling avoids that.
        double doubleNormalised(double raw) {
          final double preScaled = CurrencyRecognitionService.applyScaling(
            raw,
            0,
            CurrencyInputScaling.minusOneToOne,
          );
          return preScaled / 127.5 - 1.0; // the model's baked-in Rescaling
        }

        final double low = doubleNormalised(0);
        final double high = doubleNormalised(255);
        expect(low, closeTo(-1.0078, 1e-3));
        expect(high, closeTo(-0.9922, 1e-3));
        expect(high - low, lessThan(0.02));

        final double rawLow = CurrencyRecognitionService.applyScaling(
          0,
          0,
          CurrencyInputScaling.raw,
        );
        final double rawHigh = CurrencyRecognitionService.applyScaling(
          255,
          0,
          CurrencyInputScaling.raw,
        );
        expect(rawHigh - rawLow, 255);
      },
    );
  });

  group('reliability threshold', () {
    test('a win below the acceptance threshold is not reliable', () {
      const CurrencyRecognition low = CurrencyRecognition(
        kind: CurrencyKind.banknote,
        denomination: 100,
        confidence: 0.42,
        reliable: false,
      );
      expect(low.reliable, isFalse);
      expect(
        low.confidence < CurrencyRecognitionService.defaultThreshold,
        isTrue,
      );
    });

    test('a win that clears the threshold is reliable', () {
      const CurrencyRecognition high = CurrencyRecognition(
        kind: CurrencyKind.coin,
        denomination: 10,
        confidence: 0.91,
        reliable: true,
      );
      expect(high.reliable, isTrue);
      expect(
        high.confidence >= CurrencyRecognitionService.defaultThreshold,
        isTrue,
      );
    });
  });

  group('recognition labels', () {
    test('banknote and coin wording differ', () {
      const CurrencyRecognition note = CurrencyRecognition(
        kind: CurrencyKind.banknote,
        denomination: 50,
        confidence: 0.8,
        reliable: true,
      );
      const CurrencyRecognition coin = CurrencyRecognition(
        kind: CurrencyKind.coin,
        denomination: 5,
        confidence: 0.8,
        reliable: true,
      );
      expect(note.isBanknote, isTrue);
      expect(note.spokenLabel, '50 rupee note');
      expect(note.displayLabel, '₹50 Banknote');
      expect(coin.isBanknote, isFalse);
      expect(coin.spokenLabel, '5 rupee coin');
      expect(coin.displayLabel, '₹5 Coin');
    });

    test('confidence rounds to a whole percentage for display', () {
      const CurrencyRecognition r = CurrencyRecognition(
        kind: CurrencyKind.banknote,
        denomination: 20,
        confidence: 0.876,
        reliable: true,
      );
      expect(r.confidencePercent, 88);
    });

    test('key identifies the recognised denomination per kind', () {
      const CurrencyRecognition note = CurrencyRecognition(
        kind: CurrencyKind.banknote,
        denomination: 100,
        confidence: 0.8,
        reliable: true,
      );
      const CurrencyRecognition coin = CurrencyRecognition(
        kind: CurrencyKind.coin,
        denomination: 100,
        confidence: 0.8,
        reliable: true,
      );
      expect(note.key, 'banknote_100');
      expect(coin.key, 'coin_100');
      expect(note.key == coin.key, isFalse);
    });
  });

  group('frame analysis', () {
    // These tests deliberately do not call ensureLoaded(): a service must
    // report the unavailable state honestly rather than guessing when its
    // model has not loaded yet.
    test('reports modelUnavailable when no model is loaded', () async {
      final CurrencyRecognitionService service = CurrencyRecognitionService();
      await CurrencyRecognitionService.closeAll();

      final CurrencyInferenceResult result = await service.analyze(
        Uint8List(4 * 4 * 4),
        4,
        4,
      );
      expect(result.status, CurrencyInferenceStatus.modelUnavailable);
      expect(result.recognition, isNull);
      expect(result.reason, isNotNull);
      expect(result.reason, contains('No model available'));
    });

    test('reports modelUnavailable per requested kind', () async {
      final CurrencyRecognitionService service = CurrencyRecognitionService();
      await CurrencyRecognitionService.closeAll();

      final CurrencyInferenceResult result = await service.analyze(
        Uint8List(4 * 4 * 4),
        4,
        4,
        kinds: const <CurrencyKind>{CurrencyKind.coin},
      );
      expect(result.status, CurrencyInferenceStatus.modelUnavailable);
      expect(result.reason, contains('coin'));
    });

    test('reports invalidInput for a frame that is too small', () async {
      final CurrencyRecognitionService service = CurrencyRecognitionService();
      await CurrencyRecognitionService.closeAll();

      final CurrencyInferenceResult result = await service.analyze(
        Uint8List(3),
        4,
        4,
      );
      expect(result.status, CurrencyInferenceStatus.invalidInput);
      expect(result.reason, isNotNull);

      expect(
        (await service.analyze(Uint8List(16), 0, 4)).status,
        CurrencyInferenceStatus.invalidInput,
      );
    });

    test('drops a second frame while one is still in flight', () async {
      final CurrencyRecognitionService service = CurrencyRecognitionService();
      await CurrencyRecognitionService.closeAll();

      final Uint8List frame = Uint8List(4 * 4 * 4);
      final Future<CurrencyInferenceResult> first = service.analyze(
        frame,
        4,
        4,
      );
      final CurrencyInferenceResult second = await service.analyze(frame, 4, 4);
      expect(second.status, CurrencyInferenceStatus.busy);

      // The first call finishes normally once the guard is released.
      final CurrencyInferenceResult firstResult = await first;
      expect(firstResult.status, isNot(CurrencyInferenceStatus.busy));
    });

    test('classify is a thin wrapper over analyze', () async {
      final CurrencyRecognitionService service = CurrencyRecognitionService();
      await CurrencyRecognitionService.closeAll();

      final CurrencyRecognition? rec = await service.classify(
        Uint8List(4 * 4 * 4),
        4,
        4,
      );
      expect(rec, isNull);
    });

    test(
      'the bundled detector loads with the verified seven denominations',
      () async {
        final CurrencyRecognitionService service = CurrencyRecognitionService();
        await CurrencyRecognitionService.closeAll();
        expect(service.state, CurrencyModelState.notLoaded);

        await service.ensureLoaded();
        expect(service.state, CurrencyModelState.ready);
        expect(service.anyModelAvailable, isTrue);
        expect(service.loadError, isNull);
        expect(service.supportedDenominations(CurrencyKind.banknote), <int>[
          100,
          10,
          200,
          20,
          500,
          50,
          5,
        ]);
        expect(service.kindLoadError(CurrencyKind.banknote), isNull);
      },
    );
  });

  group('banknote-only contract', () {
    test('coins are never claimed as supported', () {
      final CurrencyRecognitionService service = CurrencyRecognitionService();
      expect(service.hasCoinModel, isFalse);
      expect(service.supportedDenominations(CurrencyKind.coin), isNull);
      expect(
        service.kindLoadError(CurrencyKind.coin),
        contains('not supported'),
      );
    });

    test('the bundled note detector assets are the ones wired in', () {
      expect(
        CurrencyRecognitionService.detectorAsset,
        'assets/ml/currency_notes_yolo.tflite',
      );
      expect(
        CurrencyRecognitionService.detectorLabelsAsset,
        'assets/ml/currency_notes_yolo_labels.txt',
      );
    });

    test('a coin-only request is reported unavailable, not guessed', () async {
      final CurrencyRecognitionService service = CurrencyRecognitionService();
      await CurrencyRecognitionService.closeAll();

      final CurrencyInferenceResult result = await service.analyze(
        Uint8List(4 * 4 * 4),
        4,
        4,
        kinds: const <CurrencyKind>{CurrencyKind.coin},
      );
      expect(result.status, CurrencyInferenceStatus.modelUnavailable);
      expect(result.recognition, isNull);
    });
  });
}
