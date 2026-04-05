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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Create FTS5 virtual table and sync triggers via raw SQL
          await _createFts(m);
          await _createAppSettingsTable();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await _createAppSettingsTable();
          }
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

  /// Creates the key-value settings table used by the Flutter settings layer.
  Future<void> _createAppSettingsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ---------------------------------------------------------------------------
  // Query helpers
  // ---------------------------------------------------------------------------

  /// All non-deleted, non-archived entries, newest first.
  Future<List<HistoryEntry>> allEntries({int limit = 100, int offset = 0}) {
    return (select(historyEntries)
          ..where((e) => e.deletedAt.isNull() & e.archived.equals(false))
          ..orderBy([
            (e) => OrderingTerm(expression: e.timestamp, mode: OrderingMode.desc)
          ])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Pinned entries only (non-deleted, non-archived).
  Future<List<HistoryEntry>> pinnedEntries() {
    return (select(historyEntries)
          ..where((e) =>
              e.pinned.equals(true) &
              e.deletedAt.isNull() &
              e.archived.equals(false))
          ..orderBy([
            (e) => OrderingTerm(expression: e.timestamp, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// Archived entries only (non-deleted).
  Future<List<HistoryEntry>> archivedEntries({int limit = 100}) {
    return (select(historyEntries)
          ..where((e) =>
              e.archived.equals(true) & e.deletedAt.isNull())
          ..orderBy([
            (e) => OrderingTerm(expression: e.timestamp, mode: OrderingMode.desc)
          ])
          ..limit(limit))
        .get();
  }

  /// Trash: soft-deleted entries, newest deletion first.
  Future<List<HistoryEntry>> trashEntries({int limit = 100}) {
    return (select(historyEntries)
          ..where((e) => e.deletedAt.isNotNull())
          ..orderBy([
            (e) => OrderingTerm(expression: e.deletedAt, mode: OrderingMode.desc)
          ])
          ..limit(limit))
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

  /// Restore a soft-deleted entry from trash.
  Future<int> restoreEntry(String entryId) {
    return (update(historyEntries)..where((e) => e.id.equals(entryId)))
        .write(const HistoryEntriesCompanion(deletedAt: Value(null)));
  }

  /// Permanently delete a single entry.
  Future<int> permanentDeleteEntry(String entryId) {
    return (delete(historyEntries)..where((e) => e.id.equals(entryId))).go();
  }

  /// Permanently remove soft-deleted entries older than [days].
  Future<int> purgeTrash({int days = 30}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return (delete(historyEntries)
          ..where((e) => e.deletedAt.isNotNull() & e.deletedAt.isSmallerThanValue(cutoff)))
        .go();
  }

  /// Toggle archive status.
  Future<void> toggleArchive(String entryId) async {
    final entry = await (select(historyEntries)
          ..where((e) => e.id.equals(entryId)))
        .getSingleOrNull();
    if (entry == null) return;
    await (update(historyEntries)..where((e) => e.id.equals(entryId)))
        .write(HistoryEntriesCompanion(archived: Value(!entry.archived)));
  }

  /// Bulk soft-delete multiple entries.
  Future<void> softDeleteEntries(List<String> entryIds) async {
    await (update(historyEntries)..where((e) => e.id.isIn(entryIds)))
        .write(HistoryEntriesCompanion(deletedAt: Value(DateTime.now())));
  }

  /// Merge multiple entries into one. Keeps the oldest timestamp,
  /// concatenates content with dividers, combines tags.
  Future<HistoryEntry?> mergeEntries(List<String> entryIds) async {
    if (entryIds.length < 2) return null;
    final entries = await (select(historyEntries)
          ..where((e) => e.id.isIn(entryIds))
          ..orderBy([
            (e) => OrderingTerm(expression: e.timestamp, mode: OrderingMode.asc)
          ]))
        .get();
    if (entries.length < 2) return null;

    // Merge content
    final mergedContent =
        entries.map((e) => e.content.trim()).where((c) => c.isNotEmpty).join('\n\n---\n\n');

    // Merge tags (deduplicate)
    final allTags = <String>{};
    for (final e in entries) {
      // Tags are stored as JSON array string
      final raw = e.tags;
      if (raw.isNotEmpty && raw != '[]') {
        // Simple parse: strip brackets, split by comma
        for (final t in raw
            .replaceAll('[', '')
            .replaceAll(']', '')
            .replaceAll('"', '')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)) {
          allTags.add(t);
        }
      }
    }
    final tagsJson = allTags.isEmpty
        ? '[]'
        : '[${allTags.map((t) => '"$t"').join(',')}]';

    // Sum durations
    final totalDuration = entries.fold<double>(0, (s, e) => s + e.durationSec);

    // Use first entry as base, update it
    final base = entries.first;
    final companion = HistoryEntriesCompanion(
      id: Value(base.id),
      content: Value(mergedContent),
      title: Value('${base.title} (merged)'),
      timestamp: Value(base.timestamp),
      durationSec: Value(totalDuration),
      tags: Value(tagsJson),
      pinned: Value(entries.any((e) => e.pinned)),
    );
    await into(historyEntries).insertOnConflictUpdate(companion);

    // Soft-delete the other entries
    final otherIds = entryIds.where((id) => id != base.id).toList();
    await softDeleteEntries(otherIds);

    // Return the merged entry
    return (select(historyEntries)..where((e) => e.id.equals(base.id)))
        .getSingleOrNull();
  }

  /// Insert or update an entry.
  Future<void> upsertEntry(HistoryEntriesCompanion entry) {
    return into(historyEntries).insertOnConflictUpdate(entry);
  }

  /// Duplicate an entry with a new ID and "(copy)" title suffix.
  Future<HistoryEntry?> duplicateEntry(String entryId) async {
    final original = await (select(historyEntries)
          ..where((e) => e.id.equals(entryId)))
        .getSingleOrNull();
    if (original == null) return null;

    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final companion = HistoryEntriesCompanion(
      id: Value(newId),
      content: Value(original.content),
      title: Value('${original.title} (copy)'),
      timestamp: Value(DateTime.now()),
      durationSec: Value(original.durationSec),
      processingDurationSec: Value(original.processingDurationSec),
      language: Value(original.language),
      languageHint: Value(original.languageHint),
      tags: Value(original.tags),
      pinned: const Value(false),
      source: Value(original.source),
      model: Value(original.model),
      isLocal: Value(original.isLocal),
      costUsd: Value(original.costUsd),
      projectId: Value(original.projectId),
      archived: const Value(false),
      titleEdited: const Value(false),
    );
    await into(historyEntries).insert(companion);
    return (select(historyEntries)..where((e) => e.id.equals(newId)))
        .getSingleOrNull();
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

  /// Watch all non-deleted, non-archived entries as a live stream.
  Stream<List<HistoryEntry>> watchEntries({int limit = 100}) {
    return (select(historyEntries)
          ..where((e) => e.deletedAt.isNull() & e.archived.equals(false))
          ..orderBy([
            (e) => OrderingTerm(expression: e.timestamp, mode: OrderingMode.desc)
          ])
          ..limit(limit))
        .watch();
  }

  /// Watch archived entries.
  Stream<List<HistoryEntry>> watchArchived({int limit = 100}) {
    return (select(historyEntries)
          ..where((e) => e.archived.equals(true) & e.deletedAt.isNull())
          ..orderBy([
            (e) => OrderingTerm(expression: e.timestamp, mode: OrderingMode.desc)
          ])
          ..limit(limit))
        .watch();
  }

  /// Watch trash entries.
  Stream<List<HistoryEntry>> watchTrash({int limit = 100}) {
    return (select(historyEntries)
          ..where((e) => e.deletedAt.isNotNull())
          ..orderBy([
            (e) => OrderingTerm(expression: e.deletedAt, mode: OrderingMode.desc)
          ])
          ..limit(limit))
        .watch();
  }

  // ---------------------------------------------------------------------------
  // App settings
  // ---------------------------------------------------------------------------

  /// Reads all persisted app settings from the local key-value table.
  Future<Map<String, String>> readAppSettings() async {
    final rows = await customSelect(
      'SELECT key, value FROM app_settings',
    ).get();

    return {
      for (final row in rows)
        row.read<String>('key'): row.read<String>('value'),
    };
  }

  /// Writes the complete settings snapshot to the local key-value table.
  Future<void> writeAppSettings(Map<String, String> values) async {
    await transaction(() async {
      for (final entry in values.entries) {
        await customStatement(
          'INSERT INTO app_settings (key, value) VALUES (?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [entry.key, entry.value],
        );
      }
    });
  }

  /// Removes all persisted settings, causing the app to fall back to defaults.
  Future<void> resetAppSettings() {
    return customStatement('DELETE FROM app_settings');
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

  /// Watch notes for a specific entry as a live stream.
  Stream<List<EntryNote>> watchNotesForEntry(String entryId) {
    return (select(entryNotes)
          ..where((n) => n.entryId.equals(entryId))
          ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
        .watch();
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
