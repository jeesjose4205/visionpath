import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/models/familiar_face.dart';
import 'package:visionpath/services/face_embedding_service.dart';
import 'package:visionpath/services/familiar_face_repository.dart';
import 'package:visionpath/services/familiar_face_service.dart';

FamiliarFace person({
  String id = '1',
  String name = 'Mother',
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
  group('FamiliarFace serialization', () {
    test('round-trips templates and model', () {
      final f = person(
        templates: [
          [1.0, 0.0],
          [0.0, 1.0],
        ],
        model: 'arcface_w600k_mbf',
      );
      final back = FamiliarFace.fromJson(f.toJson());
      expect(back.templates, f.templates);
      expect(back.model, 'arcface_w600k_mbf');
      expect(back.embedding, f.embedding);
    });

    test('legacy record without templates derives them from the mean', () {
      final json = {
        'id': '9',
        'name': 'Old',
        'embedding': [0.6, 0.8],
        'sampleCount': 4,
        'createdAt': 5,
      };
      final f = FamiliarFace.fromJson(json);
      expect(f.templates, [
        [0.6, 0.8]
      ]);
      expect(f.model, isNull);
    });
  });

  group('FamiliarFaceService with repository', () {
    test('stores per-sample templates and model, then reloads them', () async {
      final repo = InMemoryFamiliarFaceRepository();
      final service = FamiliarFaceService(repository: repo);
      await service.load();

      await service.addPerson(
        name: 'Mother',
        samples: [
          [1.0, 0.0],
          [0.0, 1.0],
        ],
        model: 'arcface_w600k_mbf',
      );

      final reloaded = FamiliarFaceService(repository: repo);
      await reloaded.load();
      expect(reloaded.people, hasLength(1));
      final p = reloaded.people.single;
      expect(p.templates, hasLength(2));
      expect(p.model, 'arcface_w600k_mbf');
      // Representative embedding is the L2-normalized mean of the samples.
      expect(p.embedding[0], closeTo(0.70710678, 1e-6));
      expect(p.embedding[1], closeTo(0.70710678, 1e-6));
    });

    test('delete removes the record entirely', () async {
      final repo = InMemoryFamiliarFaceRepository();
      final service = FamiliarFaceService(repository: repo);
      await service.load();
      final added = await service.addPerson(name: 'A', samples: [
        [1.0, 0.0]
      ]);
      expect(await service.deletePerson(added.id), isTrue);
      expect(service.people, isEmpty);
      expect(await repo.loadAll(), isEmpty);
    });
  });

  group('FaceEmbeddingService.identify (templates + margin)', () {
    final service = FaceEmbeddingService.instance;

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

    test('returns null when the top two are ambiguous', () {
      final a = person(id: 'a', name: 'A', embedding: [1.0, 0.0]);
      final b = person(id: 'b', name: 'B', embedding: [0.999, 0.0447]);
      expect(service.identify([1.0, 0.0], [a, b]), isNull);
    });

    test('ignores people whose embedding dimension is incompatible', () {
      final a = person(id: 'a', name: 'A', embedding: [1.0, 0.0, 0.0]);
      expect(service.identify([1.0, 0.0], [a]), isNull);
    });
  });
}