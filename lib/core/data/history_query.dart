/// Bounded history queries (#1643): what a search matches, as SQL, so the
/// database returns one page or one count instead of every match.
library;

import 'package:drift/drift.dart';

import 'note_preview.dart';

/// The order of a list on the Aufnahmen page (#1663). It is part of the
/// query, so every page continues where the previous one ended and the first
/// page already holds the oldest or longest recordings of the whole history.
enum HistorySortOrder {
  /// Pinned first, then newest. The default view.
  newest,

  /// Oldest first; pins do not jump the queue.
  oldest,

  /// Longest first, equal lengths newest first; pins do not jump the queue.
  longest,
}

/// The ORDER BY terms of [order] over `history_entries he`. The id is the
/// last term, so rows with equal values keep one order across pages.
String historyOrderBy(HistorySortOrder order) => switch (order) {
  HistorySortOrder.newest => 'he.pinned DESC, he.timestamp DESC, he.id DESC',
  HistorySortOrder.oldest => 'he.timestamp ASC, he.id ASC',
  HistorySortOrder.longest =>
    'he.duration_sec DESC, he.timestamp DESC, he.id DESC',
};

/// How many recordings "Alle auswählen" takes at most (#1663): every match
/// of the list up to this bound, in list order. It keeps the id list of a
/// bulk action well below SQLite's limit of 32 766 bound values per
/// statement and the selection small in memory.
const historySelectAllLimit = 10000;

/// Length bounds of the duration chips (#879). [below] and [above] exclude
/// their value, [atLeast] and [atMost] include it, so 60 s and 300 s land in
/// "1–5 min" only.
class HistoryDurationBounds {
  const HistoryDurationBounds({
    this.below,
    this.above,
    this.atLeast,
    this.atMost,
  });

  final double? below;
  final double? above;
  final double? atLeast;
  final double? atMost;

  bool matches(double seconds) =>
      (below == null || seconds < below!) &&
      (above == null || seconds > above!) &&
      (atLeast == null || seconds >= atLeast!) &&
      (atMost == null || seconds <= atMost!);
}

/// What a history search matches. The fields mirror the operators of the
/// search field; [archived], [deleted], [pinnedOnly] and [duration] narrow
/// the result to one list of the Aufnahmen page.
class HistorySearchSpec {
  const HistorySearchSpec({
    this.freeText = '',
    this.tagNames = const [],
    this.langCode,
    this.includeDeleted = false,
    this.includeArchived = false,
    this.from,
    this.to,
    this.longerThanSec,
    this.shorterThanSec,
    this.archived,
    this.deleted,
    this.pinnedOnly = false,
    this.duration,
    this.substring = false,
  });

  /// FTS5 prefix match on title, content and legacy tags, plus a substring
  /// match on tag names and note texts. Never matches a trashed entry.
  final String freeText;

  /// Exact tag names, all of which an entry must carry.
  final List<String> tagNames;
  final String? langCode;

  /// Without it, trashed entries are left out.
  final bool includeDeleted;

  /// Without it, archived entries are left out, but only when neither
  /// [freeText] nor [tagNames] pinpoints them.
  final bool includeArchived;
  final DateTime? from;
  final DateTime? to;
  final int? longerThanSec;
  final int? shorterThanSec;

  /// Exactly archived (true) or not archived (false); null = either.
  final bool? archived;

  /// Exactly trashed (true) or not trashed (false); null = either.
  final bool? deleted;
  final bool pinnedOnly;
  final HistoryDurationBounds? duration;

  /// Matches [freeText] as a case-insensitive substring of the title or the
  /// stored preview instead of the full-text index: the second try when the
  /// index finds nothing (a word part in the middle of a word).
  final bool substring;

  HistorySearchSpec copyWith({
    bool? archived,
    bool? deleted,
    bool? pinnedOnly,
    bool? substring,
  }) => HistorySearchSpec(
    freeText: freeText,
    tagNames: tagNames,
    langCode: langCode,
    includeDeleted: includeDeleted,
    includeArchived: includeArchived,
    from: from,
    to: to,
    longerThanSec: longerThanSec,
    shorterThanSec: shorterThanSec,
    archived: archived ?? this.archived,
    deleted: deleted ?? this.deleted,
    pinnedOnly: pinnedOnly ?? this.pinnedOnly,
    duration: duration,
    substring: substring ?? this.substring,
  );
}

/// The WHERE clause of [spec] over `history_entries he`, or null when it can
/// match nothing (a blank free text). Values are bound, never spliced in.
({String sql, List<Variable<Object>> variables})? historySearchWhere(
  HistorySearchSpec spec,
) {
  final where = <String>[];
  final vars = <Variable<Object>>[];

  final uniqueTags = spec.tagNames
      .map((t) => t.toLowerCase().trim())
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();

  if (spec.freeText.isNotEmpty) {
    if (!_addFreeText(spec, where, vars)) return null;
  }
  _addTags(uniqueTags, where, vars);
  _addState(spec, uniqueTags.isEmpty, where);
  _addRanges(spec, where, vars);

  return (sql: where.isEmpty ? '1 = 1' : where.join(' AND '), variables: vars);
}

