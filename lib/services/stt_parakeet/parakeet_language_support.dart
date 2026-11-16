/// Parakeet language gap (SW-05).
///
/// Parakeet TDT v3 transcribes only [parakeetSupportedLanguages]. Its adapter
/// drops the requested language without a word, so a user who dictates Arabic
/// with Parakeet active gets nonsense and no explanation. These helpers name
/// the gap so the Settings banner, the recording-start toast and the
/// Automation API can say what happens and offer the switch to Whisper.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import 'parakeet_model_registry.dart' show parakeetSupportedLanguages;

/// The language code Parakeet cannot transcribe under [settings], or `null`
/// when that is not a problem: Parakeet is not the active engine, the language
/// is automatic, or the language is supported.
///
/// [languageOverride] (Automation API `language`) wins over the configured
/// language, as it does at transcription time.
String? parakeetUnsupportedLanguage(
  AppSettings settings, {
  String? languageOverride,
}) {
  if (!settings.sttProviderType.isLocal ||
      settings.onDeviceEngine != OnDeviceEngine.parakeet) {
    return null;
  }
  final code = languageOverride ?? settings.sttLanguageCode;
  if (code.isEmpty ||
      code == 'auto' ||
      parakeetSupportedLanguages.contains(code)) {
    return null;
  }
  return code;
}

/// One notice per recording start. A new instance every time, so a repeated
/// notice fires again after the previous one was cleared.
class ParakeetLanguageNotice {
  const ParakeetLanguageNotice(this.languageCode);

  final String languageCode;
}

class ParakeetLanguageNoticeNotifier extends Notifier<ParakeetLanguageNotice?> {
  @override
  ParakeetLanguageNotice? build() => null;

  void show(ParakeetLanguageNotice notice) => state = notice;

  void clear() => state = null;
}

final parakeetLanguageNoticeProvider =
    NotifierProvider<ParakeetLanguageNoticeNotifier, ParakeetLanguageNotice?>(
      ParakeetLanguageNoticeNotifier.new,
    );
