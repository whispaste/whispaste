/// Health check and lossless rebuild of the derived indexes (#668): the
/// full-text search index `history_fts` and the preview index of
/// [ContentMetadataIndex]. Both are disposable: they are dropped and refilled
/// from the user tables, which are only ever read here.
library;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../logging/app_logger.dart';

/// Version of the search index layout. Bump it when the FTS columns, the
/// tokenizer or the triggers change: the next open then rebuilds the index
/// (silently, it is a planned change, not a repair).
const kSearchIndexVersion = 1;

/// `app_meta` key holding [kSearchIndexVersion] of the index on disk.
const kSearchIndexVersionKey = 'search_index_version';

/// `app_meta` key set when a search failed because the index is corrupt; the
/// next open rebuilds it.
const kSearchIndexDamagedKey = 'search_index_damaged';

/// What [IndexMaintenance.inspectSearchIndex] found.
enum SearchIndexState { healthy, missing, damaged, outdated }

/// Which index a rebuild is filling.
enum IndexRebuildPhase { search, preview, done }

/// Progress of [IndexMaintenance.rebuild]; [done] of [total] items of [phase].
@immutable
class IndexRebuildProgress {
  const IndexRebuildProgress(this.phase, this.done, this.total);

  final IndexRebuildPhase phase;
  final int done;
  final int total;

  /// 0..1, or null while the total is unknown.
  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is IndexRebuildProgress &&
      other.phase == phase &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(phase, done, total);
}

/// Whether a failed search points at a broken search index rather than at
/// the query: SQLITE_CORRUPT (11) or a missing/unreadable FTS table.
bool isSearchIndexFailure(Object error) =>
    error is SqliteException &&
    ((error.resultCode & 0xff) == 11 || error.message.contains('history_fts'));

typedef IndexWriter = Future<void> Function(Future<void> Function() action);

/// Reports the preview index fill: (dirty, total) documents.
typedef PreviewCounts = Future<(int, int)> Function();

/// Rows indexed per statement; progress is reported after each batch.
const _kBatch = 250;

const _ftsTable = '''
  CREATE VIRTUAL TABLE IF NOT EXISTS history_fts USING fts5(
    title, content, tags,
    content='',
    tokenize='unicode61'
  )
''';

// Same triggers as the schema migrations create; kept in sync by the
// rebuild test (search finds a new, an edited and not a deleted entry).
const _ftsTriggers = [
  '''
  CREATE TRIGGER IF NOT EXISTS history_fts_ai AFTER INSERT ON history_entries
  BEGIN
    INSERT INTO history_fts(rowid, title, content, tags)
    VALUES (new.rowid, new.title, new.content, new.tags);
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS history_fts_ad AFTER DELETE ON history_entries
  BEGIN
    INSERT INTO history_fts(history_fts, rowid, title, content, tags)
    VALUES ('delete', old.rowid, old.title, old.content, old.tags);
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS history_fts_au AFTER UPDATE ON history_entries
  BEGIN
    INSERT INTO history_fts(history_fts, rowid, title, content, tags)
    VALUES ('delete', old.rowid, old.title, old.content, old.tags);
    INSERT INTO history_fts(rowid, title, content, tags)
    VALUES (new.rowid, new.title, new.content, new.tags);
  END
  ''',
];

class IndexMaintenance {
  IndexMaintenance(this._db, this._write);

  final GeneratedDatabase _db;
  final IndexWriter _write;
  static final _log = AppLogger('IndexMaintenance');

