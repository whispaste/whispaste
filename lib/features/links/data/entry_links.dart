/// Reads behind links between entries (#660): what a link points at, which
/// entries the picker offers, and the title each of them shows.
///
/// Only titles and short previews are read, never a whole text: a note of a
/// million characters costs the same as a short one here.
library;

import 'package:drift/drift.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/text/entry_link.dart';
import 'package:whispaste/features/history/data/history_title.dart';
import 'package:whispaste/features/notes/data/note_title.dart';
import 'package:whispaste/features/search/data/content_search.dart';

export 'package:whispaste/core/text/entry_link.dart';

/// An entry as a link shows it: kind, id, the current title and when it
/// last changed. [title] null means the entry has no words yet ("Untitled").
class LinkedEntry {
  const LinkedEntry({
    required this.ref,
    required this.title,
    required this.changedAt,
  });

  final EntryRef ref;
  final String? title;
  final DateTime changedAt;

  @override
  bool operator ==(Object other) =>
      other is LinkedEntry &&
      other.ref == ref &&
      other.title == title &&
      other.changedAt == changedAt;

  @override
  int get hashCode => Object.hash(ref, title, changedAt);
}

String? _noteTitle(String? title, String? preview) =>
    (title?.trim().isNotEmpty ?? false)
    ? title!.trim()
    : deriveNoteTitle(preview ?? '');

String? _recordingTitle(String title, String? preview) {
  if (title.trim().isNotEmpty) return title.trim();
  final derived = deriveHistoryTitle(preview ?? '');
  return derived.isEmpty ? null : derived;
}

/// The live entries among [refs] with their current titles. Entries in the
/// trash or gone are missing from the result: a link to them is shown as
/// not found. With [includePrivate] false (history PIN lock closed) notes
/// and recordings are left out as well.
Future<Map<EntryRef, LinkedEntry>> resolveLinkedEntries(
  HistoryDatabase db,
  Iterable<EntryRef> refs, {
  required bool includePrivate,
}) async {
  final byKind = <EntryLinkKind, Set<String>>{};
  for (final ref in refs) {
    byKind.putIfAbsent(ref.kind, () => <String>{}).add(ref.id);
  }
  final result = <EntryRef, LinkedEntry>{};
  void add(EntryLinkKind kind, String id, String? title, DateTime at) {
    final ref = (kind: kind, id: id);
    result[ref] = LinkedEntry(ref: ref, title: title, changedAt: at);
  }

  if (includePrivate) {
    final noteIds = byKind[EntryLinkKind.note];
    if (noteIds != null && noteIds.isNotEmpty) {
      final n = db.notes;
      final preview = _notePreview(n);
      final rows =
          await (db.selectOnly(n)
                ..addColumns([n.id, n.title, preview, n.updatedAt])
                ..where(n.id.isIn(noteIds) & n.deletedAt.isNull()))
              .get();
      for (final row in rows) {
        add(
          EntryLinkKind.note,
          row.read(n.id)!,
          _noteTitle(row.read(n.title), row.read(preview)),
          row.read(n.updatedAt)!,
        );
      }
    }
    final entryIds = byKind[EntryLinkKind.recording];
    if (entryIds != null && entryIds.isNotEmpty) {
      final h = db.historyEntries;
      final preview = _entryPreview(h);
      final rows =
          await (db.selectOnly(h)
                ..addColumns([h.id, h.title, preview, h.timestamp])
                ..where(h.id.isIn(entryIds) & h.deletedAt.isNull()))
              .get();
      for (final row in rows) {
        add(
          EntryLinkKind.recording,
          row.read(h.id)!,
          _recordingTitle(row.read(h.title) ?? '', row.read(preview)),
          row.read(h.timestamp)!,
        );
      }
    }
  }
  final snippetIds = byKind[EntryLinkKind.snippet];
  if (snippetIds != null && snippetIds.isNotEmpty) {
    final s = db.snippets;
    final rows =
        await (db.selectOnly(s)
              ..addColumns([s.id, s.title, s.createdAt, s.updatedAt])
              ..where(s.id.isIn(snippetIds) & s.deletedAt.isNull()))
            .get();
    for (final row in rows) {
      add(
        EntryLinkKind.snippet,
        row.read(s.id)!,
        row.read(s.title),
        row.read(s.updatedAt) ?? row.read(s.createdAt)!,
      );
    }
  }
  return result;
}

