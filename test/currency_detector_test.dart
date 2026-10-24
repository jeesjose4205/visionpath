import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/services/currency_detector.dart';

/// Build a raw `[1, 300, 6]` detector output from explicit candidate rows.
/// Missing rows are left as zero (confidence 0), which the decoder drops.
Float32List rawOutput(List<List<double>> rows) {
  final Float32List out = Float32List(
    CurrencyDetector.numBoxes * CurrencyDetector.boxStride,
  );
  for (int i = 0; i < rows.length; i++) {
    for (int j = 0; j < CurrencyDetector.boxStride; j++) {
      out[i * CurrencyDetector.boxStride + j] = rows[i][j];
    }
  }
  return out;
}

/// A solid-colour RGBA frame.
Uint8List solidFrame(
  int width,
  int height, {
  required int r,
  required int g,
  required int b,
}) {
  final Uint8List bytes = Uint8List(width * height * 4);
  for (int i = 0; i < width * height; i++) {
    bytes[i * 4] = r;
    bytes[i * 4 + 1] = g;
    bytes[i * 4 + 2] = b;
    bytes[i * 4 + 3] = 255;
  }
  return bytes;
}

void main() {
  group('class mapping', () {
    test('default label order maps to the expected denominations', () {
      final CurrencyDetector detector = CurrencyDetector();
      expect(detector.labels, CurrencyDetector.defaultLabels);
      expect(detector.denominations, <int?>[100, 10, 200, 20, 500, 50, 5]);
    });

    test('detector labels carry the rupee value through the shared parser', () {
      expect(CurrencyDetector.denominationFromLabel('100IndianRupees'), 100);
      expect(CurrencyDetector.denominationFromLabel('10IndianRupees'), 10);
      expect(CurrencyDetector.denominationFromLabel('5IndianRupees'), 5);
      expect(CurrencyDetector.denominationFromLabel('background'), isNull);
    });

    test(
      'only the embedded seven-class label order is accepted as verified',
      () {
        expect(
          CurrencyDetector.hasExpectedLabelOrder(
            CurrencyDetector.defaultLabels,
          ),
          isTrue,
        );
        expect(
          CurrencyDetector.hasExpectedLabelOrder(<String>[
            '10IndianRupees',
            '100IndianRupees',
            '200IndianRupees',
            '20IndianRupees',
            '500IndianRupees',
            '50IndianRupees',
            '5IndianRupees',
          ]),
          isFalse,
        );
      },
    );

    test('a class with no denomination is never decoded', () {
      final CurrencyDetector detector = CurrencyDetector(
        labels: <String>['background', '50IndianRupees'],
      );
      expect(detector.denominations, <int?>[null, 50]);

      final List<CurrencyDetection> detections = detector.decode(
        rawOutput(<List<double>>[
          <double>[0.1, 0.1, 0.5, 0.5, 0.9, 0], // background -> dropped
          <double>[0.1, 0.1, 0.5, 0.5, 0.8, 1], // ₹50
        ]),
      );
      expect(detections, hasLength(1));
      expect(detections.single.denomination, 50);
    });
  });

  group('input contract', () {
    test('preprocess rejects a degenerate frame', () {
      expect(CurrencyDetector.preprocess(Uint8List(0), 0, 0), isNull);
      expect(CurrencyDetector.preprocess(Uint8List(7), 2, 2), isNull);
    });

    test('tensor is 640x640x3 and preserves RGB order, scaled to 0..1', () {
      final Uint8List frame = solidFrame(640, 640, r: 255, g: 128, b: 0);
      final LetterboxedInput input = CurrencyDetector.preprocess(
        frame,
        640,
        640,
      )!;
      expect(input.tensor.length, 640 * 640 * 3);
      expect(input.tensor[0], closeTo(1.0, 1e-6)); // R
      expect(input.tensor[1], closeTo(128 / 255, 1e-6)); // G
      expect(input.tensor[2], closeTo(0.0, 1e-6)); // B
      expect(CurrencyDetector.inputShape, <int>[1, 640, 640, 3]);
      expect(CurrencyDetector.outputShape, <int>[1, 300, 6]);
    });

    test('a non-square frame is letterboxed with a grey (114) pad', () {
      // 320x640 frame: width is the short side, so scale = 1 and the frame is
      // centred with 160px of pad on each side.
      final Uint8List frame = solidFrame(320, 640, r: 51, g: 102, b: 153);
      final LetterboxedInput input = CurrencyDetector.preprocess(
        frame,
        320,
        640,
      )!;

      expect(input.transform.scale, 1.0);
      expect(input.transform.padX, 160.0);
      expect(input.transform.padY, 0.0);

      expect(input.tensor[0], closeTo(CurrencyDetector.padValue / 255.0, 1e-6));

      final int contentIndex = (0 * 640 + 160) * 3;
      expect(input.tensor[contentIndex], closeTo(51 / 255, 1e-6));
      expect(input.tensor[contentIndex + 1], closeTo(102 / 255, 1e-6));
      expect(input.tensor[contentIndex + 2], closeTo(153 / 255, 1e-6));
    });

    test('centre crops run full frame first, then coarsest to tightest', () {
      final List<CurrencyCrop> crops = CurrencyDetector.centerCrops(320, 640);
      expect(crops.first.isFullFrame, isTrue);
      expect(crops.first.left, 0);
      expect(crops.first.width, 320);
      expect(crops.first.height, 640);

      expect(
        crops.skip(1).map((CurrencyCrop c) => c.fraction).toList(),
        <double>[0.8, 0.6, 0.45, 0.35, 0.3],
      );
      expect(
        crops.skip(1).every((CurrencyCrop c) => c.width == c.height),
        isTrue,
      );
      expect(crops[1].width, 256);
      expect(crops[1].left, 32);
      expect(crops[1].top, 192);
      expect(crops.last.width, 96);
      expect(crops.last.left, 112);
      expect(crops.last.top, 272);

      for (final CurrencyCrop crop in crops) {
        expect(crop.left, greaterThanOrEqualTo(0));
        expect(crop.top, greaterThanOrEqualTo(0));
        expect(crop.left + crop.width, lessThanOrEqualTo(320));
        expect(crop.top + crop.height, lessThanOrEqualTo(640));
      }
    });

    test('centre crops de-duplicate on tiny frames and reject empty ones', () {
      final List<CurrencyCrop> tiny = CurrencyDetector.centerCrops(3, 3);
      expect(tiny.map((CurrencyCrop c) => c.width).toList(), <int>[3, 2, 1]);
      expect(CurrencyDetector.centerCrops(0, 10), isEmpty);
      expect(CurrencyDetector.centerCrops(10, -1), isEmpty);
    });

    test(
      'a crop keeps frame-relative coordinates and samples only the crop',
      () {
        const int width = 320;
        const int height = 640;
        final Uint8List frame = solidFrame(width, height, r: 255, g: 0, b: 0);
        final CurrencyCrop crop = CurrencyDetector.centerCrops(
          width,
          height,
        )[1];
        for (int y = crop.top; y < crop.top + crop.height; y++) {
          for (int x = crop.left; x < crop.left + crop.width; x++) {
            final int i = (y * width + x) * 4;
            frame[i] = 0;
            frame[i + 1] = 255;
            frame[i + 2] = 0;
          }
        }

        final LetterboxedInput input = CurrencyDetector.preprocess(
          frame,
          width,
          height,
          crop: crop,
        )!;
        expect(input.tensor.length, 640 * 640 * 3);
        expect(input.tensor[0], closeTo(0.0, 1e-6));
        expect(input.tensor[1], closeTo(1.0, 1e-6));
        expect(input.tensor[2], closeTo(0.0, 1e-6));

        final LetterboxTransform t = input.transform;
        expect(t.frameWidth, width);
        expect(t.frameHeight, height);
        expect(t.sourceLeft, crop.left);
        expect(t.sourceTop, crop.top);
        expect(t.padX, 0);
        expect(t.padY, 0);
        expect(t.frameX(0), closeTo(crop.left / width, 1e-6));
        expect(t.frameX(640), closeTo((crop.left + crop.width) / width, 1e-6));
        expect(t.frameY(0), closeTo(crop.top / height, 1e-6));
        expect(t.frameY(640), closeTo((crop.top + crop.height) / height, 1e-6));
        expect(t.frameX(320), closeTo(0.5, 1e-6));
        expect(t.frameY(320), closeTo(0.5, 1e-6));
      },
    );

    test('letterbox transform maps input coordinates back to the frame', () {
      final Uint8List frame = solidFrame(320, 640, r: 10, g: 10, b: 10);
      final LetterboxedInput input = CurrencyDetector.preprocess(
        frame,
        320,
        640,
      )!;

      // Input x=160 is the left edge of the content; x=480 the right edge.
      expect(input.transform.frameX(160), closeTo(0.0, 1e-6));
      expect(input.transform.frameX(480), closeTo(1.0, 1e-6));
      expect(input.transform.frameX(320), closeTo(0.5, 1e-6));
      // Inside the pad maps out of range and is clamped.
      expect(input.transform.frameX(0), 0.0);
      // y spans the full height with no pad.
      expect(input.transform.frameY(0), closeTo(0.0, 1e-6));
      expect(input.transform.frameY(640), closeTo(1.0, 1e-6));
    });
  });

  group('output decoding', () {
    final CurrencyDetector detector = CurrencyDetector();

    test('an empty (all zero) output produces no detections', () {
      expect(detector.decode(rawOutput(<List<double>>[])), isEmpty);
    });

    test('a malformed (too short) tensor is rejected safely', () {
      expect(detector.decode(Float32List(10)), isEmpty);
    });

    test('rows below the confidence floor are dropped', () {
      final List<CurrencyDetection> detections = detector.decode(
        rawOutput(<List<double>>[
          <double>[0.1, 0.1, 0.5, 0.5, 0.10, 0], // below floor
          <double>[0.1, 0.1, 0.5, 0.5, 0.30, 0], // above floor
        ]),
        confidenceThreshold: CurrencyDetector.confidenceFloor,
      );
      expect(detections, hasLength(1));
      expect(detections.single.confidence, closeTo(0.30, 1e-6));
    });

    test('out-of-range and negative class indices are dropped', () {
      final List<CurrencyDetection> detections = detector.decode(
        rawOutput(<List<double>>[
          <double>[0.1, 0.1, 0.5, 0.5, 0.9, 99],
          <double>[0.1, 0.1, 0.5, 0.5, 0.9, -1],
          <double>[0.1, 0.1, 0.5, 0.5, 0.9, 0],
        ]),
      );
      expect(detections, hasLength(1));
      expect(detections.single.denomination, 100);
    });

    test('fractional class IDs and malformed rows are dropped safely', () {
      final List<CurrencyDetection> detections = detector.decode(
        rawOutput(<List<double>>[
          <double>[0.1, 0.1, 0.5, 0.5, 0.9, 0.49],
          <double>[0.1, 0.1, 0.5, 0.5, 1.01, 0],
          <double>[double.nan, 0.1, 0.5, 0.5, 0.9, 0],
          <double>[0.5, 0.1, 0.1, 0.5, 0.9, 0],
          <double>[0.1, 0.1, 0.5, 0.5, 0.9, 0],
        ]),
      );

      expect(detections, hasLength(1));
      expect(detections.single.denomination, 100);
    });

    test(
      'two non-overlapping notes both survive, best is the confident one',
      () {
        final List<CurrencyDetection> detections = detector.decode(
          rawOutput(<List<double>>[
            <double>[0.05, 0.05, 0.35, 0.35, 0.91, 0], // ₹100
            <double>[0.60, 0.60, 0.95, 0.95, 0.72, 4], // ₹500
          ]),
        );
        expect(detections, hasLength(2));
        expect(detections.first.denomination, 100);
        expect(CurrencyDetector.best(detections)!.denomination, 100);
        expect(
          CurrencyDetector.best(detections)!.confidence,
          closeTo(0.91, 1e-6),
        );
      },
    );

    test('overlapping duplicates are de-duplicated to the top score', () {
      final List<CurrencyDetection> detections = detector.decode(
        rawOutput(<List<double>>[
          <double>[0.10, 0.10, 0.60, 0.60, 0.95, 1], // ₹10
          <double>[0.11, 0.11, 0.61, 0.61, 0.60, 5], // same box, lower score
        ]),
      );
      expect(detections, hasLength(1));
      expect(detections.single.denomination, 10);
      expect(detections.single.confidence, closeTo(0.95, 1e-6));
    });

    test('coordinates are mapped onto the frame when a transform is given', () {
      final Uint8List frame = solidFrame(320, 640, r: 20, g: 20, b: 20);
      final LetterboxedInput input = CurrencyDetector.preprocess(
        frame,
        320,
        640,
      )!;
      final List<CurrencyDetection> detections = detector.decode(
        rawOutput(<List<double>>[
          <double>[0.25, 0.00, 0.75, 1.00, 0.88, 3], // ₹20 across the width
        ]),
        transform: input.transform,
      );
      expect(detections, hasLength(1));
      final CurrencyDetection d = detections.single;
      expect(d.left, closeTo(0.0, 1e-6));
      expect(d.right, closeTo(1.0, 1e-6));
      expect(d.top, closeTo(0.0, 1e-6));
      expect(d.bottom, closeTo(1.0, 1e-6));
    });

    test('the confidence filter is inclusive at the threshold', () {
      // Pinned so a future edit cannot silently make an at-threshold detection
      // fail (>= vs >). A frame whose best score equals the threshold is a
      // borderline win and is accepted by contract.
      const double threshold = 0.60;
      final List<CurrencyDetection> atThreshold = detector.decode(
        rawOutput(<List<double>>[
          <double>[0.1, 0.1, 0.5, 0.5, 0.60, 0],
        ]),
        confidenceThreshold: threshold,
      );
      expect(atThreshold, hasLength(1));
      expect(atThreshold.single.confidence, closeTo(0.60, 1e-6));

      final List<CurrencyDetection> justBelow = detector.decode(
        rawOutput(<List<double>>[
          <double>[0.1, 0.1, 0.5, 0.5, 0.5999, 0],
        ]),
        confidenceThreshold: threshold,
      );
      expect(justBelow, isEmpty);
    });

    test('a rejected detection keeps its own confidence, it is not rescaled', () {
      // The "Confidence X% is below the Y% threshold" message reports the raw
      // winning detection's confidence, so a 0.31 detection must still read as
      // 31% after decoding.
      final List<CurrencyDetection> detections = detector.decode(
        rawOutput(<List<double>>[
          <double>[0.1, 0.1, 0.5, 0.5, 0.31, 3],
        ]),
        confidenceThreshold: 0.60,
      );
      expect(detections, isEmpty);
      final List<CurrencyDetection> sameRow = detector.decode(
        rawOutput(<List<double>>[
          <double>[0.1, 0.1, 0.5, 0.5, 0.31, 3],
        ]),
        confidenceThreshold: 0.25,
      );
      expect(sameRow.single.confidence, closeTo(0.31, 1e-6));
      expect(sameRow.single.denomination, 20);
      expect((sameRow.single.confidence * 100).round(), 31);
    });
  });
}