  /// Cheap check for every open: the table and its three triggers exist, the
  /// layout version matches, no search reported corruption, and the index
  /// holds one document per entry. A full FTS integrity check would read the
  /// whole index on the start path, so it is left to the manual rebuild.
  Future<SearchIndexState> inspectSearchIndex() async {
    final names =
        (await _db
                .customSelect(
                  'SELECT name FROM sqlite_master WHERE name IN '
                  "('history_fts', 'history_fts_ai', 'history_fts_ad', 'history_fts_au')",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    if (!names.contains('history_fts')) return SearchIndexState.missing;
    if (names.length != 4) return SearchIndexState.damaged;
    if (await _meta(kSearchIndexDamagedKey) != null) {
      return SearchIndexState.damaged;
    }
    try {
      final counts = await _db.customSelect('''
        SELECT (SELECT COUNT(*) FROM history_fts_docsize) AS indexed,
               (SELECT COUNT(*) FROM history_entries) AS entries
      ''').getSingle();
      if (counts.read<int>('indexed') != counts.read<int>('entries')) {
        return SearchIndexState.damaged;
      }
    } on Object catch (e) {
      _log.warning('Search index unreadable: $e');
      return SearchIndexState.damaged;
    }
    final version = await _meta(kSearchIndexVersionKey);
    if (version == null) {
      // Indexes from before the version key are the current layout.
      await _setMeta(kSearchIndexVersionKey, '$kSearchIndexVersion');
      return SearchIndexState.healthy;
    }
    return version == '$kSearchIndexVersion'
        ? SearchIndexState.healthy
        : SearchIndexState.outdated;
  }

  /// Without the search table its triggers make every write to
  /// `history_entries` fail, even the opening repairs before
  /// [healSearchIndexOnOpen]. They are derived, so they go; the heal still
  /// finds the index missing and rebuilds both.
  Future<void> dropOrphanSearchTriggers() async {
    final table = await _db
        .customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'history_fts'",
        )
        .get();
    if (table.isNotEmpty) return;
    for (final t in ['history_fts_ai', 'history_fts_ad', 'history_fts_au']) {
      await _db.customStatement('DROP TRIGGER IF EXISTS $t');
    }
  }

  /// Start-path self-heal. Returns the state found; anything but
  /// [SearchIndexState.healthy] has been rebuilt when this returns. Runs
  /// inside `beforeOpen`, so it writes directly (no writer queue yet).
  Future<SearchIndexState> healSearchIndexOnOpen() async {
    final state = await inspectSearchIndex();
    if (state == SearchIndexState.healthy) return state;
    _log.info('Search index ${state.name}: rebuilding on open');
    await _db.transaction(() => _rebuildSearch((_, _) {}));
    return state;
  }

  /// Marks the search index as corrupt so the next open rebuilds it.
  Future<void> reportSearchIndexDamaged() =>
      _write(() => _setMeta(kSearchIndexDamagedKey, '1'));

  /// Rebuilds the search index (one transaction: a search never sees it half
  /// full, a save waits for it), then resets the preview index and waits
  /// while its worker refills it. The user tables are only read.
  Stream<IndexRebuildProgress> rebuild({
    required Future<void> Function() resetPreview,
    required PreviewCounts previewCounts,
    Duration poll = const Duration(milliseconds: 200),
    Duration stall = const Duration(seconds: 15),
  }) async* {
    final progress = StreamController<IndexRebuildProgress>();
    unawaited(
      _write(
        () => _db.transaction(
          () => _rebuildSearch(
            (done, total) => progress.add(
              IndexRebuildProgress(IndexRebuildPhase.search, done, total),
            ),
          ),
        ),
      ).then(
        (_) => progress.close(),
        onError: (Object e, StackTrace st) {
          progress
            ..addError(e, st)
            ..close();
        },
      ),
    );
    yield* progress.stream;

    await resetPreview();
    var last = -1;
    var unchangedSince = DateTime.now();
    while (true) {
      final (dirty, total) = await previewCounts();
      yield IndexRebuildProgress(
        IndexRebuildPhase.preview,
        total - dirty,
        total,
      );
      if (dirty == 0) break;
      if (dirty != last) {
        last = dirty;
        unchangedSince = DateTime.now();
      } else if (DateTime.now().difference(unchangedSince) > stall) {
        // The worker defers on errors and retries on the next change; the
        // previews then fill in the background, nothing is lost.
        _log.warning('Preview index stalled at $dirty of $total');
        break;
      }
      await Future<void>.delayed(poll);
    }
    yield const IndexRebuildProgress(IndexRebuildPhase.done, 1, 1);
  }

  /// Drops and refills `history_fts`, newest entries first. Must run inside
  /// a transaction. `DROP TABLE` removes the FTS shadow tables as well, so a
  /// corrupt index is replaced, not patched.
  Future<void> _rebuildSearch(void Function(int done, int total) report) async {
    for (final t in ['history_fts_ai', 'history_fts_ad', 'history_fts_au']) {
      await _db.customStatement('DROP TRIGGER IF EXISTS $t');
    }
    await _db.customStatement('DROP TABLE IF EXISTS history_fts');
    await _db.customStatement(_ftsTable);
    final rowIds =
        (await _db
                .customSelect(
                  'SELECT rowid AS r FROM history_entries ORDER BY timestamp DESC, rowid DESC',
                )
                .get())
            .map((row) => row.read<int>('r'))
            .toList();
    report(0, rowIds.length);
    for (var i = 0; i < rowIds.length; i += _kBatch) {
      final batch = rowIds.sublist(i, (i + _kBatch).clamp(0, rowIds.length));
      await _db.customStatement('''
        INSERT INTO history_fts(rowid, title, content, tags)
        SELECT rowid, title, content, tags FROM history_entries
        WHERE rowid IN (${batch.join(',')})
      ''');
      report(i + batch.length, rowIds.length);
    }
    for (final trigger in _ftsTriggers) {
      await _db.customStatement(trigger);
    }
    await _setMeta(kSearchIndexVersionKey, '$kSearchIndexVersion');
    await _db.customStatement('DELETE FROM app_meta WHERE key = ?', [
      kSearchIndexDamagedKey,
    ]);
  }

  Future<String?> _meta(String key) async {
    final rows = await _db
        .customSelect(
          'SELECT value FROM app_meta WHERE key = ?',
          variables: [Variable.withString(key)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  Future<void> _setMeta(String key, String value) => _db.customStatement(
    'INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)',
    [key, value],
  );
}
