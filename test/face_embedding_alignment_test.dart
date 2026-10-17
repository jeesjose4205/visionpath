import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/models/familiar_face.dart';
import 'package:visionpath/services/face_embedding_service.dart';

FamiliarFace person({
  String id = '1',
  String name = 'P',
  List<double> embedding = const [1, 0],
  List<List<double>> templates = const [],
  String? model,
}) =>
    FamiliarFace(
      id: id,
      name: name,
      embedding: embedding,
      templates: templates,
      model: model,
      sampleCount: templates.isEmpty ? 1 : templates.length,
      createdAt: 1000,
    );

void main() {
  final service = FaceEmbeddingService.instance;

  group('alignment regression (ArcFace 5-point Umeyama)', () {
    // Canonical ArcFace template (112x112 image space).
    final canonical = <List<double>>[
      [38.2946, 51.6963],
      [73.5318, 51.5014],
      [56.0252, 71.7366],
      [41.5493, 92.3655],
      [70.7299, 92.2041],
    ];

    List<List<double>> applySimilarity(
      List<List<double>> pts,
      double scale,
      double deg,
      double tx,
      double ty,
    ) {
      final th = deg * math.pi / 180;
      final c = math.cos(th), s = math.sin(th);
      return [
        for (final p in pts)
          [
            scale * (c * p[0] - s * p[1]) + tx,
            scale * (s * p[0] + c * p[1]) + ty,
          ],
      ];
    }

    test('recovers a known similarity transform exactly', () {
      final src = applySimilarity(canonical, 2.5, 20, 120, 40);
      final back = FaceEmbeddingService.mapCanonicalToSource(src);
      expect(back, hasLength(canonical.length));
      var maxErr = 0.0;
      for (var i = 0; i < src.length; i++) {
        final dx = back[i][0] - src[i][0];
        final dy = back[i][1] - src[i][1];
        maxErr = math.max(maxErr, math.sqrt(dx * dx + dy * dy));
      }
      // The previous buggy implementation produced ~200px of error here.
      expect(maxErr, lessThan(1e-6));
    });

    test('recovers transform at a different scale and offset', () {
      final src = applySimilarity(canonical, 1.2, -15, 240, 300);
      final back = FaceEmbeddingService.mapCanonicalToSource(src);
      var maxErr = 0.0;
      for (var i = 0; i < src.length; i++) {
        final dx = back[i][0] - src[i][0];
        final dy = back[i][1] - src[i][1];
        maxErr = math.max(maxErr, math.sqrt(dx * dx + dy * dy));
      }
      expect(maxErr, lessThan(1e-6));
    });
  });

  group('identify gating and validation', () {
    test('matches the person whose template is closest', () {
      final a = person(id: 'a', name: 'A', templates: [
        [1.0, 0.0],
        [0.0, 1.0],
      ]);
      final b = person(id: 'b', name: 'B', embedding: [-1.0, 0.0], templates: [
        [-1.0, 0.0]
      ]);
      final match = service.identify([1.0, 0.0], [a, b]);
      expect(match, isNotNull);
      expect(match!.person.id, 'a');
      expect(match.similarity, closeTo(1.0, 1e-9));
    });

    test('single-person registry matches a near-identical vector', () {
      final a = person(id: 'a', name: 'A', embedding: [0.6, 0.8]);
      final match = service.identify([0.6, 0.8], [a]);
      expect(match, isNotNull);
      expect(match!.person.id, 'a');
      expect(match.similarity, closeTo(1.0, 1e-9));
    });

    test('different vector in single-person registry is rejected by threshold',
        () {
      final a = person(id: 'a', name: 'A', embedding: [1.0, 0.0]);
      // cosine 0 -> below default threshold
      expect(service.identify([0.0, 1.0], [a]), isNull);
    });

    test('returns null when the top two are ambiguous', () {
      final a = person(id: 'a', name: 'A', embedding: [1.0, 0.0]);
      final b = person(id: 'b', name: 'B', embedding: [0.999, 0.0447]);
      expect(service.identify([1.0, 0.0], [a, b]), isNull);
    });

    test('ignores people whose embedding dimension is incompatible', () {
      final a = person(id: 'a', name: 'A', embedding: [1.0, 0.0, 0.0]);
      expect(service.identify([1.0, 0.0], [a]), isNull);
    });

    test('rejects people with a different model id (same dimension)', () {
      final a = person(
        id: 'a',
        name: 'A',
        embedding: [1.0, 0.0],
        templates: [
          [1.0, 0.0]
        ],
        model: 'mobilefacenet',
      );
      expect(service.identify([1.0, 0.0], [a]), isNull);
    });

    test('accepts legacy records with a null model id when dim matches', () {
      final a = person(id: 'a', name: 'A', embedding: [1.0, 0.0], model: null);
      final match = service.identify([1.0, 0.0], [a]);
      expect(match, isNotNull);
      expect(match!.person.id, 'a');
    });

    test('rejects a zero/invalid probe embedding', () {
      final a = person(id: 'a', name: 'A', embedding: [1.0, 0.0]);
      expect(service.identify(const [], [a]), isNull);
      expect(service.identify([double.nan, 0.0], [a]), isNull);
      expect(service.identify([double.infinity, 0.0], [a]), isNull);
    });

    test('rejects empty registry', () {
      expect(service.identify([1.0, 0.0], const []), isNull);
    });
  });

  group('normalizedMean', () {
    test('is the L2-normalized pointwise mean', () {
      final mean = FaceEmbeddingService.normalizedMean([
        [1.0, 0.0],
        [0.0, 1.0],
      ]);
      expect(mean[0], closeTo(0.70710678, 1e-6));
      expect(mean[1], closeTo(0.70710678, 1e-6));
    });

    test('returns empty for an empty sample list', () {
      expect(FaceEmbeddingService.normalizedMean(const []), isEmpty);
    });
  });
}
