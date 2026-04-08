/// WhisPaste history database — drift database class.
///
/// Central database accessor for all history features.
/// Uses drift code generation — run `dart run build_runner build`
/// to generate the `.g.dart` file.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../services/path_service.dart' as paths;

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  HistoryEntries,
  Projects,
  DailyStats,
  EntryNotes,
  EntryAttachments,
  TextReplacements,
  Tags,
  EntryTags,
])
class HistoryDatabase extends _$HistoryDatabase {
  HistoryDatabase() : super(_openConnection());

  /// For testing — accepts an in-memory or custom executor.
  HistoryDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 4;

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
          if (from < 3) {
            await m.createTable(textReplacements);
          }
          if (from < 4) {
            await m.createTable(tags);
            await m.createTable(entryTags);
            await _recreateFtsWithTags();
            await _migrateJsonTags();
          }
        },
        beforeOpen: (details) async {
          // Reconcile Go-era schema if DB was created by the old Go backend
          // (column "text" instead of "content", TEXT timestamps instead of
          // INTEGER). Must run BEFORE any Drift queries touch the table.
          await _reconcileGoSchema();
          // One-time backfill: populate DailyStats from existing history
          // entries so that stats are correct for users upgrading from
          // a version that never wrote to DailyStats.
          await backfillDailyStats();
        },
      );

  /// Creates the FTS5 virtual table and triggers for full-text search.
  Future<void> _createFts(Migrator m) async {
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS history_fts USING fts5(
        title, content, tags,
        content='',
        tokenize='unicode61'
      )
    ''');

    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS history_fts_ai AFTER INSERT ON history_entries
      BEGIN
        INSERT INTO history_fts(rowid, title, content, tags)
        VALUES (new.rowid, new.title, new.content, new.tags);
      END
    ''');

    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS history_fts_ad AFTER DELETE ON history_entries
      BEGIN
        INSERT INTO history_fts(history_fts, rowid, title, content, tags)
        VALUES ('delete', old.rowid, old.title, old.content, old.tags);
      END
    ''');

    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS history_fts_au AFTER UPDATE ON history_entries
      BEGIN
        INSERT INTO history_fts(history_fts, rowid, title, content, tags)
        VALUES ('delete', old.rowid, old.title, old.content, old.tags);
        INSERT INTO history_fts(rowid, title, content, tags)
        VALUES (new.rowid, new.title, new.content, new.tags);
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

  /// Recreates FTS5 table and triggers with the tags column (v4 migration).
  Future<void> _recreateFtsWithTags() async {
    await customStatement('DROP TRIGGER IF EXISTS history_fts_ai');
    await customStatement('DROP TRIGGER IF EXISTS history_fts_ad');
    await customStatement('DROP TRIGGER IF EXISTS history_fts_au');
    await customStatement('DROP TABLE IF EXISTS history_fts');

    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS history_fts USING fts5(
        title, content, tags,
        content='',
        tokenize='unicode61'
      )
    ''');

    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS history_fts_ai AFTER INSERT ON history_entries
      BEGIN
        INSERT INTO history_fts(rowid, title, content, tags)
        VALUES (new.rowid, new.title, new.content, new.tags);
      END
    ''');

    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS history_fts_ad AFTER DELETE ON history_entries
      BEGIN
        INSERT INTO history_fts(history_fts, rowid, title, content, tags)
        VALUES ('delete', old.rowid, old.title, old.content, old.tags);
      END
    ''');

    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS history_fts_au AFTER UPDATE ON history_entries
      BEGIN
        INSERT INTO history_fts(history_fts, rowid, title, content, tags)
        VALUES ('delete', old.rowid, old.title, old.content, old.tags);
        INSERT INTO history_fts(rowid, title, content, tags)
        VALUES (new.rowid, new.title, new.content, new.tags);
      END
    ''');

    // Rebuild FTS index from existing data
    await customStatement('''
      INSERT INTO history_fts(rowid, title, content, tags)
      SELECT rowid, title, content, tags FROM history_entries
    ''');
  }

  /// Migrates JSON tag arrays on history_entries into normalized Tags/EntryTags.
  Future<void> _migrateJsonTags() async {
    final rows = await customSelect(
      "SELECT id, tags FROM history_entries WHERE tags != '[]' AND tags != ''",
    ).get();

    for (final row in rows) {
      final entryId = row.read<String>('id');
      final tagsJson = row.read<String>('tags');

      List<String> tagNames;
      try {
        final decoded = jsonDecode(tagsJson);
        if (decoded is List) {
          tagNames = decoded.cast<String>();
        } else {
          continue;
        }
      } catch (_) {
        continue;
      }

      for (final name in tagNames) {
        final normalized = name.toLowerCase().trim();
        if (normalized.isEmpty) continue;

        final tag = await createTag(normalized);
        await tagEntry(entryId, tag.id);
      }
    }
  }

  /// Safety net: if the DB has Go-era schema (column "text" instead of
  /// "content", TEXT timestamps instead of INTEGER), reconcile it to match
  /// the Drift-expected schema.
  Future<void> _reconcileGoSchema() async {
    final cols =
        await customSelect("PRAGMA table_info('history_entries')").get();
    final colNames = cols.map((r) => r.data['name'] as String).toSet();

    if (!colNames.contains('text') || colNames.contains('content')) return;

    debugPrint('Reconciling Go-era schema: "text" → "content"');
    await customStatement(
      'ALTER TABLE history_entries RENAME COLUMN "text" TO "content"',
    );
    // Go stored ISO 8601 TEXT timestamps; Drift expects Unix epoch integers.
    await customStatement('''
      UPDATE history_entries
      SET timestamp = CAST(strftime('%s', timestamp) AS INTEGER)
      WHERE typeof(timestamp) = 'text'
    ''');
    // Recreate FTS triggers (they reference the "content" column name).
    await _recreateFtsWithTags();
    debugPrint('Go-era schema reconciliation complete');
  }

  // ---------------------------------------------------------------------------
  // Query helpers
  // ---------------------------------------------------------------------------

  /// All non-deleted, non-archived entries, pinned first then newest.
  Future<List<HistoryEntry>> allEntries({int limit = 100, int offset = 0}) {
    return (select(historyEntries)
          ..where((e) => e.deletedAt.isNull() & e.archived.equals(false))
          ..orderBy([
            (e) => OrderingTerm(expression: e.pinned, mode: OrderingMode.desc),
            (e) => OrderingTerm(expression: e.timestamp, mode: OrderingMode.desc),
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

  /// Full-text search via FTS5 with query sanitization.
  Future<List<HistoryEntry>> searchEntries(String query) async {
    final sanitized = _sanitizeFtsQuery(query);
    if (sanitized.isEmpty) return [];

    try {
      final ftsResults = await customSelect(
        'SELECT rowid FROM history_fts WHERE history_fts MATCH ?',
        variables: [Variable.withString(sanitized)],
      ).get();

      if (ftsResults.isEmpty) return [];

      final rowIds = ftsResults.map((r) => r.read<int>('rowid')).toList();
      return (select(historyEntries)
            ..where((e) => e.rowId.isIn(rowIds) & e.deletedAt.isNull())
            ..orderBy([
              (e) => OrderingTerm(expression: e.pinned, mode: OrderingMode.desc),
              (e) =>
                  OrderingTerm(expression: e.timestamp, mode: OrderingMode.desc),
            ]))
          .get();
    } catch (_) {
      return [];
    }
  }

  /// Escapes special FTS5 characters and converts to a prefix query.
  static String _sanitizeFtsQuery(String query) {
    final cleaned = query
        .replaceAll(RegExp(r'[*"()+\-^{}~:\\/]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '';
    final terms = cleaned.split(' ').where((t) => t.isNotEmpty).toList();
    if (terms.isEmpty) return '';
    return terms.map((t) => '"$t"*').join(' ');
  }

  /// Get a single entry by ID (or null if not found).
  Future<HistoryEntry?> getEntry(String entryId) {
    return (select(historyEntries)..where((e) => e.id.equals(entryId)))
        .getSingleOrNull();
  }

  /// Partial update of an existing entry (only writes provided fields).
  Future<int> updateEntry(String entryId, HistoryEntriesCompanion companion) {
    return (update(historyEntries)..where((e) => e.id.equals(entryId)))
        .write(companion);
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

  /// Permanently remove ALL soft-deleted entries (empty trash).
  Future<int> emptyTrash() {
    return (delete(historyEntries)..where((e) => e.deletedAt.isNotNull()))
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

    // Mark as merged via tag (not title suffix)
    allTags.add('merged');

    // Use first entry as base, update it
    final base = entries.first;
    final companion = HistoryEntriesCompanion(
      id: Value(base.id),
      content: Value(mergedContent),
      title: Value(base.title),
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
  // Tags — normalized tag CRUD
  // ---------------------------------------------------------------------------

  /// Creates a tag with the given name (lowercased). Returns existing if duplicate.
  Future<Tag> createTag(String name) async {
    final normalized = name.toLowerCase().trim();
    final existing = await (select(tags)
          ..where((t) => t.name.equals(normalized)))
        .getSingleOrNull();
    if (existing != null) return existing;

    final id = _uuid();
    final now = DateTime.now();
    await into(tags).insert(TagsCompanion.insert(
      id: id,
      name: normalized,
      createdAt: now,
    ));
    return Tag(id: id, name: normalized, createdAt: now);
  }

  /// Deletes a tag and all its entry links.
  Future<void> deleteTag(String tagId) async {
    await (delete(entryTags)..where((et) => et.tagId.equals(tagId))).go();
    await (delete(tags)..where((t) => t.id.equals(tagId))).go();
  }

  /// Renames a tag (lowercased). Fails silently if new name already exists.
  Future<void> renameTag(String tagId, String newName) async {
    final normalized = newName.toLowerCase().trim();
    final existing = await (select(tags)
          ..where((t) => t.name.equals(normalized)))
        .getSingleOrNull();
    if (existing != null && existing.id != tagId) return;

    await (update(tags)..where((t) => t.id.equals(tagId)))
        .write(TagsCompanion(name: Value(normalized)));
  }

  /// All tags, alphabetically.
  Future<List<Tag>> allTags() {
    return (select(tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  }

  /// Tags for a specific entry (via join).
  Future<List<Tag>> tagsForEntry(String entryId) async {
    final query = select(tags).join([
      innerJoin(entryTags, entryTags.tagId.equalsExp(tags.id)),
    ])
      ..where(entryTags.entryId.equals(entryId))
      ..orderBy([OrderingTerm.asc(tags.name)]);
    final rows = await query.get();
    return rows.map((r) => r.readTable(tags)).toList();
  }

  /// Reactive stream of tags for a specific entry.
  Stream<List<Tag>> watchTagsForEntry(String entryId) {
    final query = select(tags).join([
      innerJoin(entryTags, entryTags.tagId.equalsExp(tags.id)),
    ])
      ..where(entryTags.entryId.equals(entryId))
      ..orderBy([OrderingTerm.asc(tags.name)]);
    return query.watch().map(
          (rows) => rows.map((r) => r.readTable(tags)).toList(),
        );
  }

  /// Most-used tags by entry count.
  Future<List<Tag>> frequentTags({int limit = 10}) async {
    final count = entryTags.tagId.count();
    final query = select(tags).join([
      innerJoin(entryTags, entryTags.tagId.equalsExp(tags.id)),
    ])
      ..groupBy([tags.id, tags.name, tags.createdAt])
      ..orderBy([OrderingTerm.desc(count)])
      ..limit(limit);
    final rows = await query.get();
    return rows.map((r) => r.readTable(tags)).toList();
  }

  /// Prefix search for tag autocomplete.
  Future<List<Tag>> searchTags(String prefix) {
    final normalized = prefix.toLowerCase().trim();
    return (select(tags)
          ..where((t) => t.name.like('$normalized%'))
          ..orderBy([(t) => OrderingTerm.asc(t.name)])
          ..limit(20))
        .get();
  }

  /// Link an entry to a tag.
  Future<void> tagEntry(String entryId, String tagId) {
    return into(entryTags).insert(
      EntryTagsCompanion.insert(entryId: entryId, tagId: tagId),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Remove a tag from an entry.
  Future<void> untagEntry(String entryId, String tagId) {
    return (delete(entryTags)
          ..where(
              (et) => et.entryId.equals(entryId) & et.tagId.equals(tagId)))
        .go();
  }

  /// Generates a v4 UUID without external dependencies.
  static String _uuid() {
    final r = Random.secure();
    final bytes = List.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
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

  /// Removes all accumulated daily analytics stats.
  Future<void> resetDailyStats() {
    return delete(dailyStats).go();
  }

  // ---------------------------------------------------------------------------
  // Text Replacements (voice shortcuts)
  // ---------------------------------------------------------------------------

  Future<List<TextReplacement>> readAllReplacements() =>
      select(textReplacements).get();

  Stream<List<TextReplacement>> watchAllReplacements() =>
      select(textReplacements).watch();

  Future<void> upsertReplacement(TextReplacementsCompanion entry) =>
      into(textReplacements).insertOnConflictUpdate(entry);

  Future<void> deleteReplacement(String id) =>
      (delete(textReplacements)..where((t) => t.id.equals(id))).go();

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

  /// Partial update of an existing note (only writes provided fields).
  Future<int> updateNoteFields(String noteId, EntryNotesCompanion companion) {
    return (update(entryNotes)..where((n) => n.id.equals(noteId)))
        .write(companion);
  }

  Future<int> deleteNote(String noteId) {
    return (delete(entryNotes)..where((n) => n.id.equals(noteId))).go();
  }

  // ---------------------------------------------------------------------------
  // DailyStats — persistent analytics (independent of history CRUD)
  // ---------------------------------------------------------------------------

  /// Record a completed transcription in the DailyStats table.
  ///
  /// Uses upsert (INSERT OR UPDATE) keyed on (date, model, isLocal).
  /// This is the ONLY write path for analytics — deleting history entries
  /// does NOT affect these counters.
  Future<void> recordDailyStat({
    required DateTime timestamp,
    required String model,
    required bool isLocal,
    required double durationSec,
    required double processingDurationSec,
    required int wordCount,
    required double costUsd,
  }) async {
    final dateStr = _dateKey(timestamp);
    final bucket = _durationBucket(durationSec);

    await into(dailyStats).insert(
      DailyStatsCompanion(
        date: Value(dateStr),
        model: Value(model.isEmpty ? 'unknown' : model),
        isLocal: Value(isLocal),
        count: const Value(1),
        totalDurationSec: Value(durationSec),
        totalProcessingSec: Value(processingDurationSec),
        totalWords: Value(wordCount),
        totalCostUsd: Value(costUsd),
        durUnder15s: Value(bucket == 0 ? 1 : 0),
        dur15To30s: Value(bucket == 1 ? 1 : 0),
        dur30To60s: Value(bucket == 2 ? 1 : 0),
        dur1To3m: Value(bucket == 3 ? 1 : 0),
        durOver3m: Value(bucket == 4 ? 1 : 0),
      ),
      onConflict: DoUpdate(
        (old) => DailyStatsCompanion.custom(
          count: dailyStats.count + const Constant(1),
          totalDurationSec:
              dailyStats.totalDurationSec + Variable(durationSec),
          totalProcessingSec:
              dailyStats.totalProcessingSec + Variable(processingDurationSec),
          totalWords: dailyStats.totalWords + Variable(wordCount),
          totalCostUsd: dailyStats.totalCostUsd + Variable(costUsd),
          durUnder15s:
              dailyStats.durUnder15s + Variable(bucket == 0 ? 1 : 0),
          dur15To30s:
              dailyStats.dur15To30s + Variable(bucket == 1 ? 1 : 0),
          dur30To60s:
              dailyStats.dur30To60s + Variable(bucket == 2 ? 1 : 0),
          dur1To3m: dailyStats.dur1To3m + Variable(bucket == 3 ? 1 : 0),
          durOver3m:
              dailyStats.durOver3m + Variable(bucket == 4 ? 1 : 0),
        ),
        target: [dailyStats.date, dailyStats.model, dailyStats.isLocal],
      ),
    );
  }

  /// Backfill DailyStats from existing HistoryEntries (one-time migration).
  Future<void> backfillDailyStats() async {
    // Check if DailyStats already has data — skip if already backfilled.
    final existing = await (selectOnly(dailyStats)
          ..addColumns([dailyStats.count.sum()]))
        .getSingle();
    final existingCount = existing.read(dailyStats.count.sum()) ?? 0;
    if (existingCount > 0) return;

    // Read ALL history entries (including deleted/archived) for backfill.
    final entries = await select(historyEntries).get();
    for (final e in entries) {
      final words =
          e.content.trim().isEmpty ? 0 : e.content.trim().split(RegExp(r'\s+')).length;
      await recordDailyStat(
        timestamp: e.timestamp,
        model: e.model,
        isLocal: e.isLocal,
        durationSec: e.durationSec,
        processingDurationSec: e.processingDurationSec,
        wordCount: words,
        costUsd: e.costUsd,
      );
    }
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static int _durationBucket(double sec) {
    if (sec < 15) return 0;
    if (sec < 30) return 1;
    if (sec < 60) return 2;
    if (sec < 180) return 3;
    return 4;
  }

  // ---------------------------------------------------------------------------
  // Analytics queries — read from DailyStats (history-independent)
  // ---------------------------------------------------------------------------

  /// Total number of recordings ever made.
  Future<int> analyticsEntryCount({DateTime? since}) async {
    final total = dailyStats.count.sum();
    final q = selectOnly(dailyStats)..addColumns([total]);
    if (since != null) {
      q.where(dailyStats.date
          .isBiggerOrEqualValue(_dateKey(since)));
    }
    final row = await q.getSingle();
    return row.read(total) ?? 0;
  }

  /// Sum of recording duration in seconds.
  Future<double> analyticsTotalDurationSec({DateTime? since}) async {
    final total = dailyStats.totalDurationSec.sum();
    final q = selectOnly(dailyStats)..addColumns([total]);
    if (since != null) {
      q.where(dailyStats.date
          .isBiggerOrEqualValue(_dateKey(since)));
    }
    final row = await q.getSingle();
    return row.read(total) ?? 0.0;
  }

  /// Total word count across all recordings.
  Future<int> analyticsTotalWords({DateTime? since}) async {
    final total = dailyStats.totalWords.sum();
    final q = selectOnly(dailyStats)..addColumns([total]);
    if (since != null) {
      q.where(dailyStats.date
          .isBiggerOrEqualValue(_dateKey(since)));
    }
    final row = await q.getSingle();
    return row.read(total) ?? 0;
  }

  /// Total cloud cost in USD.
  Future<double> analyticsTotalCostUsd({DateTime? since}) async {
    final total = dailyStats.totalCostUsd.sum();
    final q = selectOnly(dailyStats)..addColumns([total]);
    if (since != null) {
      q.where(dailyStats.date
          .isBiggerOrEqualValue(_dateKey(since)));
    }
    final row = await q.getSingle();
    return row.read(total) ?? 0.0;
  }

  /// Estimated savings: sum durationSec of local entries × rate/min.
  Future<double> analyticsLocalSavingsUsd({
    DateTime? since,
    double ratePerMinute = 0.006,
  }) async {
    final total = dailyStats.totalDurationSec.sum();
    final q = selectOnly(dailyStats)..addColumns([total]);
    q.where(dailyStats.isLocal.equals(true));
    if (since != null) {
      q.where(dailyStats.date
          .isBiggerOrEqualValue(_dateKey(since)));
    }
    final row = await q.getSingle();
    final totalSec = row.read(total) ?? 0.0;
    return (totalSec / 60.0) * ratePerMinute;
  }

  /// Per-model usage stats.
  Future<List<AnalyticsModelUsage>> analyticsModelUsage({
    DateTime? since,
  }) async {
    final cnt = dailyStats.count.sum();
    final q = selectOnly(dailyStats)
      ..addColumns([dailyStats.model, cnt])
      ..groupBy([dailyStats.model])
      ..orderBy([OrderingTerm.desc(cnt)]);
    if (since != null) {
      q.where(dailyStats.date
          .isBiggerOrEqualValue(_dateKey(since)));
    }
    final rows = await q.get();
    final total = rows.fold<int>(0, (s, r) => s + (r.read(cnt) ?? 0));
    return rows.map((r) {
      final name = r.read(dailyStats.model) ?? '';
      final count = r.read(cnt) ?? 0;
      return AnalyticsModelUsage(
        model: name.isEmpty ? 'Unknown' : name,
        count: count,
        fraction: total > 0 ? count / total : 0.0,
      );
    }).toList();
  }

  /// Recordings per day-of-week (0=Monday … 6=Sunday) for the last 7 days.
  ///
  /// Uses DailyStats date strings to derive day-of-week.
  Future<List<double>> analyticsWeeklyActivity() async {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final sinceStr = _dateKey(weekAgo);

    final cnt = dailyStats.count.sum();
    final q = selectOnly(dailyStats)
      ..addColumns([dailyStats.date, cnt])
      ..groupBy([dailyStats.date]);
    q.where(dailyStats.date.isBiggerOrEqualValue(sinceStr));
    final rows = await q.get();

    final counts = List.filled(7, 0.0);
    for (final r in rows) {
      final dateStr = r.read(dailyStats.date);
      if (dateStr == null) continue;
      final dt = DateTime.tryParse(dateStr);
      if (dt == null) continue;
      final idx = dt.weekday - 1; // 0-based Mon..Sun
      counts[idx] += (r.read(cnt) ?? 0).toDouble();
    }
    return counts;
  }

  /// Duration distribution buckets: [<15s, 15-30s, 30-60s, 1-3m, >3m].
  Future<List<int>> analyticsDurationBuckets({DateTime? since}) async {
    final cols = [
      dailyStats.durUnder15s.sum(),
      dailyStats.dur15To30s.sum(),
      dailyStats.dur30To60s.sum(),
      dailyStats.dur1To3m.sum(),
      dailyStats.durOver3m.sum(),
    ];
    final q = selectOnly(dailyStats)..addColumns(cols);
    if (since != null) {
      q.where(dailyStats.date
          .isBiggerOrEqualValue(_dateKey(since)));
    }
    final row = await q.getSingle();
    return [
      row.read(cols[0]) ?? 0,
      row.read(cols[1]) ?? 0,
      row.read(cols[2]) ?? 0,
      row.read(cols[3]) ?? 0,
      row.read(cols[4]) ?? 0,
    ];
  }
}

// ---------------------------------------------------------------------------
// Analytics data classes
// ---------------------------------------------------------------------------

/// Model usage row for analytics.
class AnalyticsModelUsage {
  const AnalyticsModelUsage({
    required this.model,
    required this.count,
    required this.fraction,
  });

  final String model;
  final int count;
  final double fraction;
}

// ---------------------------------------------------------------------------
// Connection factory
// ---------------------------------------------------------------------------

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = Directory(paths.appDataDir());
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await _migrateFromNestedPath(dir.path);
    final file = File(p.join(dir.path, 'history.db'));
    return NativeDatabase.createInBackground(file);
  });
}

/// One-time migration: move history.db from the old double-nested
/// `%APPDATA%\WhisPaste\WhisPaste\` path to the correct single-level
/// `%APPDATA%\WhisPaste\` path. If a Go-era DB already occupies the
/// target, back it up and prefer the Flutter DB (correct Drift schema).
Future<void> _migrateFromNestedPath(String correctDir) async {
  if (!Platform.isWindows) return;
  final nestedDb = File(p.join(correctDir, 'WhisPaste', 'history.db'));
  if (!nestedDb.existsSync()) return;

  final targetDb = File(p.join(correctDir, 'history.db'));
  try {
    // If a DB already exists at the target (likely Go-era), back it up.
    if (targetDb.existsSync()) {
      final backup = File(p.join(correctDir, 'history.db.pre-migration'));
      await targetDb.copy(backup.path);
      await targetDb.delete();
      for (final suffix in ['-wal', '-shm']) {
        final f = File('${targetDb.path}$suffix');
        if (f.existsSync()) await f.delete();
      }
    }

    // Copy Flutter DB from nested path.
    await nestedDb.copy(targetDb.path);
    for (final suffix in ['-wal', '-shm']) {
      final src = File('${nestedDb.path}$suffix');
      if (src.existsSync()) await src.copy('${targetDb.path}$suffix');
    }

    // Remove old nested directory (best-effort).
    try {
      await Directory(p.join(correctDir, 'WhisPaste'))
          .delete(recursive: true);
    } catch (_) {}

    debugPrint('DB migrated from nested WhisPaste/WhisPaste/ path');
  } catch (e) {
    debugPrint('DB migration failed (will use existing location): $e');
  }
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
