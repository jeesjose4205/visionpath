import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/familiar_face.dart';
import 'familiar_face_repository.dart';

class FamiliarFaceService extends ChangeNotifier {
  final FamiliarFaceRepository _repo;
  List<FamiliarFace> _people = const [];
  bool _loaded = false;

  FamiliarFaceService({FamiliarFaceRepository? repository})
      : _repo = repository ?? SharedPreferencesFamiliarFaceRepository();

  List<FamiliarFace> get people => List.unmodifiable(_people);
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      _people = await _repo.loadAll();
      _people.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _loaded = true;
      print('FAMILIAR_FACES_LOADED: count=${_people.length} '
          'dims=${_people.map((p) => p.embedding.length).toSet().toList()} '
          'models=${_people.map((p) => p.model).toSet().toList()}');
    } catch (e) {
      print('FAMILIAR_FACES_LOAD_FAILED: $e');
      _people = const [];
      _loaded = true;
    }
    notifyListeners();
  }

  FamiliarFace? byId(String id) {
    for (final p in _people) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<FamiliarFace> addPerson({
    required String name,
    String? relationship,
    required List<List<double>> samples,
    String? model,
  }) async {
    final mean = normalizedMean(samples);
    final face = FamiliarFace(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim(),
      relationship: relationship?.trim().isEmpty ?? true ? null : relationship!.trim(),
      embedding: mean,
      sampleCount: samples.length,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      templates: samples,
      model: model,
    );
    _people.insert(0, face);
    await _persist();
    notifyListeners();
    print('FAMILIAR_FACE_ADDED: ${face.name} samples=${samples.length} '
        'dim=${mean.length} model=${model ?? "geometric"}');
    return face;
  }

  Future<FamiliarFace> updatePerson(String id, {String? name, String? relationship}) async {
    final idx = _people.indexWhere((p) => p.id == id);
    if (idx == -1) {
      throw StateError('Person  not found');
    }
    final p = _people[idx];
    final updated = p.copyWith(name: name, relationship: relationship);
    _people[idx] = updated;
    await _persist();
    notifyListeners();
    return updated;
  }

  Future<bool> deletePerson(String id) async {
    final before = _people.length;
    _people = _people.where((p) => p.id != id).toList();
    await _persist();
    notifyListeners();
    print('FAMILIAR_FACE_REMOVED: $id');
    return before > _people.length;
  }

  Future<bool> removePerson(String id) async {
    return deletePerson(id);
  }

  Future<void> _persist() async {
    await _repo.saveAll(_people);
    print('FAMILIAR_FACES_SAVED: count=${_people.length}');
  }

  static List<double> normalizedMean(List<List<double>> samples) {
    if (samples.isEmpty) return const [];
    final dims = samples.first.length;
    final mean = List<double>.filled(dims, 0);
    for (final s in samples) {
      if (s.length != dims) continue;
      for (var i = 0; i < dims; i++) {
        mean[i] += s[i];
      }
    }
    final count = samples.where((s) => s.length == dims).length;
    if (count == 0) return const [];
    for (var i = 0; i < dims; i++) {
      mean[i] /= count;
    }
    final norm = _norm(mean);
    if (norm < 1e-9) return const [];
    return [for (final v in mean) v / norm];
  }

  static double _norm(List<double> v) {
    double sum = 0;
    for (final x in v) {
      sum += x * x;
    }
    return math.sqrt(sum);
  }
}
