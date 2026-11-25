/// The one search over Aufnahmen, Notizen and Textbausteine (#628): one
/// query in the syntax of the Aufnahmen search, answered from the three
/// full-text indexes, grouped by area, best answers first, each hit with the
/// excerpt around its match.
library;

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/search/search_ranker.dart';
import 'package:whispaste/features/history/data/history_title.dart';
import 'package:whispaste/features/history/data/search_query_parser.dart';
import 'package:whispaste/features/notes/data/note_search_snippet.dart';
import 'package:whispaste/features/notes/data/note_title.dart';

/// The areas the search covers, in the order the result list shows them.
enum ContentSearchArea { recordings, notes, snippets }

/// Candidates read per area: the newest matches, which the ranking then
/// orders. Bounded, so a broad query never pulls a whole history.
const kContentSearchCandidates = 50;

/// Hits shown per area.
const kContentSearchShownPerArea = 6;

/// One hit: enough to show the row and to open the item at its place.
class ContentSearchHit {
  const ContentSearchHit({
    required this.area,
    required this.id,
    required this.title,
    required this.preview,
    required this.changedAt,
    this.excerpt,
    this.matchStart,
    this.matchEnd,
    this.tags = const [],
  });

  final ContentSearchArea area;
  final String id;

  /// Display title; null for a note without a title and text (the row says
  /// "untitled").
  final String? title;

  /// The marked excerpt around the first match in the text, or null when
  /// the match lies in the title, a tag or only an operator matched.
  final NoteSearchSnippet? excerpt;

  /// Start of the text, one line, for a hit without [excerpt].
  final String preview;

  /// UTF-16 range of the marked match in the item's text, so a note opens
  /// with the match selected.
  final int? matchStart;
  final int? matchEnd;

  /// Recorded (recordings) or last changed (notes, snippets).
  final DateTime changedAt;

  /// Tag names of a note or snippet hit, by name (#662); empty for
  /// recordings, whose row stays as it was.
  final List<String> tags;

  ContentSearchHit withTags(List<String> names) => ContentSearchHit(
    area: area,
    id: id,
    title: title,
    preview: preview,
    changedAt: changedAt,
    excerpt: excerpt,
    matchStart: matchStart,
    matchEnd: matchEnd,
    tags: names,
  );
}

/// The hits of one area: the [shown] ones and how many matched in all
/// ([total], [more] when the candidate bound was reached).
class ContentSearchGroup {
  const ContentSearchGroup(
    this.area,
    this.shown,
    this.total, {
    this.more = false,
  });

  final ContentSearchArea area;
  final List<ContentSearchHit> shown;
  final int total;
  final bool more;
}

/// The answer to one query.
class ContentSearchResults {
  const ContentSearchResults({
    required this.query,
    required this.groups,
    this.withheld = false,
  });

  static const empty = ContentSearchResults(query: '', groups: []);

  final String query;

  /// Only the areas with hits, in [ContentSearchArea] order.
  final List<ContentSearchGroup> groups;

  /// True when recordings and notes were left out because the history PIN
  /// lock is closed.
  final bool withheld;

  bool get isEmpty => groups.isEmpty;

  /// Every shown hit in list order: what the arrow keys walk through.
  List<ContentSearchHit> get flat => [for (final g in groups) ...g.shown];
}

/// [raw] in the search syntax as a spec; periods resolve against [now].
ContentSearchSpec contentSearchSpecFor(String raw, DateTime now) {
  final parsed = parseSearchQuery(raw);
  final range = parsed.dateRange == null
      ? null
      : resolveDateRange(parsed.dateRange!, now);
  return ContentSearchSpec(
    freeText: parsed.freeText,
    tagNames: parsed.tagNames,
    langCode: parsed.langCode,
    from: range?.from,
    to: range?.to,
    longerThanSec: parsed.longerThanSec,
    shorterThanSec: parsed.shorterThanSec,
  );
}

/// The words of [freeText] the index matched as prefixes.
List<String> _queryTerms(String freeText) => freeText
    .replaceAll(RegExp(r'[*"()+\-^{}~:\\/]'), ' ')
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .toList();

/// What to mark in a hit's text: the first word that starts with one of
/// [terms] (as the index matched it), or the term itself anywhere for a
/// substring hit. Null without terms.
RegExp? contentMatchPattern(List<String> terms, {bool substring = false}) {
  if (terms.isEmpty) return null;
  final alternatives = ([
    ...terms,
  ]..sort((a, b) => b.length - a.length)).map(RegExp.escape).join('|');
  return RegExp(
    substring
        ? '(?:$alternatives)'
        : r'(?<![\p{L}\p{N}])(?:' + alternatives + r')[\p{L}\p{N}]*',
    caseSensitive: false,
    unicode: true,
  );
}

/// One line of the start of [text], for a row without an excerpt.
String contentPreview(String text, {int maxChars = 160}) {
  final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (line.length <= maxChars) return line;
  return '${line.substring(0, maxChars)}…';
}

