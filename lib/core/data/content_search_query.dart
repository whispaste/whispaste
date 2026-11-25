/// What the one search over Aufnahmen, Notizen and Textbausteine matches
/// (#628), as SQL over the notes and snippets indexes. Recordings go through
/// [historySearchWhere], so every area reads the same search syntax the
/// Aufnahmen page has: free text as an FTS5 prefix query, `#tag`, `lang:`,
/// `date:`, `longer:` and `shorter:`.
library;

import 'package:drift/drift.dart';

import 'history_query.dart';

/// One query of the search over every area, already parsed.
class ContentSearchSpec {
  const ContentSearchSpec({
    this.freeText = '',
    this.tagNames = const [],
    this.langCode,
    this.from,
    this.to,
    this.longerThanSec,
    this.shorterThanSec,
    this.substring = false,
  });

  /// Matched as an FTS5 prefix query on title and text (and, in every area,
  /// as a substring of a tag name).
  final String freeText;

  /// Exact tag names that a recording, note or snippet must all carry
  /// (snippets since #662).
  final List<String> tagNames;

  /// Recording-only filters: language and length. A note or a snippet has
  /// neither, so these leave both out.
  final String? langCode;
  final int? longerThanSec;
  final int? shorterThanSec;

  /// Period: when a recording was made, when a note or snippet was last
  /// changed. [from] inclusive, [to] exclusive.
  final DateTime? from;
  final DateTime? to;

  /// The second try when the index finds nothing in an area: [freeText] as
  /// a case-insensitive substring of title or text (a word part in the
  /// middle of a word), as on the Aufnahmen page.
  final bool substring;

  /// True when nothing at all was asked for.
  bool get isEmpty =>
      freeText.trim().isEmpty &&
      tagNames.isEmpty &&
      langCode == null &&
      from == null &&
      to == null &&
      longerThanSec == null &&
      shorterThanSec == null;

  /// Whether a filter only recordings can satisfy is set.
  bool get recordingsOnly =>
      (langCode?.isNotEmpty ?? false) ||
      longerThanSec != null ||
      shorterThanSec != null;

  ContentSearchSpec asSubstring() => ContentSearchSpec(
    freeText: freeText,
    tagNames: tagNames,
    langCode: langCode,
    from: from,
    to: to,
    longerThanSec: longerThanSec,
    shorterThanSec: shorterThanSec,
    substring: true,
  );

  /// The same query for the recordings list.
  HistorySearchSpec toHistory() => HistorySearchSpec(
    freeText: freeText.trim(),
    tagNames: tagNames,
    langCode: langCode,
    from: from,
    to: to,
    longerThanSec: longerThanSec,
    shorterThanSec: shorterThanSec,
    substring: substring,
  );
}

typedef SqlWhere = ({String sql, List<Variable<Object>> variables});

List<String> _uniqueTags(List<String> names) => names
    .map((t) => t.toLowerCase().trim())
    .where((t) => t.isNotEmpty)
    .toSet()
    .toList();

