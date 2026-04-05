/// WhisPaste history database — drift database class.
///
/// Central database accessor for all history features.
/// Uses drift code generation — run `dart run build_runner build`
/// to generate the `.g.dart` file.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  HistoryEntries,
  Projects,
  DailyStats,
  EntryNotes,
  EntryAttachments,
])
class HistoryDatabase extends _$HistoryDatabase {
  HistoryDatabase() : super(_openConnection());

  /// For testing — accepts an in-memory or custom executor.
  HistoryDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Create FTS5 virtual table and sync triggers via raw SQL
          await _createFts(m);
        },
        onUpgrade: (m, from, to) async {
          // Future migrations go here
        },
      );

  /// Creates the FTS5 virtual table and triggers for full-text search.
  Future<void> _createFts(Migrator m) async {
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS history_fts USING fts5(
        title, content,
        content='',
        tokenize='unicode61'
      )
    ''');

    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS history_fts_ai AFTER INSERT ON history_entries
      BEGIN
        INSERT INTO history_fts(rowid, title, content)
        VALUES (new.rowid, new.title, new.content);
      END
    ''');

    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS history_fts_ad AFTER DELETE ON history_entries
      BEGIN
        INSERT INTO history_fts(history_fts, rowid, title, content)
        VALUES ('delete', old.rowid, old.title, old.content);
      END
    ''');

    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS history_fts_au AFTER UPDATE ON history_entries
      BEGIN
        INSERT INTO history_fts(history_fts, rowid, title, content)
        VALUES ('delete', old.rowid, old.title, old.content);
        INSERT INTO history_fts(rowid, title, content)
        VALUES (new.rowid, new.title, new.content);
      END
    ''');
  }

  // ---------------------------------------------------------------------------
  // Query helpers
  // ---------------------------------------------------------------------------

  /// All non-deleted entries, newest first.
  Future<List<HistoryEntry>> allEntries({int limit = 100, int offset = 0}) {
    return (select(historyEntries)
          ..where((e) => e.deletedAt.isNull())
          ..orderBy([
            (e) => OrderingTerm(expression: e.timestamp, mode: OrderingMode.desc)
          ])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Pinned entries only.
  Future<List<HistoryEntry>> pinnedEntries() {
    return (select(historyEntries)
          ..where((e) => e.pinned.equals(true) & e.deletedAt.isNull())
          ..orderBy([
            (e) => OrderingTerm(expression: e.timestamp, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// Entries in a specific project.
  Future<List<HistoryEntry>> entriesByProject(String projectId) {
    return (select(historyEntries)
          ..where(
              (e) => e.projectId.equals(projectId) & e.deletedAt.isNull())
          ..orderBy([
            (e) => OrderingTerm(expression: e.timestamp, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// Full-text search via FTS5.
  Future<List<HistoryEntry>> searchEntries(String query) async {
    final ftsResults = await customSelect(
      'SELECT rowid FROM history_fts WHERE history_fts MATCH ?',
      variables: [Variable.withString(query)],
    ).get();

    if (ftsResults.isEmpty) return [];

    final rowIds = ftsResults.map((r) => r.read<int>('rowid')).toList();
    return (select(historyEntries)
          ..where((e) =>
              e.rowId.isIn(rowIds) & e.deletedAt.isNull())
          ..orderBy([
            (e) => OrderingTerm(expression: e.timestamp, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// Soft-delete an entry (move to trash).
  Future<int> softDeleteEntry(String entryId) {
    return (update(historyEntries)..where((e) => e.id.equals(entryId)))
        .write(HistoryEntriesCompanion(deletedAt: Value(DateTime.now())));
  }

  /// Permanently remove soft-deleted entries older than [days].
  Future<int> purgeTrash({int days = 30}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return (delete(historyEntries)
          ..where((e) => e.deletedAt.isNotNull() & e.deletedAt.isSmallerThanValue(cutoff)))
        .go();
  }

  /// Insert or update an entry.
  Future<void> upsertEntry(HistoryEntriesCompanion entry) {
    return into(historyEntries).insertOnConflictUpdate(entry);
  }

  /// Toggle pin status.
  Future<void> togglePin(String entryId) async {
    final entry = await (select(historyEntries)
          ..where((e) => e.id.equals(entryId)))
        .getSingleOrNull();
    if (entry == null) return;
    await (update(historyEntries)..where((e) => e.id.equals(entryId)))
        .write(HistoryEntriesCompanion(pinned: Value(!entry.pinned)));
  }

  /// Watch all non-deleted entries as a live stream.
  Stream<List<HistoryEntry>> watchEntries({int limit = 100}) {
    return (select(historyEntries)
          ..where((e) => e.deletedAt.isNull())
          ..orderBy([
            (e) => OrderingTerm(expression: e.timestamp, mode: OrderingMode.desc)
          ])
          ..limit(limit))
        .watch();
  }

  // ---------------------------------------------------------------------------
  // Projects
  // ---------------------------------------------------------------------------

  Future<List<Project>> allProjects() {
    return (select(projects)
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .get();
  }

  Future<void> upsertProject(ProjectsCompanion project) {
    return into(projects).insertOnConflictUpdate(project);
  }

  Future<int> deleteProject(String projectId) {
    return (delete(projects)..where((p) => p.id.equals(projectId))).go();
  }

  // ---------------------------------------------------------------------------
  // Notes
  // ---------------------------------------------------------------------------

  Future<List<EntryNote>> notesForEntry(String entryId) {
    return (select(entryNotes)
          ..where((n) => n.entryId.equals(entryId))
          ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
        .get();
  }

  Future<void> upsertNote(EntryNotesCompanion note) {
    return into(entryNotes).insertOnConflictUpdate(note);
  }

  Future<int> deleteNote(String noteId) {
    return (delete(entryNotes)..where((n) => n.id.equals(noteId))).go();
  }
}

// ---------------------------------------------------------------------------
// Connection factory
// ---------------------------------------------------------------------------

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'history.db'));
    return NativeDatabase.createInBackground(file);
  });
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// Global database provider — single instance across the app.
// TODO: Replace with real Riverpod provider when history DB is connected
final historyDatabaseProvider = Provider<HistoryDatabase>((ref) {
  final db = HistoryDatabase();
  ref.onDispose(db.close);
  return db;
});
