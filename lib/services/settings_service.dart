import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// Centralized, persistent application settings for VisionPath AI.
///
/// All preference keys live here (never scattered in UI files). Values are
/// cached in memory after [load] and persisted to [SharedPreferences] on
/// every update. Settings are intentionally separate from user data
/// (familiar faces, emergency contacts, history), so [resetToDefaults]
/// never touches those stores.
class SettingsService extends ChangeNotifier {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  static const String _kVoiceGuidance = 'setting.voiceGuidance';
  static const String _kGlobalVoiceMuted = 'setting.globalVoiceMuted';
  static const String _kSpeechRate = 'setting.speechRate';
  static const String _kVoiceVolume = 'setting.voiceVolume';
  static const String _kVoiceLanguage = 'setting.voiceLanguage';
  static const String _kRepeatInstruction = 'setting.repeatInstruction';
  static const String _kAnnouncementCooldown = 'setting.announcementCooldown';
  static const String _kLargeText = 'setting.largeText';
  static const String _kHighContrast = 'setting.highContrast';
  static const String _kLargeButtons = 'setting.largeButtons';
  static const String _kHapticFeedback = 'setting.hapticFeedback';
  static const String _kVoiceFirstMode = 'setting.voiceFirstMode';
  static const String _kReduceAnimations = 'setting.reduceAnimations';
  static const String _kNavVoice = 'setting.navVoice';
  static const String _kObstacleSensitivity = 'setting.obstacleSensitivity';
  static const String _kGuidanceMode = 'setting.guidanceMode';
  static const String _kCloseObstacleWarnings = 'setting.closeObstacleWarnings';
  static const String _kDetectionVoice = 'setting.detectionVoice';
  static const String _kPeopleAnns = 'setting.peopleAnns';
  static const String _kVehicleAnns = 'setting.vehicleAnns';
  static const String _kAnimalAnns = 'setting.animalAnns';
  static const String _kFurnitureAnns = 'setting.furnitureAnns';
  static const String _kObstacleAnns = 'setting.obstacleAnns';
  static const String _kDetectionSensitivity = 'setting.detectionSensitivity';
  static const String _kReadAutoRead = 'setting.readAutoRead';
  static const String _kTextPosGuidance = 'setting.textPosGuidance';
  static const String _kOcrLanguage = 'setting.ocrLanguage';
  static const String _kReadingSpeed = 'setting.readingSpeed';
  static const String _kFacesEnabled = 'setting.facesEnabled';
  static const String _kFaceVoice = 'setting.faceVoice';
  static const String _kUnknownAnns = 'setting.unknownAnns';
  static const String _kFaceSensitivity = 'setting.faceSensitivity';
  static const String _kFaceCooldown = 'setting.faceCooldown';
  static const String _kSosHoldDuration = 'setting.sosHoldDuration';
  static const String _kSosConfirmation = 'setting.sosConfirmation';
  static const String _kAppLanguage = 'setting.appLanguage';
  static const String _kTheme = 'setting.theme';
  static const String _kNotifications = 'setting.notifications';
  static const String _kClearHistory = 'app_history';

  bool _loaded = false;
  bool get loaded => _loaded;

  // ---------------------------------------------------------------
  // Voice & Audio
  // ---------------------------------------------------------------

  bool _voiceGuidanceEnabled = true;
  bool _globalVoiceMuted = false;
  bool _repeatInstruction = true;
  double _voiceVolume = 1.0;
  int _announcementCooldownSeconds = 3;
  SpeechRate _speechRate = SpeechRate.normal;
  VoiceLanguage _voiceLanguage = VoiceLanguage.systemDefault;

  bool get voiceGuidanceEnabled => _voiceGuidanceEnabled;
  bool get globalVoiceMuted => _globalVoiceMuted;
  bool get repeatInstruction => _repeatInstruction;
  double get voiceVolume => _voiceVolume;
  int get announcementCooldownSeconds => _announcementCooldownSeconds;
  SpeechRate get speechRate => _speechRate;
  VoiceLanguage get voiceLanguage => _voiceLanguage;

