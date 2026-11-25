/// Health check and lossless rebuild of the derived indexes (#668): the
/// full-text search indexes of recordings, notes and snippets (#628) and the
/// preview index of [ContentMetadataIndex]. All are disposable: they are
/// dropped and refilled from the user tables, which are only ever read here.
library;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../logging/app_logger.dart';
import 'database_upgrade_interrupted_exception.dart';

/// Version of the search index layout. Bump it when the FTS columns, the
/// tokenizer or the triggers change: the next open then rebuilds the index
/// (silently, it is a planned change, not a repair).
const kSearchIndexVersion = 1;

/// `app_meta` key holding [kSearchIndexVersion] of the recordings index on
/// disk. The notes and snippets indexes have keys of their own
/// ([SearchIndexSpec.versionKey]), so adding them never rebuilt the
/// recordings index.
const kSearchIndexVersionKey = 'search_index_version';

/// `app_meta` key set when a search failed because an index is corrupt; the
/// next open rebuilds every search index.
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

/// One contentless FTS5 index over a user table (#628): [table] indexes
/// [columns] of [source] under the same names, keyed by the source rowid and
/// kept current by three triggers. Every index is derived and disposable.
@immutable
class SearchIndexSpec {
  const SearchIndexSpec({
    required this.table,
    required this.source,
    required this.columns,
    required this.rebuildOrder,
    this.versionKey,
    this.updateOf = false,
  });

  /// The FTS5 table, e.g. `notes_fts`.
  final String table;

  /// The user table it indexes, e.g. `notes`.
  final String source;

  /// Columns of [source], indexed under the same names.
  final List<String> columns;

  /// ORDER BY of the refill, newest first.
  final String rebuildOrder;

  /// `app_meta` key of this index's layout version. Null for `history_fts`,
  /// which keeps [kSearchIndexVersionKey] from #668. An index with its own
  /// key that was never built is a planned addition: it is built silently.
  final String? versionKey;

  /// Whether the update trigger fires only when an indexed column is written
  /// (`AFTER UPDATE OF ...`): a pin, a star or a usage count then leaves the
  /// index alone. `history_fts` keeps the trigger its migrations create.
  final bool updateOf;

  String get _metaKey => versionKey ?? kSearchIndexVersionKey;

  String get _cols => columns.join(', ');

  String _of(String row) => columns.map((c) => '$row.$c').join(', ');

  /// The names of the three sync triggers.
  List<String> get triggerNames => [
    '${table}_ai',
    '${table}_ad',
    '${table}_au',
  ];

  /// `CREATE VIRTUAL TABLE` of the index.
  String get createTable =>
      'CREATE VIRTUAL TABLE IF NOT EXISTS $table USING fts5('
      "$_cols, content='', tokenize='unicode61')";

  /// `CREATE TRIGGER` of the insert, delete and update triggers.
  List<String> get createTriggers => [
    'CREATE TRIGGER IF NOT EXISTS ${table}_ai AFTER INSERT ON $source '
        'BEGIN INSERT INTO $table(rowid, $_cols) '
        'VALUES (new.rowid, ${_of('new')}); END',
    'CREATE TRIGGER IF NOT EXISTS ${table}_ad AFTER DELETE ON $source '
        'BEGIN INSERT INTO $table($table, rowid, $_cols) '
        "VALUES ('delete', old.rowid, ${_of('old')}); END",
    'CREATE TRIGGER IF NOT EXISTS ${table}_au '
        'AFTER UPDATE${updateOf ? ' OF $_cols' : ''} ON $source '
        'BEGIN INSERT INTO $table($table, rowid, $_cols) '
        "VALUES ('delete', old.rowid, ${_of('old')}); "
        'INSERT INTO $table(rowid, $_cols) '
        "VALUES (new.rowid, ${_of('new')}); END",
  ];
}

/// The recordings index: the same table and columns the schema migrations
/// create; kept in sync by the rebuild test (search finds a new, an edited
/// and not a deleted entry).
const kHistorySearchIndex = SearchIndexSpec(
  table: 'history_fts',
  source: 'history_entries',
  columns: ['title', 'content', 'tags'],
  rebuildOrder: 'timestamp DESC, rowid DESC',
);

/// The notes index (#628): explicit title and Markdown text.
const kNotesSearchIndex = SearchIndexSpec(
  table: 'notes_fts',
  source: 'notes',
  columns: ['title', 'content'],
  rebuildOrder: 'updated_at DESC, rowid DESC',
  versionKey: 'notes_search_index_version',
  updateOf: true,
);

