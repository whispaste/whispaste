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

/// Set of section keys whose entries match the current query.
///
/// Returns `null` when the query is blank — meaning "show all sections".
/// Returns a (possibly empty) [Set<String>] of matching [SettingsSearchEntry.sectionKey]
/// values when the query is non-blank.
final settingsSectionMatchSetProvider = Provider<Set<String>?>((ref) {
  final query = ref.watch(settingsSearchQueryProvider).trim();
  if (query.isEmpty) return null;
  final matches = ref.watch(settingsSearchMatchesProvider);
  return matches.map((e) => e.sectionKey).toSet();
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

  // PERF (Bolt): Precompile RegExp with `caseSensitive: false` before the loop
  // to avoid allocating hundreds of lowercase String objects via `toLowerCase()`
  // on every keystroke during a search.
  final needle = RegExp.escape(_fold(trimmed));
  final regex = RegExp(needle, caseSensitive: false);

  return table.where((e) {
    if (regex.hasMatch(_fold(e.title(locale)))) return true;
    if (regex.hasMatch(_fold(e.subtitle(locale)))) return true;
    return e.keywords.any((kw) => regex.hasMatch(_fold(kw)));
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
    'ä': 'a', 'Ä': 'A',
    'à': 'a', 'À': 'A',
    'á': 'a', 'Á': 'A',
    'â': 'a', 'Â': 'A',
    'ã': 'a', 'Ã': 'A',
    'å': 'a', 'Å': 'A',
    'ö': 'o', 'Ö': 'O',
    'ò': 'o', 'Ò': 'O',
    'ó': 'o', 'Ó': 'O',
    'ô': 'o', 'Ô': 'O',
    'õ': 'o', 'Õ': 'O',
    'ü': 'u', 'Ü': 'U',
    'ù': 'u', 'Ù': 'U',
    'ú': 'u', 'Ú': 'U',
    'û': 'u', 'Û': 'U',
    'é': 'e', 'É': 'E',
    'è': 'e', 'È': 'E',
    'ê': 'e', 'Ê': 'E',
    'ë': 'e', 'Ë': 'E',
    'ï': 'i', 'Ï': 'I',
    'î': 'i', 'Î': 'I',
    'í': 'i', 'Í': 'I',
    'ì': 'i', 'Ì': 'I',
    'ñ': 'n', 'Ñ': 'N',
    'ç': 'c', 'Ç': 'C',
    'ß':
        'ss', // Note: dart's toLowerCase doesn't convert ß to ss, regex case-insensitivity covers typical alpha case
  };
  final buf = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(table[ch] ?? ch);
  }
  return buf.toString();
}