  /// Platform TTS tag for the selected [voiceLanguage].
  String get voiceLanguageTag {
    switch (_voiceLanguage) {
      case VoiceLanguage.systemDefault:
      case VoiceLanguage.usEnglish:
        return 'en-US';
      case VoiceLanguage.ukEnglish:
        return 'en-GB';
    }
  }

  double get speechRateValue {
    switch (_speechRate) {
      case SpeechRate.slow:
        return 0.35;
      case SpeechRate.normal:
        return 0.55;
      case SpeechRate.fast:
        return 0.8;
    }
  }

  // ---------------------------------------------------------------
  // Accessibility
  // ---------------------------------------------------------------

  TextSizeLevel _textSize = TextSizeLevel.standard;
  bool _highContrast = false;
  bool _largeButtons = false;
  bool _hapticFeedback = true;
  bool _voiceFirstMode = true;
  bool _reduceAnimations = false;

  TextSizeLevel get textSize => _textSize;
  bool get highContrast => _highContrast;
  bool get largeButtons => _largeButtons;
  bool get hapticFeedback => _hapticFeedback;
  bool get voiceFirstMode => _voiceFirstMode;
  bool get reduceAnimations => _reduceAnimations;

  // ---------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------

  bool _navigationVoiceEnabled = true;
  ObstacleSensitivity _obstacleSensitivity = ObstacleSensitivity.medium;
  GuidanceMode _guidanceMode = GuidanceMode.balanced;
  bool _closeObstacleWarnings = true;

  bool get navigationVoiceEnabled => _navigationVoiceEnabled;
  ObstacleSensitivity get obstacleSensitivity => _obstacleSensitivity;
  GuidanceMode get guidanceMode => _guidanceMode;
  bool get closeObstacleWarnings => _closeObstacleWarnings;

  // ---------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------

  bool _detectionVoiceEnabled = true;
  bool _peopleAnnouncements = true;
  bool _vehicleAnnouncements = true;
  bool _animalAnnouncements = true;
  bool _furnitureAnnouncements = true;
  bool _obstacleAnnouncements = true;
  DetectionSensitivity _detectionSensitivity = DetectionSensitivity.balanced;

  bool get detectionVoiceEnabled => _detectionVoiceEnabled;
  bool get peopleAnnouncements => _peopleAnnouncements;
  bool get vehicleAnnouncements => _vehicleAnnouncements;
  bool get animalAnnouncements => _animalAnnouncements;
  bool get furnitureAnnouncements => _furnitureAnnouncements;
  bool get obstacleAnnouncements => _obstacleAnnouncements;
  DetectionSensitivity get detectionSensitivity => _detectionSensitivity;

  double get detectionConfidenceThreshold {
    switch (_detectionSensitivity) {
      case DetectionSensitivity.conservative:
        return 0.55;
      case DetectionSensitivity.balanced:
        return 0.40;
      case DetectionSensitivity.sensitive:
        return 0.25;
    }
  }

  // ---------------------------------------------------------------
  // Read Text
  // ---------------------------------------------------------------

  bool _readTextAutoRead = false;
  bool _textPositionGuidance = true;
  SpeechRate _readingSpeed = SpeechRate.normal;
  String _ocrLanguage = 'latin';

  bool get readTextAutoRead => _readTextAutoRead;
  bool get textPositionGuidance => _textPositionGuidance;
  SpeechRate get readingSpeed => _readingSpeed;
  String get ocrLanguage => _ocrLanguage;

  // ---------------------------------------------------------------
  // Familiar Faces
  // ---------------------------------------------------------------

  bool _familiarFacesEnabled = true;
  bool _familiarFaceVoice = true;
  bool _unknownPersonAnnouncements = false;
  FamiliarFaceSensitivity _familiarFaceSensitivity =
      FamiliarFaceSensitivity.conservative;
  int _familiarFaceCooldownSeconds = 3;

  bool get familiarFacesEnabled => _familiarFacesEnabled;
  bool get familiarFaceVoice => _familiarFaceVoice;
  bool get unknownPersonAnnouncements => _unknownPersonAnnouncements;
  FamiliarFaceSensitivity get familiarFaceSensitivity =>
      _familiarFaceSensitivity;
  int get familiarFaceCooldownSeconds => _familiarFaceCooldownSeconds;

