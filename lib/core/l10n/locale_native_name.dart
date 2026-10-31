import 'package:flutter/widgets.dart';

/// Maps a [Locale] to its native (endonym) language name — the language
/// written in its own script.
///
/// Used by the onboarding language selector and any other UI that needs to
/// label a locale in a way every speaker recognises, regardless of the
/// currently active UI language.
///
/// New entries are required whenever a locale is added to
/// `L10n.supportedLocales`.  Unknown locales fall back to the language
/// subtag in upper-case so the UI never crashes — but the fallback is a
/// last-resort and should not ship to end users.
String localeNativeName(Locale locale) {
  // Match on the lower-cased language code; ignore script/region —
  // WhisPaste ships one variant per language. Portuguese is the Brazilian
  // variant, so its name says so.
  final code = locale.languageCode.toLowerCase();
  return switch (code) {
    'de' => 'Deutsch',
    'en' => 'English',
    'he' => 'עברית',
    'fr' => 'Français',
    'es' => 'Español',
    'pt' => 'Português (Brasil)',
    'ru' => 'Русский',
    _ => code.toUpperCase(),
  };
}
