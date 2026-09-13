import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/emergency_contact.dart';

enum ContactSaveResult {
  success,
  duplicate,
  maxReached,
  invalid,
}

/// Persists emergency contacts as JSON strings under the same
/// `emergency_contacts` key the previous implementation used, so existing
/// saved contacts survive the rebuild.
class EmergencyContactService extends ChangeNotifier {
  static const int maxContacts = 5;
  static const String _contactsKey = 'emergency_contacts';

  final List<EmergencyContact> _contacts = [];
  bool _loaded = false;

  List<EmergencyContact> get contacts => List.unmodifiable(_contacts);
  bool get loaded => _loaded;
  bool get hasReachedMax => _contacts.length >= maxContacts;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_contactsKey) ?? const [];
    _contacts
      ..clear()
      ..addAll(raw.map(_decodeEntry).whereType<EmergencyContact>());
    _loaded = true;
    notifyListeners();
  }

  EmergencyContact? _decodeEntry(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return EmergencyContact.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _contactsKey,
      _contacts.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  /// Adds a contact. Returns a [ContactSaveResult] describing the outcome so
  /// the UI can show specific guidance to the user.
  Future<ContactSaveResult> addContact(String name, String phone) async {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    if (!isValidName(trimmedName) || !isValidPhone(trimmedPhone)) {
      return ContactSaveResult.invalid;
    }
    if (hasReachedMax) {
      return ContactSaveResult.maxReached;
    }
    if (_findIndexByPhone(trimmedPhone) != -1) {
      return ContactSaveResult.duplicate;
    }
    _contacts.add(EmergencyContact(name: trimmedName, phone: trimmedPhone));
    await _persist();
    notifyListeners();
    return ContactSaveResult.success;
  }

  /// Updates the contact at [index]. [currentPhone] lets the editor keep the
  /// same phone number without being flagged as a duplicate.
  Future<ContactSaveResult> updateContact(
    int index,
    String name,
    String phone, {
    String? currentPhone,
  }) async {
    if (index < 0 || index >= _contacts.length) {
      return ContactSaveResult.invalid;
    }
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    if (!isValidName(trimmedName) || !isValidPhone(trimmedPhone)) {
      return ContactSaveResult.invalid;
    }
    final existingIndex = _findIndexByPhone(trimmedPhone);
    if (existingIndex != -1 &&
        existingIndex != index &&
        normalizePhone(currentPhone ?? '') != normalizePhone(trimmedPhone)) {
      return ContactSaveResult.duplicate;
    }
    _contacts[index] = EmergencyContact(
      name: trimmedName,
      phone: trimmedPhone,
    );
    await _persist();
    notifyListeners();
    return ContactSaveResult.success;
  }

  Future<void> deleteContact(int index) async {
    if (index < 0 || index >= _contacts.length) return;
    _contacts.removeAt(index);
    await _persist();
    notifyListeners();
  }

  EmergencyContact? contactAt(int index) {
    if (index < 0 || index >= _contacts.length) return null;
    return _contacts[index];
  }

  int _findIndexByPhone(String phone) {
    final target = normalizePhone(phone);
    for (var i = 0; i < _contacts.length; i++) {
      if (normalizePhone(_contacts[i].phone) == target) {
        return i;
      }
    }
    return -1;
  }

  static bool isValidName(String name) => name.trim().isNotEmpty;

  static bool isValidPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 8 && digits.length <= 15;
  }

  /// Canonical phone form used for duplicate detection: digits only, keeping
  /// an optional leading `+`.
  static String normalizePhone(String phone) {
    var normalized = phone.replaceAll(RegExp(r'[\s\-().]'), '');
    var digitsOnly = normalized.replaceAll(RegExp(r'\D'), '');
    return normalized.startsWith('+')
        ? '+$digitsOnly'
        : digitsOnly;
  }
}