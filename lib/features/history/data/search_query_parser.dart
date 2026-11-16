/// Parser for the WhisPaste power-search command syntax.
///
/// Supported commands:
///   `#tagname`   — exact tag filter (AND — all tags must match)
///   `lang:xx`    — language filter (e.g. lang:de, lang:en)
///   `date:range` — period filter: today, yesterday, 7d, 30d or month
///   `longer:30s` / `shorter:2m` — recording length (seconds or minutes)
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
    this.dateRange,
    this.longerThanSec,
    this.shorterThanSec,
    required this.rawQuery,
  });

  /// Free-text portion after stripping command tokens.
  final String freeText;

  /// Tag names from `#tagname` tokens (lowercase, no `#`).
  final List<String> tagNames;

  /// Language code from `lang:xx` token (lowercase), or `null`.
  final String? langCode;

  /// Period from a `date:` token, or `null`.
  final HistoryDateRange? dateRange;

  /// Minimum length in seconds from a `longer:` token, or `null`.
  final int? longerThanSec;

  /// Maximum length in seconds from a `shorter:` token, or `null`.
  final int? shorterThanSec;

  /// The original raw query string (useful for display / chips).
  final String rawQuery;

  /// `true` when there are no search terms at all.
  bool get isEmpty =>
      freeText.isEmpty &&
      tagNames.isEmpty &&
      langCode == null &&
      dateRange == null &&
      longerThanSec == null &&
      shorterThanSec == null;

  @override
  String toString() =>
      'ParsedSearchQuery(freeText: "$freeText", tags: $tagNames, '
      'lang: $langCode, date: $dateRange, longer: $longerThanSec, '
      'shorter: $shorterThanSec)';
}

// ---------------------------------------------------------------------------
// Period and length operators
// ---------------------------------------------------------------------------

/// The periods the `date:` operator and the period chips offer.
enum HistoryDateRange {
  today('today'),
  yesterday('yesterday'),
  last7Days('7d'),
  last30Days('30d'),
  monthToDate('month');

  const HistoryDateRange(this.token);

  /// The value after `date:`.
  final String token;

  static HistoryDateRange? fromToken(String token) {
    for (final range in values) {
      if (range.token == token) return range;
    }
    return null;
  }
}

/// Start (inclusive) and end (exclusive) of [range] as seen from [now].
///
/// "7 days" and "30 days" include today, so they start six and twenty-nine
/// days back at midnight.
({DateTime from, DateTime to}) resolveDateRange(
  HistoryDateRange range,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  return switch (range) {
    HistoryDateRange.today => (from: today, to: tomorrow),
    HistoryDateRange.yesterday => (
      from: DateTime(now.year, now.month, now.day - 1),
      to: today,
    ),
    HistoryDateRange.last7Days => (
      from: DateTime(now.year, now.month, now.day - 6),
      to: tomorrow,
    ),
    HistoryDateRange.last30Days => (
      from: DateTime(now.year, now.month, now.day - 29),
      to: tomorrow,
    ),
    HistoryDateRange.monthToDate => (
      from: DateTime(now.year, now.month),
      to: tomorrow,
    ),
  };
}

/// Which side of the length threshold a `longer:`/`shorter:` token sets.
enum HistoryDurationBound {
  longer('longer'),
  shorter('shorter');

  const HistoryDurationBound(this.operator);
  final String operator;
}

/// The token for a length threshold, `longer:90s` style. Whole minutes are
/// written in minutes (`longer:2m`).
String durationToken(HistoryDurationBound bound, int seconds) =>
    '${bound.operator}:${seconds % 60 == 0 ? '${seconds ~/ 60}m' : '${seconds}s'}';

final _datePattern = RegExp(r'\bdate:(\w+)', caseSensitive: false);
final _durationPattern = RegExp(
  r'\b(longer|shorter):(\d{1,5})([sm])\b',
  caseSensitive: false,
);

/// [query] with its `date:` operator replaced by [range]; `null` removes it.
/// Everything else the user typed stays as it is.
String withDateOperator(String query, HistoryDateRange? range) => _tidy(
  '${query.replaceAllMapped(_datePattern, (m) => HistoryDateRange.fromToken(m.group(1)!.toLowerCase()) == null ? m.group(0)! : ' ')}'
  '${range == null ? '' : ' date:${range.token}'}',
);

/// [query] with the `longer:`/`shorter:` operator of [bound] replaced by
/// [seconds]; `null` removes it. The other bound is kept, so "longer than 10 s"
/// and "shorter than 2 min" combine into a window.
String withDurationOperator(
  String query,
  HistoryDurationBound bound,
  int? seconds,
) {
  final kept = query.replaceAllMapped(
    _durationPattern,
    (m) => m.group(1)!.toLowerCase() == bound.operator ? ' ' : m.group(0)!,
  );
  return _tidy(
    '$kept${seconds == null ? '' : ' ${durationToken(bound, seconds)}'}',
  );
}

String _tidy(String raw) => raw.trim().replaceAll(RegExp(r'\s{2,}'), ' ');

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
  HistoryDateRange? dateRange;
  int? longerThanSec;
  int? shorterThanSec;

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

  // Strip date: token (the last known range wins; an unknown value stays text)
  remaining = remaining.replaceAllMapped(_datePattern, (m) {
    final range = HistoryDateRange.fromToken(m.group(1)!.toLowerCase());
    if (range == null) return m.group(0)!;
    dateRange = range;
    return ' ';
  });

  // Strip longer:/shorter: tokens
  remaining = remaining.replaceAllMapped(_durationPattern, (m) {
    final value =
        int.parse(m.group(2)!) * (m.group(3)!.toLowerCase() == 'm' ? 60 : 1);
    if (m.group(1)!.toLowerCase() == 'longer') {
      longerThanSec = value;
    } else {
      shorterThanSec = value;
    }
    return ' ';
  });

  // Normalise whitespace
  final freeText = remaining.trim().replaceAll(RegExp(r'\s{2,}'), ' ');

  return ParsedSearchQuery(
    freeText: freeText,
    tagNames: tagNames,
    langCode: langCode,
    dateRange: dateRange,
    longerThanSec: longerThanSec,
    shorterThanSec: shorterThanSec,
    rawQuery: raw,
  );
}