/// Runs [raw] over every area. [includePrivate] false leaves recordings and
/// notes out (history PIN lock closed). Each area tries the index first and
/// falls back to a substring match when the index finds nothing there, as
/// the Aufnahmen page does.
Future<ContentSearchResults> searchAllContent(
  HistoryDatabase db,
  String raw, {
  required DateTime now,
  bool includePrivate = true,
  int candidates = kContentSearchCandidates,
  int shownPerArea = kContentSearchShownPerArea,
}) async {
  final spec = contentSearchSpecFor(raw, now);
  if (spec.isEmpty) {
    return ContentSearchResults(query: raw, groups: const []);
  }
  final terms = _queryTerms(spec.freeText);
  final hasText = terms.isNotEmpty;

  Future<List<T>> withFallback<T>(
    Future<List<T>> Function(ContentSearchSpec s) run,
    void Function(bool substring) usedSubstring,
  ) async {
    final found = await run(spec);
    if (found.isNotEmpty || !hasText) {
      usedSubstring(false);
      return found;
    }
    usedSubstring(true);
    return run(spec.asSubstring());
  }

  final groups = <ContentSearchGroup>[];

  Future<ContentSearchGroup?> group<T>(
    ContentSearchArea area,
    List<T> rows,
    bool substring,
    ContentSearchHit Function(T row, RegExp? pattern) toHit,
    List<SearchField> Function(T row) fields, {
    Future<Map<String, List<String>>> Function(List<String> ids)? tagsOf,
  }) async {
    if (rows.isEmpty) return null;
    final pattern = contentMatchPattern(terms, substring: substring);
    final ordered = _ranked(rows, fields, spec.freeText);
    var shown = [
      for (final row in ordered.take(shownPerArea)) toHit(row, pattern),
    ];
    // Only the shown hits get their tags: one small read per area.
    if (tagsOf != null) {
      final names = await tagsOf([for (final h in shown) h.id]);
      shown = [for (final h in shown) h.withTags(names[h.id] ?? const [])];
    }
    return ContentSearchGroup(
      area,
      shown,
      rows.length,
      more: rows.length >= candidates,
    );
  }

  if (includePrivate) {
    var substring = false;
    final entries = await withFallback(
      (s) => db.searchHistory(s.toHistory(), limit: candidates),
      (used) => substring = used,
    );
    final g = await group<HistoryEntry>(
      ContentSearchArea.recordings,
      entries,
      substring,
      (e, pattern) => _hit(
        ContentSearchArea.recordings,
        e.id,
        e.title.trim().isEmpty ? deriveHistoryTitle(e.content) : e.title,
        e.content,
        e.timestamp,
        pattern,
      ),
      (e) => [
        SearchField(e.title, SearchWeight.title),
        SearchField(e.content, SearchWeight.body),
      ],
    );
    if (g != null) groups.add(g);

    substring = false;
    final notes = await withFallback(
      (s) => db.searchNotesContent(s, limit: candidates),
      (used) => substring = used,
    );
    final n = await group<Note>(
      ContentSearchArea.notes,
      notes,
      substring,
      (note, pattern) => _hit(
        ContentSearchArea.notes,
        note.id,
        (note.title?.trim().isNotEmpty ?? false)
            ? note.title!.trim()
            : deriveNoteTitle(note.content),
        note.content,
        note.updatedAt,
        pattern,
      ),
      (note) => [
        SearchField(note.title ?? '', SearchWeight.title),
        SearchField(note.content, SearchWeight.body),
      ],
      tagsOf: db.tagNamesForNotes,
    );
    if (n != null) groups.add(n);
  }

  var snippetSubstring = false;
  final snippets = await withFallback(
    (s) => db.searchSnippetsContent(s, limit: candidates),
    (used) => snippetSubstring = used,
  );
  final s = await group<Snippet>(
    ContentSearchArea.snippets,
    snippets,
    snippetSubstring,
    (snippet, pattern) => _hit(
      ContentSearchArea.snippets,
      snippet.id,
      snippet.title,
      snippet.body,
      snippet.updatedAt ?? snippet.createdAt,
      pattern,
    ),
    (snippet) => [
      SearchField(snippet.title, SearchWeight.title),
      SearchField(snippet.body, SearchWeight.body),
    ],
    tagsOf: db.tagNamesForSnippets,
  );
  if (s != null) groups.add(s);

  return ContentSearchResults(
    query: raw,
    groups: groups,
    withheld: !includePrivate,
  );
}

/// [rows] in the app's one search ranking ([rankSearch]) for [freeText];
/// rows it does not rank (matched only through a tag or an annotation) keep
/// their newest-first order behind the ranked ones.
List<T> _ranked<T>(
  List<T> rows,
  List<SearchField> Function(T row) fields,
  String freeText,
) {
  if (freeText.trim().isEmpty) return rows;
  final hits = rankSearch([
    for (var i = 0; i < rows.length; i++) SearchDoc('$i', fields(rows[i])),
  ], freeText);
  final ranked = {for (final h in hits) h.index};
  return [
    for (final h in hits) rows[h.index],
    for (var i = 0; i < rows.length; i++)
      if (!ranked.contains(i)) rows[i],
  ];
}

ContentSearchHit _hit(
  ContentSearchArea area,
  String id,
  String? title,
  String text,
  DateTime changedAt,
  RegExp? pattern,
) {
  final match = pattern?.firstMatch(text);
  final excerpt = match == null
      ? null
      : noteSearchSnippet(text, match[0]!, pattern: pattern);
  return ContentSearchHit(
    area: area,
    id: id,
    title: title,
    excerpt: excerpt,
    preview: contentPreview(text),
    changedAt: changedAt,
    matchStart: match?.start,
    matchEnd: match?.end,
  );
}