/// What the link picker offers before anything is typed: the most recently
/// changed entries of every kind, newest first, at most [limit] in all.
/// Trash and archive are left out; [except] is the entry being written.
Future<List<LinkedEntry>> recentLinkTargets(
  HistoryDatabase db, {
  required bool includePrivate,
  EntryRef? except,
  int limit = 12,
}) async {
  final found = <LinkedEntry>[];
  if (includePrivate) {
    final n = db.notes;
    final notePreview = _notePreview(n);
    final notes =
        await (db.selectOnly(n)
              ..addColumns([n.id, n.title, notePreview, n.updatedAt])
              ..where(n.deletedAt.isNull() & n.archived.equals(false))
              ..orderBy([OrderingTerm.desc(n.updatedAt)])
              ..limit(limit))
            .get();
    for (final row in notes) {
      found.add(
        LinkedEntry(
          ref: (kind: EntryLinkKind.note, id: row.read(n.id)!),
          title: _noteTitle(row.read(n.title), row.read(notePreview)),
          changedAt: row.read(n.updatedAt)!,
        ),
      );
    }
    final h = db.historyEntries;
    final entryPreview = _entryPreview(h);
    final entries =
        await (db.selectOnly(h)
              ..addColumns([h.id, h.title, entryPreview, h.timestamp])
              ..where(h.deletedAt.isNull() & h.archived.equals(false))
              ..orderBy([OrderingTerm.desc(h.timestamp)])
              ..limit(limit))
            .get();
    for (final row in entries) {
      found.add(
        LinkedEntry(
          ref: (kind: EntryLinkKind.recording, id: row.read(h.id)!),
          title: _recordingTitle(
            row.read(h.title) ?? '',
            row.read(entryPreview),
          ),
          changedAt: row.read(h.timestamp)!,
        ),
      );
    }
  }
  final s = db.snippets;
  final changed = coalesce([s.updatedAt, s.createdAt]);
  final snippets =
      await (db.selectOnly(s)
            ..addColumns([s.id, s.title, s.createdAt, s.updatedAt])
            ..where(s.deletedAt.isNull())
            ..orderBy([OrderingTerm.desc(changed)])
            ..limit(limit))
          .get();
  for (final row in snippets) {
    found.add(
      LinkedEntry(
        ref: (kind: EntryLinkKind.snippet, id: row.read(s.id)!),
        title: row.read(s.title),
        changedAt: row.read(s.updatedAt) ?? row.read(s.createdAt)!,
      ),
    );
  }
  found
    ..removeWhere((e) => e.ref == except)
    ..sort((a, b) => b.changedAt.compareTo(a.changedAt));
  return found.take(limit).toList();
}

/// The picker's answer to [query]: the app's search over every area
/// ([searchAllContent], same ranking and PIN rule), flattened into one list
/// in area order. [except] is the entry being written.
Future<List<LinkedEntry>> searchLinkTargets(
  HistoryDatabase db,
  String query, {
  required DateTime now,
  required bool includePrivate,
  EntryRef? except,
}) async {
  final results = await searchAllContent(
    db,
    query,
    now: now,
    includePrivate: includePrivate,
  );
  return [
    for (final group in results.groups)
      for (final hit in group.shown)
        if ((kind: _kindOf(hit.area), id: hit.id) != except)
          LinkedEntry(
            ref: (kind: _kindOf(hit.area), id: hit.id),
            title: hit.title,
            changedAt: hit.changedAt,
          ),
  ];
}

EntryLinkKind _kindOf(ContentSearchArea area) => switch (area) {
  ContentSearchArea.recordings => EntryLinkKind.recording,
  ContentSearchArea.notes => EntryLinkKind.note,
  ContentSearchArea.snippets => EntryLinkKind.snippet,
};

// Rows written before the preview column was filled fall back to the start
// of the text, cut in SQL, as the lists do.
Expression<String> _notePreview($NotesTable n) =>
    coalesce([n.preview, n.content.substr(1, 500)]);

Expression<String> _entryPreview($HistoryEntriesTable h) =>
    coalesce([h.preview, h.content.substr(1, 500)]);