  // ---------------------------------------------------------------
  // Emergency
  // ---------------------------------------------------------------

  int _sosHoldDurationSeconds = 5;
  bool _sosConfirmation = true;

  int get sosHoldDurationSeconds => _sosHoldDurationSeconds;
  bool get sosConfirmation => _sosConfirmation;

  // ---------------------------------------------------------------
  // General
  // ---------------------------------------------------------------

  AppThemePreference _theme = AppThemePreference.system;
  bool _notificationsEnabled = true;
  String _appLanguage = 'en';

  AppThemePreference get theme => _theme;
  bool get notificationsEnabled => _notificationsEnabled;
  String get appLanguage => _appLanguage;

  // ---------------------------------------------------------------
  // Load / Persist
  // ---------------------------------------------------------------

  /// Loads all settings from disk. Safe to call multiple times.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _voiceGuidanceEnabled = prefs.getBool(_kVoiceGuidance) ?? true;
    _globalVoiceMuted = prefs.getBool(_kGlobalVoiceMuted) ?? false;
    _repeatInstruction = prefs.getBool(_kRepeatInstruction) ?? true;
    _voiceVolume = prefs.getDouble(_kVoiceVolume) ?? 1.0;
    _announcementCooldownSeconds = prefs.getInt(_kAnnouncementCooldown) ?? 3;
    _speechRate = _enumFromName(SpeechRate.values, prefs.getString(_kSpeechRate)) ??
        SpeechRate.normal;
    _voiceLanguage =
        _enumFromName(VoiceLanguage.values, prefs.getString(_kVoiceLanguage)) ??
            VoiceLanguage.systemDefault;
    _textSize = _enumFromName(TextSizeLevel.values, prefs.getString(_kLargeText)) ??
        TextSizeLevel.standard;
    _highContrast = prefs.getBool(_kHighContrast) ?? false;
    _largeButtons = prefs.getBool(_kLargeButtons) ?? false;
    _hapticFeedback = prefs.getBool(_kHapticFeedback) ?? true;
    _voiceFirstMode = prefs.getBool(_kVoiceFirstMode) ?? true;
    _reduceAnimations = prefs.getBool(_kReduceAnimations) ?? false;
    _navigationVoiceEnabled = prefs.getBool(_kNavVoice) ?? true;
    _obstacleSensitivity =
        _enumFromName(ObstacleSensitivity.values, prefs.getString(_kObstacleSensitivity)) ??
            ObstacleSensitivity.medium;
    _guidanceMode =
        _enumFromName(GuidanceMode.values, prefs.getString(_kGuidanceMode)) ??
            GuidanceMode.balanced;
    _closeObstacleWarnings = prefs.getBool(_kCloseObstacleWarnings) ?? true;
    _detectionVoiceEnabled = prefs.getBool(_kDetectionVoice) ?? true;
    _peopleAnnouncements = prefs.getBool(_kPeopleAnns) ?? true;
    _vehicleAnnouncements = prefs.getBool(_kVehicleAnns) ?? true;
    _animalAnnouncements = prefs.getBool(_kAnimalAnns) ?? true;
    _furnitureAnnouncements = prefs.getBool(_kFurnitureAnns) ?? true;
    _obstacleAnnouncements = prefs.getBool(_kObstacleAnns) ?? true;
    _detectionSensitivity =
        _enumFromName(DetectionSensitivity.values, prefs.getString(_kDetectionSensitivity)) ??
            DetectionSensitivity.balanced;
    _readTextAutoRead = prefs.getBool(_kReadAutoRead) ?? false;
    _textPositionGuidance = prefs.getBool(_kTextPosGuidance) ?? true;
    _readingSpeed =
        _enumFromName(SpeechRate.values, prefs.getString(_kReadingSpeed)) ??
            SpeechRate.normal;
    _ocrLanguage = prefs.getString(_kOcrLanguage) ?? 'latin';
    _familiarFacesEnabled = prefs.getBool(_kFacesEnabled) ?? true;
    _familiarFaceVoice = prefs.getBool(_kFaceVoice) ?? true;
    _unknownPersonAnnouncements = prefs.getBool(_kUnknownAnns) ?? false;
    _familiarFaceSensitivity =
        _enumFromName(FamiliarFaceSensitivity.values, prefs.getString(_kFaceSensitivity)) ??
            FamiliarFaceSensitivity.conservative;
    _familiarFaceCooldownSeconds = prefs.getInt(_kFaceCooldown) ?? 3;
    _sosHoldDurationSeconds = prefs.getInt(_kSosHoldDuration) ?? 5;
    _sosConfirmation = prefs.getBool(_kSosConfirmation) ?? true;
    _appLanguage = prefs.getString(_kAppLanguage) ?? 'en';
    _theme = _enumFromName(AppThemePreference.values, prefs.getString(_kTheme)) ??
        AppThemePreference.system;
    _notificationsEnabled = prefs.getBool(_kNotifications) ?? true;
    _loaded = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------
  // Setters (persist on write)
  // ---------------------------------------------------------------

