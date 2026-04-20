/// Parser for the WhisPaste power-search command syntax.
///
/// Supported commands:
///   `#tagname`   — exact tag filter (AND — all tags must match)
///   `lang:xx`    — language filter (e.g. lang:de, lang:en)
///
/// Everything else is treated as free-text passed to FTS5.
library;

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

class ParsedSearchQuery {
  const ParsedSearchQuery({
    required this.freeText,
    this.tagNames = const [],
    this.langCode,
    required this.rawQuery,
  });

  /// Free-text portion after stripping command tokens.
  final String freeText;

  /// Tag names from `#tagname` tokens (lowercase, no `#`).
  final List<String> tagNames;

  /// Language code from `lang:xx` token (lowercase), or `null`.
  final String? langCode;

  /// The original raw query string (useful for display / chips).
  final String rawQuery;

  /// `true` when there are no search terms at all.
  bool get isEmpty =>
      freeText.isEmpty && tagNames.isEmpty && langCode == null;

  @override
  String toString() =>
      'ParsedSearchQuery(freeText: "$freeText", tags: $tagNames, lang: $langCode)';
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

/// Regex for `#word` tokens — allows word chars, hyphens, underscores.
final _tagPattern = RegExp(r'#([\w-]+)', caseSensitive: false);

/// Regex for `lang:xx` or `lang:xx-YY` tokens.
final _langPattern = RegExp(r'\blang:([\w-]{2,10})\b', caseSensitive: false);

/// Parse [raw] into a [ParsedSearchQuery].
///
/// Matching is case-insensitive; all results are normalised to lower-case.
ParsedSearchQuery parseSearchQuery(String raw) {
  final tagNames = <String>[];
  String? langCode;

  // Strip tag tokens
  var remaining = raw.replaceAllMapped(_tagPattern, (m) {
    tagNames.add(m.group(1)!.toLowerCase());
    return ' ';
  });

  // Strip lang: token (only the last one wins)
  remaining = remaining.replaceAllMapped(_langPattern, (m) {
    langCode = m.group(1)!.toLowerCase();
    return ' ';
  });

  // Normalise whitespace
  final freeText = remaining.trim().replaceAll(RegExp(r'\s{2,}'), ' ');

  return ParsedSearchQuery(
    freeText: freeText,
    tagNames: tagNames,
    langCode: langCode,
    rawQuery: raw,
  );
}