/// The WHERE clause of [spec] over `notes n` (trash left out), or null when
/// no note can match.
SqlWhere? notesSearchWhere(ContentSearchSpec spec) {
  if (spec.isEmpty || spec.recordingsOnly) return null;
  final where = <String>['n.deleted_at IS NULL'];
  final vars = <Variable<Object>>[];
  final text = spec.freeText.trim().toLowerCase();
  if (text.isNotEmpty) {
    final like = '%${escapeLikePattern(text)}%';
    if (spec.substring) {
      where.add(
        r"(LOWER(COALESCE(n.title, '')) LIKE ? ESCAPE '\' "
        r"OR LOWER(n.content) LIKE ? ESCAPE '\')",
      );
      vars
        ..add(Variable.withString(like))
        ..add(Variable.withString(like));
    } else {
      final fts = ftsPrefixQuery(spec.freeText);
      final branches = <String>[
        if (fts.isNotEmpty)
          'n.rowid IN (SELECT rowid FROM notes_fts WHERE notes_fts MATCH ?)',
        'n.id IN (SELECT nt.note_id FROM note_tags nt '
            'INNER JOIN tags t ON t.id = nt.tag_id '
            r"WHERE LOWER(t.name) LIKE ? ESCAPE '\')",
      ];
      where.add('(${branches.join(' OR ')})');
      if (fts.isNotEmpty) vars.add(Variable.withString(fts));
      vars.add(Variable.withString(like));
    }
  }
  final tags = _uniqueTags(spec.tagNames);
  if (tags.isNotEmpty) {
    where.add(
      'n.id IN (SELECT nt.note_id FROM note_tags nt '
      'INNER JOIN tags t ON t.id = nt.tag_id '
      'WHERE LOWER(t.name) IN (${List.filled(tags.length, '?').join(', ')}) '
      'GROUP BY nt.note_id '
      'HAVING COUNT(DISTINCT LOWER(t.name)) = ${tags.length})',
    );
    vars.addAll(tags.map(Variable.withString));
  }
  _addPeriod('n.updated_at', spec, where, vars);
  return (sql: where.join(' AND '), variables: vars);
}

/// The WHERE clause of [spec] over `snippets s` (trash left out), or null
/// when no snippet can match. Tags (#662) work as for notes: `#tag` narrows
/// to snippets carrying every named tag, free text also finds a tag name.
SqlWhere? snippetsSearchWhere(ContentSearchSpec spec) {
  if (spec.isEmpty || spec.recordingsOnly) return null;
  final where = <String>['s.deleted_at IS NULL'];
  final vars = <Variable<Object>>[];
  final text = spec.freeText.trim().toLowerCase();
  if (text.isNotEmpty) {
    final like = '%${escapeLikePattern(text)}%';
    if (spec.substring) {
      where.add(
        r"(LOWER(s.title) LIKE ? ESCAPE '\' OR LOWER(s.body) LIKE ? ESCAPE '\')",
      );
      vars
        ..add(Variable.withString(like))
        ..add(Variable.withString(like));
    } else {
      final fts = ftsPrefixQuery(spec.freeText);
      final branches = <String>[
        if (fts.isNotEmpty)
          's.rowid IN (SELECT rowid FROM snippets_fts WHERE snippets_fts MATCH ?)',
        's.id IN (SELECT st.snippet_id FROM snippet_tags st '
            'INNER JOIN tags t ON t.id = st.tag_id '
            r"WHERE LOWER(t.name) LIKE ? ESCAPE '\')",
      ];
      where.add('(${branches.join(' OR ')})');
      if (fts.isNotEmpty) vars.add(Variable.withString(fts));
      vars.add(Variable.withString(like));
    }
  }
  final tags = _uniqueTags(spec.tagNames);
  if (tags.isNotEmpty) {
    where.add(
      's.id IN (SELECT st.snippet_id FROM snippet_tags st '
      'INNER JOIN tags t ON t.id = st.tag_id '
      'WHERE LOWER(t.name) IN (${List.filled(tags.length, '?').join(', ')}) '
      'GROUP BY st.snippet_id '
      'HAVING COUNT(DISTINCT LOWER(t.name)) = ${tags.length})',
    );
    vars.addAll(tags.map(Variable.withString));
  }
  _addPeriod('COALESCE(s.updated_at, s.created_at)', spec, where, vars);
  return (sql: where.join(' AND '), variables: vars);
}

void _addPeriod(
  String column,
  ContentSearchSpec spec,
  List<String> where,
  List<Variable<Object>> vars,
) {
  if (spec.from case final from?) {
    where.add('$column >= ?');
    vars.add(Variable.withDateTime(from));
  }
  if (spec.to case final to?) {
    where.add('$column < ?');
    vars.add(Variable.withDateTime(to));
  }
}
