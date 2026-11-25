/// Spell check through the operating system's own checker (#670).
///
/// macOS asks `NSSpellChecker`, Windows the Spell Checking API, Linux
/// Enchant (Hunspell dictionaries). All three answer the same channel
/// `whispaste/spell_check`; the dictionaries, and so the languages on offer,
/// are the system's. Without a checker (Linux without Enchant) the language
/// list is empty and the app says so in the settings.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/replacements/replacements_page.dart';
import '../config/settings_provider.dart';
import '../l10n/locale_provider.dart';
import '../logging/app_logger.dart';
import 'spell_words.dart';

/// Setting value for "follow the dictation language, else the app language".
final _log = AppLogger('SpellCheck');

const spellCheckLanguageAuto = 'auto';

/// [raw] in hyphen form with a lower-case language and an upper-case region:
/// `de_DE`, `de-de` and `de-DE` all become `de-DE`.
String normalizeSpellTag(String raw) {
  final parts = raw.trim().split(RegExp('[_-]'));
  if (parts.isEmpty || parts.first.isEmpty) return '';
  final out = [parts.first.toLowerCase()];
  for (final p in parts.skip(1)) {
    if (p.isEmpty) continue;
    out.add(
      p.length == 2
          ? p.toUpperCase()
          : p.length == 4
          ? '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}'
          : p,
    );
  }
  return out.join('-');
}

String _primary(String tag) => normalizeSpellTag(tag).split('-').first;

/// The tag from [available] (raw, as the system reported it) to check with.
///
/// [setting] is [spellCheckLanguageAuto] or a tag from [available]. Auto
/// picks the dictation language when one is fixed ([dictationLanguage] is a
/// short code or `auto`), else [appLanguage]. Among several dictionaries of
/// that language the one whose region repeats the language (`de-DE`) wins,
/// then the first reported. `null` when no dictionary fits.
String? resolveSpellLanguage({
  required String setting,
  required String dictationLanguage,
  required String appLanguage,
  required List<String> available,
}) {
  if (available.isEmpty) return null;
  if (setting != spellCheckLanguageAuto) {
    final wanted = normalizeSpellTag(setting);
    for (final tag in available) {
      if (normalizeSpellTag(tag) == wanted) return tag;
    }
    return _bestForPrimary(_primary(setting), available);
  }
  final dictation = dictationLanguage.trim().toLowerCase();
  final wanted = dictation.isEmpty || dictation == 'auto'
      ? appLanguage
      : dictation;
  return _bestForPrimary(_primary(wanted), available);
}

String? _bestForPrimary(String primary, List<String> available) {
  if (primary.isEmpty) return null;
  String? first;
  for (final tag in available) {
    final norm = normalizeSpellTag(tag);
    final parts = norm.split('-');
    if (parts.first != primary) continue;
    if (parts.length == 1) return tag;
    if (parts.length == 2 && parts[1].toLowerCase() == primary) return tag;
    first ??= tag;
  }
  return first;
}

/// The native checker behind the channel.
abstract class SpellCheckBackend {
  /// Dictionary tags as the system reports them; empty without a checker.
  Future<List<String>> languages();

  /// Per word whether it is spelled correctly.
  Future<List<bool>> checkWords(String language, List<String> words);

  /// Replacement suggestions for [word], best first.
  Future<List<String>> suggest(String language, String word);
}

class ChannelSpellCheckBackend implements SpellCheckBackend {
  const ChannelSpellCheckBackend();

  static const _channel = MethodChannel('whispaste/spell_check');

  @override
  Future<List<String>> languages() async {
    try {
      final r = await _channel.invokeListMethod<String>('languages');
      return r ?? const [];
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      _log.warning('languages failed: ${e.code}');
      return const [];
    }
  }

  @override
  Future<List<bool>> checkWords(String language, List<String> words) async {
    try {
      final r = await _channel.invokeListMethod<bool>('checkWords', {
        'language': language,
        'words': words,
      });
      if (r == null || r.length != words.length) {
        return List.filled(words.length, true);
      }
      return r;
    } on MissingPluginException {
      return List.filled(words.length, true);
    } on PlatformException catch (e) {
      _log.warning('checkWords failed: ${e.code}');
      return List.filled(words.length, true);
    }
  }

  @override
  Future<List<String>> suggest(String language, String word) async {
    try {
      final r = await _channel.invokeListMethod<String>('suggest', {
        'language': language,
        'word': word,
      });
      return r ?? const [];
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      _log.warning('suggest failed: ${e.code}');
      return const [];
    }
  }
}

/// Answers from the backend with a cache per language, so typing only ever
/// asks for words not seen before.
class SpellChecker {
  SpellChecker(this.backend);

  final SpellCheckBackend backend;

  /// Words per native call; keeps a long note from blocking the channel.
  static const batchSize = 500;

  final Map<String, Map<String, bool>> _cache = {};

  /// The entries of [words] that are misspelled in [language], in order.
  /// Words in [accepted] (lower case) count as correct.
  Future<List<SpellWord>> misspelled(
    String language,
    List<SpellWord> words, {
    Set<String> accepted = const {},
  }) async {
    final cache = _cache.putIfAbsent(language, () => {});
    final unknown = <String>{
      for (final w in words)
        if (!cache.containsKey(w.text) &&
            !accepted.contains(w.text.toLowerCase()))
          w.text,
    }.toList();
    for (var i = 0; i < unknown.length; i += batchSize) {
      final batch = unknown.sublist(
        i,
        i + batchSize > unknown.length ? unknown.length : i + batchSize,
      );
      final answers = await backend.checkWords(language, batch);
      for (var j = 0; j < batch.length; j++) {
        cache[batch[j]] = answers[j];
      }
    }
    return [
      for (final w in words)
        if (!accepted.contains(w.text.toLowerCase()) && cache[w.text] == false)
          w,
    ];
  }

  Future<List<String>> suggest(String language, String word) =>
      backend.suggest(language, word);

  /// Forgets the answers for [word], e.g. after it joined the dictionary.
  void forget(String word) {
    for (final cache in _cache.values) {
      cache.remove(word);
    }
  }
}

final spellCheckBackendProvider = Provider<SpellCheckBackend>(
  (ref) => const ChannelSpellCheckBackend(),
);

final spellCheckerProvider = Provider<SpellChecker>(
  (ref) => SpellChecker(ref.watch(spellCheckBackendProvider)),
);

/// The system's dictionaries, asked once per app run.
final spellLanguagesProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(spellCheckBackendProvider).languages(),
);

/// Words of the app dictionary (lower case): every word of a replacement's
/// target. Triggers are left out on purpose, they are the misspellings.
final spellAcceptedWordsProvider = Provider<Set<String>>((ref) {
  final entries = ref.watch(replacementsProvider).value ?? const [];
  return {
    for (final r in entries)
      for (final w in spellWords(r.replacement)) w.text.toLowerCase(),
  };
});

/// The dictionary tag the editors check with, or `null` when the check is
/// off, still loading, or no dictionary fits.
final activeSpellLanguageProvider = Provider<String?>((ref) {
  final settings = ref.watch(settingsProvider).value;
  if (settings == null || !settings.interface_.spellCheckEnabled) return null;
  final available = ref.watch(spellLanguagesProvider).value ?? const [];
  return resolveSpellLanguage(
    setting: settings.interface_.spellCheckLanguage,
    dictationLanguage: settings.sttLanguageCode,
    appLanguage: ref.watch(localeProvider).languageCode,
    available: available,
  );
});
