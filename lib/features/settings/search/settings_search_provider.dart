/// Settings search — query provider and substring/accent-tolerant matcher.
///
/// The PRIMARY public seam for unit tests is [matchSettingsEntries]:
/// test it directly to verify substring, case, accent and keyword behaviour
/// without Flutter context.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/locale_provider.dart';
import 'settings_search_entry.dart';

export 'settings_search_entry.dart';

// ---------------------------------------------------------------------------
// Query provider
// ---------------------------------------------------------------------------

/// Holds the current settings search query (raw user input, before debounce).
class SettingsSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final settingsSearchQueryProvider =
    NotifierProvider<SettingsSearchQueryNotifier, String>(
      SettingsSearchQueryNotifier.new,
    );

// ---------------------------------------------------------------------------
// Matches provider (derived)
// ---------------------------------------------------------------------------

/// Filtered list of [SettingsSearchEntry] matching [settingsSearchQueryProvider].
///
/// Empty when the query is blank. Uses the current app locale so title/subtitle
/// are matched in the user's language; keywords always include both DE and EN.
final settingsSearchMatchesProvider = Provider<List<SettingsSearchEntry>>((
  ref,
) {
  final query = ref.watch(settingsSearchQueryProvider);
  final locale = ref.watch(localeProvider).languageCode;
  return matchSettingsEntries(kSettingsSearchTable, query, locale);
});

// ---------------------------------------------------------------------------
// Pure match function (testable without Flutter context)
// ---------------------------------------------------------------------------

/// Returns entries from [table] whose title, subtitle or any keyword contains
/// [query] as a case-insensitive, accent-tolerant substring.
///
/// [locale] is the BCP-47 language tag (e.g. `'de'` or `'en'`) used to select
/// the localised title/subtitle for matching; keywords are always searched
/// regardless of locale.
///
/// Returns an empty list when [query] is blank.
List<SettingsSearchEntry> matchSettingsEntries(
  List<SettingsSearchEntry> table,
  String query,
  String locale,
) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];
  final needle = _fold(trimmed.toLowerCase());
  return table.where((e) {
    if (_fold(e.title(locale).toLowerCase()).contains(needle)) return true;
    if (_fold(e.subtitle(locale).toLowerCase()).contains(needle)) return true;
    return e.keywords.any((kw) => _fold(kw.toLowerCase()).contains(needle));
  }).toList();
}

// ---------------------------------------------------------------------------
// Accent / diacritic folding
// ---------------------------------------------------------------------------

/// Maps common accented characters to their ASCII base for accent-tolerant
/// substring matching.
///
/// Applied to both the needle (query) and each haystack field so that, e.g.,
/// typing `"Tastenkurzel"` still matches `"Tastenkürzel"`.
String _fold(String s) {
  const table = <String, String>{
    'ä': 'a',
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'å': 'a',
    'ö': 'o',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ü': 'u',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'ï': 'i',
    'î': 'i',
    'í': 'i',
    'ì': 'i',
    'ñ': 'n',
    'ç': 'c',
    'ß': 'ss',
  };
  final buf = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(table[ch] ?? ch);
  }
  return buf.toString();
}
