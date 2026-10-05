/// Enum-based setting values used by SettingsService.
library;

enum SpeechRate { slow, normal, fast }

enum VoiceLanguage { systemDefault, usEnglish, ukEnglish }

enum TextSizeLevel { standard, large, extraLarge }

enum ObstacleSensitivity { low, medium, high }

enum DetectionSensitivity { conservative, balanced, sensitive }

enum FamiliarFaceSensitivity { conservative, balanced, sensitive }

enum GuidanceMode { balanced, moreFrequent, minimal }

/// Top-bar sound switch: voice alerts, vibration-based alerts, or silent.
enum AlertMode { sound, muted }

enum AppThemePreference { system, light, dark }

/// The alert tone that repeats while SOS is active.
///
/// Persisted by [name], so these names are a storage format: renaming one
/// silently resets every existing user's choice. The wire value doubles as the
/// key the Android side looks up.
enum SosAlertTone {
  beep1('Beep 1', 'A short single pip, repeating.'),
  beep2('Beep 2', 'A higher, sharper beep.'),
  beep3('Beep 3', 'A mid, steadier beep.'),
  emergency('Emergency Tone', 'The urgent two-tone alert. Recommended.'),
  siren('Siren', 'The longest, most attention-grabbing tone.');

  const SosAlertTone(this.label, this.description);

  /// Name shown in Settings.
  final String label;

  /// One-line explanation, so the choice is audible-friendly.
  final String description;

  /// Readable back from storage, falling back to the safest loud option.
  static SosAlertTone fromName(String? name) {
    return SosAlertTone.values.firstWhere(
      (SosAlertTone tone) => tone.name == name,
      orElse: () => SosAlertTone.emergency,
    );
  }
}