/// The snippets index (#628): title and text.
const kSnippetsSearchIndex = SearchIndexSpec(
  table: 'snippets_fts',
  source: 'snippets',
  columns: ['title', 'body'],
  rebuildOrder: 'created_at DESC, rowid DESC',
  versionKey: 'snippets_search_index_version',
  updateOf: true,
);

/// Every search index, recordings first.
const kSearchIndexes = <SearchIndexSpec>[
  kHistorySearchIndex,
  kNotesSearchIndex,
  kSnippetsSearchIndex,
];

/// Whether a failed search points at a broken search index rather than at
/// the query: SQLITE_CORRUPT (11) or a missing/unreadable FTS table.
bool isSearchIndexFailure(Object error) =>
    error is SqliteException &&
    !isTransientSqliteFailure(error) &&
    ((error.resultCode & 0xff) == 11 ||
        kSearchIndexes.any((index) => error.message.contains(index.table)));

typedef IndexWriter = Future<void> Function(Future<void> Function() action);

/// Reports the preview index fill: (dirty, total) documents.
typedef PreviewCounts = Future<(int, int)> Function();

/// Rows indexed per statement; progress is reported after each batch.
const _kBatch = 250;

/// The more serious of two states: what the user is told about wins.
SearchIndexState _worse(SearchIndexState a, SearchIndexState b) {
  int rank(SearchIndexState s) => switch (s) {
    SearchIndexState.healthy => 0,
    SearchIndexState.outdated => 1,
    SearchIndexState.missing => 2,
    SearchIndexState.damaged => 3,
  };
  return rank(b) > rank(a) ? b : a;
}

class IndexMaintenance {
  IndexMaintenance(this._db, this._write);

  final GeneratedDatabase _db;
  final IndexWriter _write;
  static final _log = AppLogger('IndexMaintenance');

  /// The most serious state of all search indexes, see [_inspect].
  Future<SearchIndexState> inspectSearchIndex() async {
    var worst = SearchIndexState.healthy;
    for (final spec in kSearchIndexes) {
      worst = _worse(worst, await _inspect(spec));
    }
    return worst;
  }

