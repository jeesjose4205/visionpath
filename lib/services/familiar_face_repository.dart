import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/familiar_face.dart';

/// Persistence boundary for the familiar-face registry.
///
/// The recognition pipeline never talks to storage directly — it goes through
/// this interface. Keeping it an interface means the on-device
/// SharedPreferences store can later be swapped (e.g. for an encrypted file or
/// a different backend) without touching the recognition code, and it lets
/// tests supply an in-memory implementation.
///
/// Privacy contract: implementations must keep everything on-device and remove
/// all data for a person when their record is deleted.
abstract class FamiliarFaceRepository {
  Future<List<FamiliarFace>> loadAll();
  Future<void> saveAll(List<FamiliarFace> people);
}

/// On-device repository backed by SharedPreferences.
///
/// Each person is stored as one JSON string in a string list under a single
/// key, so deletion trivially removes every trace of that person.
class SharedPreferencesFamiliarFaceRepository implements FamiliarFaceRepository {
  SharedPreferencesFamiliarFaceRepository({this.storageKey = defaultKey});

  static const String defaultKey = 'familiar_faces';

  final String storageKey;

  @override
  Future<List<FamiliarFace>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(storageKey) ?? const [];
    final people = <FamiliarFace>[];
    for (final entry in raw) {
      try {
        people.add(FamiliarFace.fromJson(jsonDecode(entry) as Map<String, dynamic>));
      } catch (e) {
        print('FAMILIAR_FACE_DECODE_ERROR: $e');
      }
    }
    return people;
  }

  @override
  Future<void> saveAll(List<FamiliarFace> people) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      storageKey,
      people.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }
}

/// In-memory repository for tests and previews.
class InMemoryFamiliarFaceRepository implements FamiliarFaceRepository {
  InMemoryFamiliarFaceRepository([List<FamiliarFace>? initial])
      : _people = [...?initial];

  List<FamiliarFace> _people;

  @override
  Future<List<FamiliarFace>> loadAll() async => [..._people];

  @override
  Future<void> saveAll(List<FamiliarFace> people) async {
    _people = [...people];
  }
}