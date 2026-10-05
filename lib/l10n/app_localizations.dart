import 'dart:ui' show Locale;

/// Resolves the persisted "App Language" preference to a real [Locale].
///
/// This is the localization architecture, kept deliberately small and honest:
///
/// * The list of languages the app actually ships translations for is declared
///   here as [supportedLanguages]. English is the only entry today because it is
///   the only language whose strings exist.
/// * A preference that is not in that list resolves to [fallbackLocale] instead
///   of being honoured, so a stale or hand-edited value can never leave the app
///   rendering untranslated strings.
/// * Strings themselves are *not* machine translated. Emergency and SOS wording
///   in particular must be written and reviewed by a human, so adding a language
///   means adding reviewed strings here — not calling a translation API.
///
/// To add a language: add its tag to [supportedLanguages], add reviewed strings
/// to [AppStrings] for that tag, and it becomes selectable automatically. No
/// other file needs to change, because every consumer resolves its locale
/// through [localeFor].
class AppLocalizations {
  AppLocalizations._();

  /// Language tags the app has translations for.
  ///
  /// English is the fallback and the only entry today.
  static const List<String> supportedLanguages = <String>['en'];

  /// Used when the device locale is not supported.
  static const Locale fallbackLocale = Locale('en');

  /// Resolves a stored preference tag to a supported [Locale].
  ///
  /// Unknown or empty values resolve to [fallbackLocale] rather than throwing,
  /// so a corrupted preference degrades to a working English UI.
  static Locale localeFor(String? languageTag) {
    if (languageTag != null && supportedLanguages.contains(languageTag)) {
      return Locale(languageTag);
    }
    return fallbackLocale;
  }

  /// Picks the best supported locale for a device locale list.
  ///
  /// Falls back to [fallbackLocale] so the UI always has a locale and never
  /// depends on a partially-supported match.
  static Locale resolve(List<Locale>? deviceLocales) {
    for (final Locale locale in deviceLocales ?? const <Locale>[]) {
      if (supportedLanguages.contains(locale.languageCode)) {
        return Locale(locale.languageCode);
      }
    }
    return fallbackLocale;
  }
}

/// Reviewed user-facing strings, keyed by language tag.
///
/// Only entries present in [AppLocalizations.supportedLanguages] are ever used.
/// This is intentionally a plain map rather than generated ARB tooling: the app
/// has exactly one locale, and a generated localization pipeline would be
/// infrastructure with no second locale to serve.
class AppStrings {
  AppStrings._();

  static const Map<String, Map<String, String>> _strings =
      <String, Map<String, String>>{
    'en': <String, String>{
      'app_title': 'VisionPath AI',
      'settings_title': 'Settings',
      // Emergency wording. These are deliberately explicit and are never
      // machine translated: an unclear emergency phrase is a safety problem.
      'sos_title': 'Emergency SOS',
      'sos_hold_prompt': 'Press and hold to activate.',
      'sos_activated': 'SOS Activated',
      'sos_reset': 'Reset SOS',
    },
  };

  /// The string table for [tag], falling back to English.
  static Map<String, String> of(String? tag) {
    return _strings[tag] ?? _strings['en']!;
  }

  /// Looks up a reviewed string by key.
  static String text(String? tag, String key) {
    return of(tag)[key] ?? of('en')[key] ?? key;
  }
}