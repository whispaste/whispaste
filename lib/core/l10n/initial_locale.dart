import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/whisper_languages.dart';
import '../logging/app_logger.dart';
import 'generated/app_localizations.dart';

final _log = AppLogger('InitialLocale');

/// The operating system's language preference list, in order, as Flutter
/// reports it. Read once by the settings on a first start, when no `locale`
/// has been stored yet. Tests override it instead of touching the platform.
final systemLocalesProvider = Provider<List<Locale>>(
  (ref) => PlatformDispatcher.instance.locales,
);

/// Native channel `whispaste/system_languages` (all three runners): the
/// platform's own preferred language list, used when Flutter reports no named
/// language (for example a `C`/`POSIX` process locale).
const _systemLanguagesChannel = MethodChannel('whispaste/system_languages');

/// Asked only on a first start whose Flutter locale list names no language.
/// A missing or slow channel yields an empty list, so the rule falls back.
final systemPreferredLanguagesProvider = FutureProvider<List<String>>((
  ref,
) async {
  try {
    final tags = await _systemLanguagesChannel
        .invokeListMethod<String>('preferredLanguages')
        .timeout(const Duration(seconds: 2));
    return tags ?? const [];
  } on Object catch (e) {
    _log.debug('Native system languages unavailable: $e');
    return const [];
  }
});

/// Where the first-start languages came from. Logged by name, never with the
/// system's own language list.
enum FirstStartSource { flutterLocales, systemPreferences, fallback }

/// Languages a first start sets: the app language and the dictation language.
typedef FirstStartLanguages = ({
  String appLocale,
  String dictationLanguage,
  FirstStartSource source,
});

/// The language tags in [raw] that name a language. Drops the empty entry,
/// the `C`/`POSIX` process locales and `und` (undetermined), and strips the
/// encoding and modifier (`de_DE.UTF-8` becomes `de_DE`, `sr@latin` `sr`).
List<String> namedLanguageTags(Iterable<String> raw) {
  final named = <String>[];
  for (final tag in raw) {
    final base = tag.trim().split('.').first.split('@').first;
    final primary = base.split(RegExp('[_-]')).first.toLowerCase();
    if (!RegExp(r'^[a-z]{2,3}$').hasMatch(primary)) continue;
    if (primary == 'und') continue;
    named.add(base);
  }
  return named;
}

/// Language code for a first start: the first named system language that
/// WhisPaste ships a translation for, otherwise English.
///
/// Chinese ships in Simplified script only (`app_zh.arb`, #1951). A system set
/// to Traditional Chinese (script `Hant`, or Taiwan, Hong Kong or Macao
/// without a script) is not taken over; the next system language decides.
String initialLocaleCode(Iterable<String> systemLanguages) {
  final supported = L10n.supportedLocales.map((l) => l.languageCode).toSet();
  for (final tag in namedLanguageTags(systemLanguages)) {
    final code = tag.split(RegExp('[_-]')).first.toLowerCase();
    if (code == 'zh' && isTraditionalChineseTag(tag)) continue;
    if (supported.contains(code)) return code;
  }
  return 'en';
}

/// Whether the Chinese language [tag] asks for Traditional script: an explicit
/// `Hant` script, or a Traditional region (TW, HK, MO) without `Hans`.
bool isTraditionalChineseTag(String tag) {
  final parts = tag.split(RegExp('[_-]')).map((p) => p.toLowerCase()).toList();
  if (parts.contains('hant')) return true;
  if (parts.contains('hans')) return false;
  return parts.any((p) => p == 'tw' || p == 'hk' || p == 'mo');
}

/// The app and dictation language of a first start.
///
/// The source is the first one that names a language: the Flutter locale
/// list, then the platform's preferred languages. If neither does, both are
/// English, which is the same fallback the app language always had. The
/// dictation language is the first system language Whisper writes. If the
/// system names languages but none of them is one Whisper writes, it stays
/// automatic detection.
FirstStartLanguages firstStartLanguages({
  required Iterable<String> flutterLocales,
  required Iterable<String> systemPreferences,
}) {
  final fromFlutter = namedLanguageTags(flutterLocales);
  final fromSystem = namedLanguageTags(systemPreferences);
  final List<String> languages;
  final FirstStartSource source;
  if (fromFlutter.isNotEmpty) {
    languages = fromFlutter;
    source = FirstStartSource.flutterLocales;
  } else if (fromSystem.isNotEmpty) {
    languages = fromSystem;
    source = FirstStartSource.systemPreferences;
  } else {
    return (
      appLocale: 'en',
      dictationLanguage: 'en',
      source: FirstStartSource.fallback,
    );
  }
  return (
    appLocale: initialLocaleCode(languages),
    dictationLanguage: suggestedDictationLanguage(languages) ?? 'auto',
    source: source,
  );
}