  /// Check every open: schema, document identities, layout version and FTS
  /// integrity. Matching counts can hide missing or orphaned documents; the FTS
  /// integrity check additionally detects damaged posting-list segments.
  /// SQLite checks the derived index without changing any source text.
  Future<SearchIndexState> _inspect(SearchIndexSpec spec) async {
    final wanted = [spec.table, ...spec.triggerNames];
    final names =
        (await _db
                .customSelect(
                  'SELECT name FROM sqlite_master WHERE name IN '
                  '(${wanted.map((n) => "'$n'").join(', ')})',
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    final version = await _meta(spec._metaKey);
    if (!names.contains(spec.table)) {
      // An index added by an update has never been built: that is planned.
      return spec.versionKey != null && version == null
          ? SearchIndexState.outdated
          : SearchIndexState.missing;
    }
    if (names.length != wanted.length) return SearchIndexState.damaged;
    if (await _meta(kSearchIndexDamagedKey) != null) {
      return SearchIndexState.damaged;
    }
    try {
      final counts = await _db.customSelect('''
        SELECT (SELECT COUNT(*) FROM ${spec.table}_docsize) AS indexed,
               (SELECT COUNT(*) FROM ${spec.source}) AS entries,
               EXISTS (
                 SELECT 1 FROM ${spec.table}_docsize AS indexed
                 LEFT JOIN ${spec.source} AS entry ON entry.rowid = indexed.id
                 WHERE entry.rowid IS NULL
               ) AS orphaned
      ''').getSingle();
      if (counts.read<int>('indexed') != counts.read<int>('entries') ||
          counts.read<int>('orphaned') != 0) {
        return SearchIndexState.damaged;
      }
      await _db.customStatement(
        "INSERT INTO ${spec.table}(${spec.table}) VALUES ('integrity-check')",
      );
    } on SqliteException catch (e) {
      // A locked/full disk is not evidence of corruption. Let the normal
      // opening error path handle it instead of dropping a healthy index.
      if (!isSearchIndexFailure(e)) rethrow;
      _log.warning('Search index ${spec.table} unreadable: $e');
      return SearchIndexState.damaged;
    }
    if (version == null) {
      // Indexes from before the version key are the current layout.
      await _setMeta(spec._metaKey, '$kSearchIndexVersion');
      return SearchIndexState.healthy;
    }
    return version == '$kSearchIndexVersion'
        ? SearchIndexState.healthy
        : SearchIndexState.outdated;
  }

  /// Without its search table the triggers make every write to the source
  /// table fail, even the opening repairs before [healSearchIndexOnOpen].
  /// They are derived, so they go; the heal still finds the index missing and
  /// rebuilds both.
  Future<void> dropOrphanSearchTriggers() async {
    for (final spec in kSearchIndexes) {
      final table = await _db
          .customSelect(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            variables: [Variable.withString(spec.table)],
          )
          .get();
      if (table.isNotEmpty) continue;
      for (final t in spec.triggerNames) {
        await _db.customStatement('DROP TRIGGER IF EXISTS $t');
      }
    }
  }

  /// Start-path self-heal. Returns the most serious state found; every index
  /// that was not [SearchIndexState.healthy] has been rebuilt when this
  /// returns, the healthy ones are left alone. Runs inside `beforeOpen`, so it
  /// writes directly (no writer queue yet).
  Future<SearchIndexState> healSearchIndexOnOpen() async {
    var worst = SearchIndexState.healthy;
    final stale = <SearchIndexSpec>[];
    for (final spec in kSearchIndexes) {
      final state = await _inspect(spec);
      if (state == SearchIndexState.healthy) continue;
      _log.info('Search index ${spec.table} ${state.name}: rebuilding on open');
      stale.add(spec);
      worst = _worse(worst, state);
    }
    if (stale.isEmpty) return worst;
    await _db.transaction(() => _rebuildSearch(stale, (_, _) {}));
    return worst;
  }

  /// Marks the search indexes as corrupt so the next open rebuilds them.
  Future<void> reportSearchIndexDamaged() =>
      _write(() => _setMeta(kSearchIndexDamagedKey, '1'));

  /// Rebuilds every search index (one transaction: a search never sees one
  /// half full, a save waits for it), then resets the preview index and waits
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
            kSearchIndexes,
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
    // Stop on a search failure: forwarding with yield* would also forward
    // the error but then continue rebuilding previews and report success.
    await for (final step in progress.stream) {
      yield step;
    }

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
        // The worker can retry in the background, but this rebuild did not
        // finish. Let the dialog announce failure instead of false success.
        _log.warning('Preview index stalled at $dirty of $total');
        throw TimeoutException('Preview index rebuild stalled', stall);
      }
      await Future<void>.delayed(poll);
    }
    yield const IndexRebuildProgress(IndexRebuildPhase.done, 1, 1);
  }

  /// Drops and refills [specs], newest rows first; progress counts the rows
  /// of all of them together. Must run inside a transaction. `DROP TABLE`
  /// removes the FTS shadow tables as well, so a corrupt index is replaced,
  /// not patched.
  Future<void> _rebuildSearch(
    List<SearchIndexSpec> specs,
    void Function(int done, int total) report,
  ) async {
    final rowIdsBySpec = <SearchIndexSpec, List<int>>{};
    for (final spec in specs) {
      rowIdsBySpec[spec] =
          (await _db
                  .customSelect(
                    'SELECT rowid AS r FROM ${spec.source} '
                    'ORDER BY ${spec.rebuildOrder}',
                  )
                  .get())
              .map((row) => row.read<int>('r'))
              .toList();
    }
    final total = rowIdsBySpec.values.fold<int>(0, (n, ids) => n + ids.length);
    var done = 0;
    report(0, total);
    for (final spec in specs) {
      for (final t in spec.triggerNames) {
        await _db.customStatement('DROP TRIGGER IF EXISTS $t');
      }
      await _db.customStatement('DROP TABLE IF EXISTS ${spec.table}');
      await _db.customStatement(spec.createTable);
      final rowIds = rowIdsBySpec[spec]!;
      final cols = spec.columns.join(', ');
      for (var i = 0; i < rowIds.length; i += _kBatch) {
        final batch = rowIds.sublist(i, (i + _kBatch).clamp(0, rowIds.length));
        await _db.customStatement('''
          INSERT INTO ${spec.table}(rowid, $cols)
          SELECT rowid, $cols FROM ${spec.source}
          WHERE rowid IN (${batch.join(',')})
        ''');
        done += batch.length;
        report(done, total);
      }
      for (final trigger in spec.createTriggers) {
        await _db.customStatement(trigger);
      }
      await _setMeta(spec._metaKey, '$kSearchIndexVersion');
    }
    if (specs.isNotEmpty) report(done, total);
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
