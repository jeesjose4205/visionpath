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