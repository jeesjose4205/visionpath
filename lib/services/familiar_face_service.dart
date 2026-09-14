import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/familiar_face.dart';

/// FamiliarFaceService owns the local registry of familiar people.
///
/// Records (name + embeddings + metadata) are stored as JSON in
/// SharedPreferences — on-device only, never uploaded. The registry honours
/// the privacy contract of the feature: faces and embeddings stay on the
/// phone, and deleting a person removes their data entirely.
class FamiliarFaceService extends ChangeNotifier {
  static const String _storageKey = 'familiar_faces';

  List<FamiliarFace> _people = const [];
  bool _loaded = false;

  /// Registered people, most recently added first.
  List<FamiliarFace> get people => List.unmodifiable(_people);

  bool get loaded => _loaded;

  /// Load the registry from local storage. Safe to call repeatedly.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_storageKey) ?? const [];
      _people = raw.map((entry) {
        try {
          return FamiliarFace.fromJson(
            jsonDecode(entry) as Map<String, dynamic>,
          );
        } catch (e) {
          print('FAMILIAR_FACE_DECODE_ERROR: $e');
          return null;
        }
      }).whereType<FamiliarFace>().toList();
      _people.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _loaded = true;
      print('FAMILIAR_FACES_LOADED: ${_people.length}');
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

  /// Register (or replace) a person. [samples] are the raw samples that were
  /// validated during registration.
  Future<FamiliarFace> addPerson({
    required String name,
    String? relationship,
    required List<List<double>> samples,
  }) async {
    final mean = _averageOf(samples);
    final face = FamiliarFace(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim(),
      relationship: relationship?.trim().isEmpty ?? true
          ? null
          : relationship!.trim(),
      embedding: mean,
      sampleCount: samples.length,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _people.insert(0, face);
    await _persist();
    notifyListeners();
    print('FAMILIAR_FACE_ADDED: ${face.name} samples=${samples.length}');
    return face;
  }

  /// Update name / relationship / embedding for an existing person.
  Future<bool> updatePerson(
    String id, {
    String? name,
    String? relationship,
    List<List<double>>? samples,
  }) async {
    final index = _people.indexWhere((p) => p.id == id);
    if (index < 0) return false;
    final existing = _people[index];
    _people[index] = existing.copyWith(
      name: name,
      relationship: relationship,
      embedding: samples != null ? _averageOf(samples) : null,
      sampleCount: samples?.length,
    );
    await _persist();
    notifyListeners();
    return true;
  }

  /// Delete a person's record entirely (privacy: removes all biometric data).
  Future<bool> deletePerson(String id) async {
    final before = _people.length;
    _people = _people.where((p) => p.id != id).toList();
    if (_people.length == before) return false;
    await _persist();
    notifyListeners();
    print('FAMILIAR_FACE_DELETED: $id');
    return true;
  }

  /// Pointwise-mean of samples, L2-normalized (matches recognition service).
  List<double> _averageOf(List<List<double>> samples) {
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

  double _norm(List<double> v) {
    double sum = 0;
    for (final x in v) {
      sum += x * x;
    }
    return math.sqrt(sum);
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _storageKey,
        _people.map((p) => jsonEncode(p.toJson())).toList(),
      );
    } catch (e) {
      print('FAMILIAR_FACES_PERSIST_FAILED: $e');
    }
  }
}