  Future<void> setVoiceGuidanceEnabled(bool v) =>
      _write(_kVoiceGuidance, () => _voiceGuidanceEnabled = v, prefsBool: v);

  Future<void> setGlobalVoiceMuted(bool v) =>
      _write(_kGlobalVoiceMuted, () => _globalVoiceMuted = v, prefsBool: v);

  Future<void> setRepeatInstruction(bool v) =>
      _write(_kRepeatInstruction, () => _repeatInstruction = v, prefsBool: v);

  Future<void> setVoiceVolume(double v) =>
      _write(_kVoiceVolume, () => _voiceVolume = v, prefsDouble: v);

  Future<void> setAnnouncementCooldown(int seconds) => _write(
        _kAnnouncementCooldown,
        () => _announcementCooldownSeconds = seconds,
        prefsInt: seconds,
      );

  Future<void> setSpeechRate(SpeechRate v) =>
      _write(_kSpeechRate, () => _speechRate = v, prefsString: v.name);

  Future<void> setVoiceLanguage(VoiceLanguage v) =>
      _write(_kVoiceLanguage, () => _voiceLanguage = v, prefsString: v.name);

  Future<void> setTextSize(TextSizeLevel v) =>
      _write(_kLargeText, () => _textSize = v, prefsString: v.name);

  Future<void> setHighContrast(bool v) =>
      _write(_kHighContrast, () => _highContrast = v, prefsBool: v);

  Future<void> setLargeButtons(bool v) =>
      _write(_kLargeButtons, () => _largeButtons = v, prefsBool: v);

  Future<void> setHapticFeedback(bool v) =>
      _write(_kHapticFeedback, () => _hapticFeedback = v, prefsBool: v);

  Future<void> setVoiceFirstMode(bool v) =>
      _write(_kVoiceFirstMode, () => _voiceFirstMode = v, prefsBool: v);

  Future<void> setReduceAnimations(bool v) =>
      _write(_kReduceAnimations, () => _reduceAnimations = v, prefsBool: v);

  Future<void> setNavigationVoiceEnabled(bool v) =>
      _write(_kNavVoice, () => _navigationVoiceEnabled = v, prefsBool: v);

  Future<void> setObstacleSensitivity(ObstacleSensitivity v) => _write(
        _kObstacleSensitivity,
        () => _obstacleSensitivity = v,
        prefsString: v.name,
      );

  Future<void> setGuidanceMode(GuidanceMode v) =>
      _write(_kGuidanceMode, () => _guidanceMode = v, prefsString: v.name);

  Future<void> setCloseObstacleWarnings(bool v) =>
      _write(_kCloseObstacleWarnings, () => _closeObstacleWarnings = v, prefsBool: v);

  Future<void> setDetectionVoiceEnabled(bool v) =>
      _write(_kDetectionVoice, () => _detectionVoiceEnabled = v, prefsBool: v);

  Future<void> setPeopleAnnouncements(bool v) =>
      _write(_kPeopleAnns, () => _peopleAnnouncements = v, prefsBool: v);