/// Adds the free-text clause; false when the text is blank after trimming.
bool _addFreeText(
  HistorySearchSpec spec,
  List<String> where,
  List<Variable<Object>> vars,
) {
  final rawLower = spec.freeText.toLowerCase().trim();
  if (rawLower.isEmpty) return false;
  final like = '%${escapeLikePattern(rawLower)}%';
  if (spec.substring) {
    where.add(
      r"(LOWER(he.title) LIKE ? ESCAPE '\' OR LOWER(COALESCE(he.preview, "
      "substr(he.content, 1, $kNotePreviewLength))) LIKE ? ESCAPE '\\')",
    );
  } else {
    final fts = ftsPrefixQuery(spec.freeText);
    final branches = <String>[
      if (fts.isNotEmpty)
        'he.rowid IN (SELECT rowid FROM history_fts '
            'WHERE history_fts MATCH ?)',
      'he.id IN (SELECT et.entry_id FROM entry_tags et '
          'INNER JOIN tags t ON t.id = et.tag_id '
          r"WHERE LOWER(t.name) LIKE ? ESCAPE '\')",
      'he.id IN (SELECT en.entry_id FROM entry_notes en '
          r"WHERE LOWER(en.content) LIKE ? ESCAPE '\')",
    ];
    where.add('(${branches.join(' OR ')})');
    if (fts.isNotEmpty) vars.add(Variable.withString(fts));
  }
  vars
    ..add(Variable.withString(like))
    ..add(Variable.withString(like));
  // A free-text match never reaches into the trash (as before #1643).
  where.add('he.deleted_at IS NULL');
  return true;
}

void _addTags(
  List<String> uniqueTags,
  List<String> where,
  List<Variable<Object>> vars,
) {
  if (uniqueTags.isNotEmpty) {
    final placeholders = List.filled(uniqueTags.length, '?').join(', ');
    where.add(
      'he.id IN (SELECT et.entry_id FROM entry_tags et '
      'INNER JOIN tags t ON t.id = et.tag_id '
      'WHERE LOWER(t.name) IN ($placeholders) '
      'GROUP BY et.entry_id '
      'HAVING COUNT(DISTINCT LOWER(t.name)) = ${uniqueTags.length})',
    );
    vars.addAll(uniqueTags.map(Variable.withString));
  }
}

/// Archive, trash, pinned and language conditions.
void _addState(HistorySearchSpec spec, bool noTags, List<String> where) {
  if (!spec.includeDeleted) where.add('he.deleted_at IS NULL');
  if (!spec.includeArchived &&
      spec.freeText.isEmpty &&
      noTags &&
      spec.archived == null) {
    where.add('he.archived = 0');
  }
  if (spec.archived case final archived?) {
    where.add('he.archived = ${archived ? 1 : 0}');
  }
  if (spec.deleted != null) {
    where.add(
      spec.deleted! ? 'he.deleted_at IS NOT NULL' : 'he.deleted_at IS NULL',
    );
  }
  if (spec.pinnedOnly) where.add('he.pinned = 1');
}

/// Language, time range and duration conditions.
void _addRanges(
  HistorySearchSpec spec,
  List<String> where,
  List<Variable<Object>> vars,
) {
  final lang = spec.langCode;
  if (lang != null && lang.isNotEmpty) {
    where.add('he.language = ?');
    vars.add(Variable.withString(lang));
  }
  if (spec.from != null) {
    where.add('he.timestamp >= ?');
    vars.add(Variable.withDateTime(spec.from!));
  }
  if (spec.to != null) {
    where.add('he.timestamp < ?');
    vars.add(Variable.withDateTime(spec.to!));
  }
  void bound(String op, num? value) {
    if (value == null) return;
    where.add('he.duration_sec $op ?');
    vars.add(Variable.withReal(value.toDouble()));
  }

  bound('>', spec.longerThanSec);
  bound('<', spec.shorterThanSec);
  final d = spec.duration;
  if (d != null) {
    bound('<', d.below);
    bound('>', d.above);
    bound('>=', d.atLeast);
    bound('<=', d.atMost);
  }
}

/// Escapes LIKE special characters (`%`, `_`, `\`).
String escapeLikePattern(String input) =>
    input.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

/// [query] as an FTS5 prefix query: special characters removed, every term
/// quoted and matched as a prefix. Empty when nothing is left.
String ftsPrefixQuery(String query) {
  final cleaned = query
      .replaceAll(RegExp(r'[*"()+\-^{}~:\\/]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return '';
  final terms = cleaned.split(' ').where((t) => t.isNotEmpty).toList();
  if (terms.isEmpty) return '';
  return terms.map((t) => '"$t"*').join(' ');
}
