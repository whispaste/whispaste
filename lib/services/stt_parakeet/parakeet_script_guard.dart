/// Parakeet keeps to the user's languages by their script (#2168).
///
/// Parakeet TDT v3 detects the language itself and takes no language from
/// the request, so a Polish dictation could come back in Cyrillic (heard as
/// Russian or Ukrainian) although the user chose Polish. The model cannot be
/// told which languages to use, but the result can be checked: when the
/// languages the user dictates in (the fixed language, or the languages
/// automatic detection may choose from, [SttSettings.autoDetectLanguages])
/// all write in scripts other than the one the text is written in, the text
/// is in a language the user does not speak. Whisper follows the language
/// setting, so when its model is on disk the same recording goes to Whisper.
/// Without it the Parakeet text stays and a notice offers the switch.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../transcription/transcriber_interface.dart';

final _log = AppLogger('ParakeetScriptGuard');

/// The scripts the check tells apart. They cover every language Parakeet
/// writes: Latin, Cyrillic (Bulgarian, Russian, Ukrainian) and Greek.
enum WritingScript { latin, cyrillic, greek }

const _cyrillicLanguages = {
  'ru', 'uk', 'bg', 'be', 'mk', 'kk', 'mn', 'tg', 'ba', 'tt', //
};

const _latinLanguages = {
  'af', 'br', 'bs', 'ca', 'cs', 'cy', 'da', 'de', 'en', 'es', 'et', 'eu', //
  'fi', 'fo', 'fr', 'gl', 'hr', 'ht', 'hu', 'id', 'is', 'it', 'jw', 'la', //
  'lb', 'ln', 'lt', 'lv', 'mg', 'mi', 'ms', 'mt', 'nl', 'nn', 'no', 'oc', //
  'pl', 'pt', 'ro', 'sk', 'sl', 'sn', 'so', 'sq', 'su', 'sv', 'sw', 'tk', //
  'tl', 'tr', 'uz', 'vi', 'yo', 'haw', //
};

/// The script [languageCode] (a whisper code) is written in, or `null` when
/// the language is unknown here or commonly written in more than one script
/// (Serbian, Azerbaijani). `null` switches the check off.
WritingScript? scriptOfLanguage(String languageCode) {
  if (_latinLanguages.contains(languageCode)) return WritingScript.latin;
  if (_cyrillicLanguages.contains(languageCode)) return WritingScript.cyrillic;
  if (languageCode == 'el') return WritingScript.greek;
  return null;
}

WritingScript? _scriptOfRune(int r) {
  if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
    return WritingScript.latin;
  }
  if (r >= 0xC0 && r <= 0x24F && r != 0xD7 && r != 0xF7) {
    return WritingScript.latin;
  }
  if (r >= 0x1E00 && r <= 0x1EFF) return WritingScript.latin;
  if (r >= 0x400 && r <= 0x52F) return WritingScript.cyrillic;
  if ((r >= 0x370 && r <= 0x3FF) || (r >= 0x1F00 && r <= 0x1FFF)) {
    return WritingScript.greek;
  }
  return null;
}

/// The script most letters of [text] are written in, or `null` for text with
/// fewer than two such letters or without a majority.
WritingScript? dominantScript(String text) {
  final counts = <WritingScript, int>{};
  var total = 0;
  for (final r in text.runes) {
    final script = _scriptOfRune(r);
    if (script == null) continue;
    counts[script] = (counts[script] ?? 0) + 1;
    total++;
  }
  if (total < 2) return null;
  for (final entry in counts.entries) {
    if (entry.value * 2 > total) return entry.key;
  }
  return null;
}

/// Whether [text] is written in a script none of [languages] uses. False
/// when there is nothing to compare against: no languages, a language with
/// no single script, or text without a clear script.
bool isForeignScript(String text, List<String> languages) {
  if (languages.isEmpty) return false;
  final allowed = <WritingScript>{};
  for (final code in languages) {
    final script = scriptOfLanguage(code);
    if (script == null) return false;
    allowed.add(script);
  }
  final dominant = dominantScript(text);
  return dominant != null && !allowed.contains(dominant);
}

/// The languages a recording may be written in: the request's fixed
/// [language], or with automatic detection [autoDetectLanguages] (empty =
/// every language, then nothing is checked).
List<String> languagesForRequest(
  String? language,
  List<String> autoDetectLanguages,
) {
  if (language == null || language.isEmpty || language == 'auto') {
    return autoDetectLanguages;
  }
  return [language];
}