  Future<void> setVehicleAnnouncements(bool v) =>
      _write(_kVehicleAnns, () => _vehicleAnnouncements = v, prefsBool: v);

  Future<void> setAnimalAnnouncements(bool v) =>
      _write(_kAnimalAnns, () => _animalAnnouncements = v, prefsBool: v);

  Future<void> setFurnitureAnnouncements(bool v) =>
      _write(_kFurnitureAnns, () => _furnitureAnnouncements = v, prefsBool: v);

  Future<void> setObstacleAnnouncements(bool v) =>
      _write(_kObstacleAnns, () => _obstacleAnnouncements = v, prefsBool: v);

  Future<void> setDetectionSensitivity(DetectionSensitivity v) => _write(
        _kDetectionSensitivity,
        () => _detectionSensitivity = v,
        prefsString: v.name,
      );

  Future<void> setReadTextAutoRead(bool v) =>
      _write(_kReadAutoRead, () => _readTextAutoRead = v, prefsBool: v);

  Future<void> setTextPositionGuidance(bool v) =>
      _write(_kTextPosGuidance, () => _textPositionGuidance = v, prefsBool: v);

  Future<void> setReadingSpeed(SpeechRate v) =>
      _write(_kReadingSpeed, () => _readingSpeed = v, prefsString: v.name);

  Future<void> setOcrLanguage(String v) =>
      _write(_kOcrLanguage, () => _ocrLanguage = v, prefsString: v);

  Future<void> setFamiliarFacesEnabled(bool v) =>
      _write(_kFacesEnabled, () => _familiarFacesEnabled = v, prefsBool: v);

  Future<void> setFamiliarFaceVoice(bool v) =>
      _write(_kFaceVoice, () => _familiarFaceVoice = v, prefsBool: v);

  Future<void> setUnknownPersonAnnouncements(bool v) =>
      _write(_kUnknownAnns, () => _unknownPersonAnnouncements = v, prefsBool: v);

  Future<void> setFamiliarFaceSensitivity(FamiliarFaceSensitivity v) => _write(
        _kFaceSensitivity,
        () => _familiarFaceSensitivity = v,
        prefsString: v.name,
      );

  Future<void> setFamiliarFaceCooldown(int seconds) =>
      _write(_kFaceCooldown, () => _familiarFaceCooldownSeconds = seconds, prefsInt: seconds);

  Future<void> setSosHoldDuration(int seconds) =>
      _write(_kSosHoldDuration, () => _sosHoldDurationSeconds = seconds, prefsInt: seconds);

  Future<void> setSosConfirmation(bool v) =>
      _write(_kSosConfirmation, () => _sosConfirmation = v, prefsBool: v);

  Future<void> setAppLanguage(String v) =>
      _write(_kAppLanguage, () => _appLanguage = v, prefsString: v);

  Future<void> setTheme(AppThemePreference v) =>
      _write(_kTheme, () => _theme = v, prefsString: v.name);

  Future<void> setNotificationsEnabled(bool v) =>
      _write(_kNotifications, () => _notificationsEnabled = v, prefsBool: v);

  /// Clears the (currently empty) guidance history store. Does not touch
  /// familiar faces, emergency contacts, or settings.
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kClearHistory);
    notifyListeners();
  }

  /// Resets preferences to defaults. Intentionally does NOT delete familiar
  /// faces, emergency contacts, or any other user data.
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('setting.'));
    for (final key in keys) {
      await prefs.remove(key);
    }
    await load();
  }

  // ---------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------

  Future<void> _write(
    String key,
    void Function() apply, {
    bool? prefsBool,
    double? prefsDouble,
    int? prefsInt,
    String? prefsString,
  }) async {
    apply();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (prefsBool != null) {
      await prefs.setBool(key, prefsBool);
    } else if (prefsDouble != null) {
      await prefs.setDouble(key, prefsDouble);
    } else if (prefsInt != null) {
      await prefs.setInt(key, prefsInt);
    } else if (prefsString != null) {
      await prefs.setString(key, prefsString);
    }
  }

  static T? _enumFromName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}