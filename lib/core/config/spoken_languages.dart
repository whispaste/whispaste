/// "Sprachen" (#2045): one choice for what used to be two rows, the fixed
/// recognition language and the expected languages (#1510).
///
/// The user picks the languages they speak. Nothing stored changes shape:
/// one language is the fixed `stt.language`, several are
/// `stt.expectedLanguages` with automatic detection, none is automatic
/// detection over all languages. Existing settings read back unchanged
/// (a fixed language always had precedence, so it alone is the selection).
library;

import '../l10n/generated/app_localizations.dart';
import 'settings_enums.dart';
import 'settings_provider.dart';

/// The languages the user speaks, as the settings store them.
List<String> spokenLanguagesOf(AppSettings settings) {
  final fixed = settings.sttLanguageCode;
  if (fixed != 'auto') return [fixed];
  return settings.stt.expectedLanguages;
}

/// The languages recognition actually works with, for the row's summary:
/// the spoken languages, or without them the favorites that restrict
/// automatic detection (#2015, [SttSettings.autoDetectLanguages]).
List<String> effectiveSpokenLanguagesOf(AppSettings settings) {
  final spoken = spokenLanguagesOf(settings);
  return spoken.isNotEmpty ? spoken : settings.stt.autoDetectLanguages;
}

/// [settings] with [codes] as the spoken languages: one is the fixed
/// language, several restrict automatic detection, none detects freely.
AppSettings withSpokenLanguages(AppSettings settings, List<String> codes) {
  final unique = codes.toSet().toList();
  final single = unique.length == 1;
  return settings.copyWithSections(
    stt: settings.stt.copyWith(
      language: single ? unique.single : 'auto',
      expectedLanguages: single ? const [] : unique,
    ),
  );
}

/// Whether the engine in use decides the language itself, so a selection
/// has no effect: Parakeet, Apple's engine and own endpoints. Whisper and
/// Deepgram follow it, OpenAI takes it as a hint.
bool spokenLanguagesIgnored(AppSettings settings) {
  final provider = settings.sttProviderType;
  if (provider == SttProviderType.customEndpoint) return true;
  if (!provider.isLocal) return false;
  return settings.onDeviceEngine == OnDeviceEngine.parakeet ||
      settings.onDeviceEngine == OnDeviceEngine.system;
}

/// The row's summary: "Automatisch", one name, or the names with
/// "(automatisch)" when the app tells them apart itself.
String spokenLanguagesSummary(
  L10n l10n,
  List<String> codes,
  String Function(String code) nameOf,
) => switch (codes) {
  [] => l10n.settingsLanguageAutoDetect,
  [final code] => nameOf(code),
  _ => l10n.settingsSpokenLanguagesAuto(codes.map(nameOf).join(', ')),
};
