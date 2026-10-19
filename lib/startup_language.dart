import 'dart:ui' show Locale;

import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';

/// SharedPreferences keys owned by app startup / first-run gating.
const String kAppLanguagePrefsKey = 'appLanguage';
const String kOnboardingCompletePrefsKey = 'onboardingComplete';

/// Resolves the language used on this launch.
///
/// A valid saved preference always wins. Only a fresh install (or a corrupt
/// preference) falls back to the device locale. Unsupported device languages
/// intentionally map to English.
AppLang startupLanguageFrom({String? savedLanguage, Locale? deviceLocale}) {
  if (savedLanguage != null) {
    for (final lang in AppLang.values) {
      if (lang.name == savedLanguage) return lang;
    }
  }
  return S.langFromLocale(deviceLocale ?? const Locale('en'));
}

/// Applies [startupLanguageFrom] and persists only when there was no valid
/// preference yet (or the stored value was corrupt).
Future<AppLang> loadStartupLanguage({
  SharedPreferences? prefs,
  Locale? deviceLocale,
}) async {
  final saved = prefs?.getString(kAppLanguagePrefsKey);
  final lang = startupLanguageFrom(
    savedLanguage: saved,
    deviceLocale: deviceLocale,
  );
  S.setLang(lang);
  if (prefs != null && saved != lang.name) {
    try {
      await prefs.setString(kAppLanguagePrefsKey, lang.name);
    } catch (_) {
      // A write failure must not block startup; the in-memory selection is
      // still correct for this session and will be retried next launch.
    }
  }
  return lang;
}

/// Existing installs that already completed onboarding are never sent back
/// through the wizard after an update.
bool shouldShowOnboarding(SharedPreferences? prefs) {
  return !(prefs?.getBool(kOnboardingCompletePrefsKey) ?? false);
}