/// What happened to a recording Parakeet wrote in a foreign script.
class ParakeetScriptNotice {
  const ParakeetScriptNotice({
    required this.languages,
    required this.handledByWhisper,
  });

  /// The languages the user dictates in, as whisper codes.
  final List<String> languages;

  /// True when Whisper transcribed the recording again; false when the
  /// Parakeet text stayed because no Whisper model is installed.
  final bool handledByWhisper;
}

class ParakeetScriptNoticeNotifier extends Notifier<ParakeetScriptNotice?> {
  @override
  ParakeetScriptNotice? build() => null;

  bool _toldWhisperTookOver = false;

  /// Publishes [notice]. That Whisper took over is said once per session,
  /// calmly; the offer to switch comes every time, because the text is in
  /// the wrong language each time.
  void show(ParakeetScriptNotice notice) {
    if (notice.handledByWhisper) {
      if (_toldWhisperTookOver) return;
      _toldWhisperTookOver = true;
    }
    state = notice;
  }

  void clear() => state = null;
}

final parakeetScriptNoticeProvider =
    NotifierProvider<ParakeetScriptNoticeNotifier, ParakeetScriptNotice?>(
      ParakeetScriptNoticeNotifier.new,
    );

/// Parakeet with the script check: a result in a script none of the user's
/// languages uses goes to [whisper] when [whisperInstalled], else stays.
class ParakeetScriptGuardedTranscriber
    implements Transcriber, WavFileTranscriber, ModelReportingTranscriber {
  ParakeetScriptGuardedTranscriber({
    required this.inner,
    required this.languagesFor,
    required this.whisperInstalled,
    required this.whisper,
    required this.whisperModelId,
    required this.onNotice,
  });

  /// The Parakeet adapter.
  final Transcriber inner;

  /// The languages a request with this language may be written in.
  final List<String> Function(String? language) languagesFor;

  /// Whether the Whisper model is on disk, read when a result is foreign.
  final bool Function() whisperInstalled;

  /// The Whisper adapter, built only when a recording needs it.
  final Transcriber Function() whisper;

  /// Model identity of [whisper], so history names the engine that wrote.
  final String Function() whisperModelId;

  final void Function(ParakeetScriptNotice notice) onNotice;

  Transcriber? _whisper;

  /// `null` while Parakeet wrote the text: the settings' identity applies.
  @override
  String? lastUsedModelId;

  @override
  Future<void> prepare() => inner.prepare();

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) =>
      _run((t) => t.transcribe(wavBytes, language: language), language);

  @override
  Future<String> transcribeWavFile(
    String wavPath,
    List<int> wavBytes, {
    String? language,
  }) => _run(
    (t) => t is WavFileTranscriber
        ? (t as WavFileTranscriber).transcribeWavFile(
            wavPath,
            wavBytes,
            language: language,
          )
        : t.transcribe(wavBytes, language: language),
    language,
  );

  Future<String> _run(
    Future<String> Function(Transcriber t) call,
    String? language,
  ) async {
    lastUsedModelId = null;
    final text = await call(inner);
    final languages = languagesFor(language);
    if (!isForeignScript(text, languages)) return text;
    if (!whisperInstalled()) {
      _log.info('Parakeet wrote a foreign script; no Whisper model to retry');
      onNotice(
        ParakeetScriptNotice(languages: languages, handledByWhisper: false),
      );
      return text;
    }
    _log.info('Parakeet wrote a foreign script; Whisper takes the recording');
    try {
      final w = _whisper ??= whisper();
      await w.prepare();
      final retried = await call(w);
      lastUsedModelId = whisperModelId();
      onNotice(
        ParakeetScriptNotice(languages: languages, handledByWhisper: true),
      );
      return retried;
    } on TranscriberException catch (e) {
      if (e.reason == TranscriberFailureReason.cancelled) rethrow;
      // The dictation is not lost: the Parakeet text stays, and the offer
      // to switch explains why it may read wrong.
      _log.warning('Whisper retry failed (${e.reason.name}); Parakeet text');
      onNotice(
        ParakeetScriptNotice(languages: languages, handledByWhisper: false),
      );
      return text;
    }
  }

  @override
  void release() {
    inner.release();
    _whisper?.release();
  }
}
