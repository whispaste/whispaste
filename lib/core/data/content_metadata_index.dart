/// Background index of saved content. SQL triggers mark work atomically with
/// every write (including imports/restores); no save ever waits for parsing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart';

import '../logging/app_logger.dart';
import 'content_metadata.dart';

export 'content_metadata.dart';

typedef MetadataWriter = Future<void> Function(Future<void> Function() action);

typedef _EncodedMetadata = ({String payload, String digest});

class ContentMetadataIndex {
  ContentMetadataIndex(this._db, this._write);

  final GeneratedDatabase _db;
  final MetadataWriter _write;
  final _changes = StreamController<ContentKey?>.broadcast();
  final _visible = <ContentKey>{};
  final _watching = <ContentKey, int>{};
  final _recent = <String, _EncodedMetadata>{};
  final _pending = <String, Future<_EncodedMetadata>>{};
  StreamSubscription<Set<TableUpdate>>? _subscription;
  Timer? _timer;
  Future<void>? _running;
  bool _closed = false;
  bool _initialized = false;
  bool _wakeAgain = false;
  static final _log = AppLogger('ContentMetadataIndex');

  /// A disposable cache has its own version, independent of the user-data
  /// schema. IF NOT EXISTS also repairs a missing cache on the next open.
  /// Database-only work, safe inside the upgrade transaction.
  Future<void> prepareSchema() async {
    await _repairShape('content_metadata_cache', {'hash', 'payload', 'digest'});
    await _repairShape('content_metadata_documents', {
      'kind',
      'id',
      'hash',
      'dirty',
    });
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS content_metadata_cache (
        hash TEXT PRIMARY KEY, payload TEXT NOT NULL, digest TEXT NOT NULL
      )
    ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS content_metadata_documents (
        kind TEXT NOT NULL, id TEXT NOT NULL, hash TEXT,
        dirty INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (kind, id)
      )
    ''');
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_metadata_dirty ON content_metadata_documents(dirty)',
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_metadata_hash ON content_metadata_documents(hash)',
    );
    for (final kind in ContentKind.values) {
      await _installSource(kind);
    }
    // Validate persisted payloads incrementally, never on the opening path.
    await _db.customStatement(
      'UPDATE content_metadata_documents SET dirty = 1',
    );
    await _sweep();
  }

  /// Attach to the normal database connection after the upgrade commits.
  void startObserving() {
    if (_initialized || _closed) return;
    _initialized = true;
    _subscription = _db.tableUpdates().listen((updates) {
      if (updates.any((u) => _sourceTables.contains(u.table))) {
        if (updates.any((u) => u.kind == null || u.kind == UpdateKind.delete)) {
          _recent.clear();
        }
        _changes.add(null);
        _wake();
      }
    });
    _wake();
  }

  /// The named way to rebuild the disposable cache (#676): every derived
  /// row is dropped and recomputed in the background from the user data.
  /// Never touches note, recording or snippet text.
  Future<void> rebuildDisposableCache() async {
    if (_closed || !_initialized) return;
    await _write(
      () => _db.transaction(() async {
        await _db.customStatement(
          'UPDATE content_metadata_documents SET hash = NULL, dirty = 1',
        );
        await _db.customStatement('DELETE FROM content_metadata_cache');
      }),
    );
    _recent.clear();
    _changes.add(null);
    _wake();
  }

  Future<void> _repairShape(String table, Set<String> columns) async {
    final rows = await _db.customSelect('PRAGMA table_info($table)').get();
    if (rows.isEmpty) return;
    final actual = rows.map((row) => row.read<String>('name')).toSet();
    if (actual.length != columns.length || !actual.containsAll(columns)) {
      // Only these two disposable tables are ever passed here. User tables
      // and their authoritative text are never repaired by the index.
      await _db.customStatement('DROP TABLE $table');
    }
  }

  /// Drops every derived preview and queues all documents again, newest
  /// first (the worker takes dirty documents in insertion order). The source
  /// tables are only read (#668).
  Future<void> rebuild() async {
    if (_closed) return;
    await _write(
      () => _db.transaction(() async {
        await _db.customStatement('DELETE FROM content_metadata_documents');
        await _db.customStatement('DELETE FROM content_metadata_cache');
        for (final kind in ContentKind.values) {
          await _queueDocuments(kind);
        }
      }),
    );
    _recent.clear();
    _changes.add(null);
    _wake();
  }

  /// (dirty, total) documents, for the rebuild progress.
  Future<(int, int)> counts() async {
    final row = await _db.customSelect('''
      SELECT COUNT(*) AS total, COALESCE(SUM(dirty), 0) AS dirty
      FROM content_metadata_documents
    ''').getSingle();
    return (row.read<int>('dirty'), row.read<int>('total'));
  }

  Future<void> _queueDocuments(ContentKind kind) {
    final (table, column) = _source(kind);
    return _db.customStatement('''
      INSERT OR IGNORE INTO content_metadata_documents(kind, id)
      SELECT '${kind.name}', id FROM $table WHERE $column IS NOT NULL
      ORDER BY rowid DESC
    ''');
  }

  Future<void> _installSource(ContentKind kind) async {
    final (table, column) = _source(kind);
    final name = kind.name;
    await _queueDocuments(kind);
    await _db.customStatement('''
      DELETE FROM content_metadata_documents
      WHERE kind = '$name' AND id NOT IN (SELECT id FROM $table WHERE $column IS NOT NULL)
    ''');
    for (final operation in ['INSERT', 'UPDATE OF $column']) {
      final suffix = operation == 'INSERT' ? 'insert' : 'update';
      final condition = suffix == 'update'
          ? 'WHEN old.$column IS NOT new.$column'
          : '';
      await _db.customStatement('''
        CREATE TRIGGER IF NOT EXISTS metadata_${name}_$suffix
        AFTER $operation ON $table $condition BEGIN
          DELETE FROM content_metadata_documents
          WHERE kind = '$name' AND id = new.id AND new.$column IS NULL;
          INSERT INTO content_metadata_documents(kind, id, dirty)
          SELECT '$name', new.id, 1 WHERE new.$column IS NOT NULL
          ON CONFLICT(kind, id) DO UPDATE SET dirty = 1;
        END
      ''');
    }
    await _db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS metadata_${name}_delete
      AFTER DELETE ON $table BEGIN
        DELETE FROM content_metadata_documents WHERE kind = '$name' AND id = old.id;
      END
    ''');
    // Deletion, PIN reset and factory reset must remove derived private data
    // in the same transaction, even while the worker is busy or stopped.
    await _db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS metadata_remove_orphan
      AFTER DELETE ON content_metadata_documents WHEN old.hash IS NOT NULL BEGIN
        DELETE FROM content_metadata_cache WHERE hash = old.hash
          AND NOT EXISTS (SELECT 1 FROM content_metadata_documents WHERE hash = old.hash);
      END
    ''');
    await _db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS metadata_replace_orphan
      AFTER UPDATE OF hash ON content_metadata_documents
      WHEN old.hash IS NOT NULL AND old.hash IS NOT new.hash BEGIN
        DELETE FROM content_metadata_cache WHERE hash = old.hash
          AND NOT EXISTS (SELECT 1 FROM content_metadata_documents WHERE hash = old.hash);
      END
    ''');
  }

  /// Mounted rows/editors request priority without passing an editor or text.
  /// Subscribe before the initial read so a fast worker cannot lose an event.
  Stream<ContentMetadata?> watch(ContentKey key) => Stream.multi((sink) {
    _watching.update(key, (count) => count + 1, ifAbsent: () => 1);
    var revision = 0;
    var cancelled = false;
    Future<void> emit() async {
      final request = ++revision;
      try {
        final value = await read(key);
        if (!cancelled && request == revision) sink.add(value);
      } on Object catch (error, stack) {
        if (!cancelled) sink.addError(error, stack);
      }
    }

    final subscription = _changes.stream.listen((changed) {
      if (changed == null || changed == key) unawaited(emit());
    });
    unawaited(emit());
    sink.onCancel = () {
      cancelled = true;
      final remaining = _watching[key]! - 1;
      if (remaining == 0) {
        _watching.remove(key);
        _visible.remove(key);
      } else {
        _watching[key] = remaining;
      }
      return subscription.cancel();
    };
  });

  Future<ContentMetadata?> read(ContentKey key) async {
    if (_closed) return null;
    // This query opens the database if necessary; initialize runs before it.
    final rows = await _db
        .customSelect(
          '''
      SELECT c.hash, c.payload, c.digest, d.dirty
      FROM content_metadata_documents d
      LEFT JOIN content_metadata_cache c ON c.hash = d.hash
      WHERE d.kind = ? AND d.id = ?
    ''',
          variables: [Variable(key.kind.name), Variable(key.id)],
        )
        .get();
    if (_closed) return null;
    if (rows.isEmpty) {
      _visible.add(key);
      _wake();
      return null;
    }
    final row = rows.single;
    if (row.read<int>('dirty') != 0) {
      _visible.add(key);
      _wake();
      return null;
    }
    final payload = row.readNullable<String>('payload');
    ContentMetadata? result;
    if (payload != null) {
      final digest = row.read<String>('digest');
      final hash = row.read<String>('hash');
      result = await _decodeInBackground(payload, digest, hash);
    }
    if (_closed) return null;
    if (result == null) {
      _visible.add(key);
      _wake();
    }
    // Never display metadata for an older saved revision.
    return result;
  }

  /// Backlinks and saved views use index rows, never editor controllers. The
  /// result keys can be joined to the usual title/list projection by callers.
  Stream<List<ContentKey>> watchBacklinks(String target) =>
      Stream.multi((sink) {
        var cancelled = false;
        Future<void> emit() async {
          try {
            final rows = await _db
                .customSelect(
                  '''
          SELECT DISTINCT d.kind, d.id FROM content_metadata_documents d
          JOIN content_metadata_cache c ON c.hash = d.hash,
          json_each(CASE WHEN json_valid(c.payload) THEN c.payload ELSE '{}' END, '\$.links') l
          WHERE d.dirty = 0 AND json_extract(l.value, '\$.target') = ?
          ORDER BY d.kind, d.id
        ''',
                  variables: [Variable(target)],
                )
                .get();
            if (!cancelled) sink.add(rows.map(_key).toList());
          } on Object catch (error, stack) {
            if (!cancelled) sink.addError(error, stack);
          }
        }

        final subscription = _changes.stream.listen((_) => unawaited(emit()));
        unawaited(emit());
        sink.onCancel = () {
          cancelled = true;
          return subscription.cancel();
        };
      });

  void _wake() {
    if (_closed || !_initialized) return;
    if (_running != null) {
      _wakeAgain = true;
      return;
    }
    // The root zone, not the caller's: a wake from inside drift's beforeOpen
    // would otherwise bind the drain's queries to the opening executor,
    // which never answers once the database is open. The drain then hung
    // for the whole session and close() waited on it forever.
    _timer ??= Zone.root.createTimer(Duration.zero, () {
      _timer = null;
      _running = _drain().whenComplete(() {
        _running = null;
        if (_wakeAgain) {
          _wakeAgain = false;
          _wake();
        }
      });
    });
  }

  Future<void> _drain() async {
    try {
      final budget = Stopwatch()..start();
      while (!_closed) {
        final key = await _next();
        if (_closed || key == null) break;
        await _index(key);
        // One document at a time; yield to rendering and foreground DB writes
        // after at most 4 ms of the batch. Hashing and parsing are in isolates.
        if (budget.elapsedMilliseconds >= 4) {
          _wakeAgain = true;
          break;
        }
      }
    } on Object catch (error, stack) {
      // Derived data must never fail a content save/open. Retry on the next
      // source change/open; avoid a tight retry loop on a broken disk.
      _wakeAgain = false;
      _log.warning('Metadata indexing deferred', error, stack);
    }
  }

  Future<ContentKey?> _next() async {
    if (_visible.isNotEmpty) {
      final key = _visible.first;
      _visible.remove(key);
      return key;
    }
    final rows = await _db.customSelect('''
      SELECT kind, id FROM content_metadata_documents
      WHERE dirty = 1 ORDER BY rowid LIMIT 1
    ''').get();
    return rows.isEmpty ? null : _key(rows.single);
  }

  Future<void> _index(ContentKey key) async {
    final (table, column) = _source(key.kind);
    final rows = await _db
        .customSelect(
          'SELECT $column AS content FROM $table WHERE id = ? AND $column IS NOT NULL',
          variables: [Variable(key.id)],
        )
        .get();
    if (_closed || rows.isEmpty) return;
    final text = rows.single.read<String>('content');
    final hash = await _hashInBackground(text);
    if (_closed) return;
    final encoded = await _resolve(text, hash);
    if (_closed) return;
    await _write(
      () => _db.transaction(() async {
        if (_closed) return;
        // A save/delete can overtake the worker. Only publish for the exact
        // source revision it parsed, checked inside the writer transaction.
        final current = await _db
            .customSelect(
              'SELECT 1 FROM $table WHERE id = ? AND $column = ?',
              variables: [Variable(key.id), Variable(text)],
            )
            .get();
        if (current.isEmpty) return;
        await _db.customStatement(
          '''
        INSERT INTO content_metadata_cache(hash, payload, digest) VALUES (?, ?, ?)
        ON CONFLICT(hash) DO UPDATE SET payload = excluded.payload, digest = excluded.digest
        WHERE payload IS NOT excluded.payload OR digest IS NOT excluded.digest
      ''',
          [hash, encoded.payload, encoded.digest],
        );
        await _db.customStatement(
          '''
        INSERT INTO content_metadata_documents(kind, id, hash, dirty) VALUES (?, ?, ?, 0)
        ON CONFLICT(kind, id) DO UPDATE SET hash = excluded.hash, dirty = 0
      ''',
          [key.kind.name, key.id, hash],
        );
      }),
    );
    if (!_closed) _changes.add(key);
  }

  Future<void> _sweep() => _db.customStatement('''
    DELETE FROM content_metadata_cache WHERE NOT EXISTS (
      SELECT 1 FROM content_metadata_documents d WHERE d.hash = content_metadata_cache.hash
    )
  ''');

  /// Unsaved snapshots share the parser/cache; they never create persistent
  /// references or backlinks. At most eight recent results stay in memory.
  Future<ContentMetadata?> preview(String text) async {
    if (_closed) return null;
    final hash = await _hashInBackground(text);
    if (_closed) return null;
    final encoded = await _resolve(text, hash);
    return _decodeInBackground(encoded.payload, encoded.digest, hash);
  }

  Future<_EncodedMetadata> _resolve(String text, String hash) async {
    final recent = _recent[hash];
    if (recent != null) return recent;
    final pending = _pending[hash];
    if (pending != null) return pending;
    final work = _loadOrParse(text, hash);
    _pending[hash] = work;
    try {
      final encoded = await work;
      if (!_closed) {
        if (_recent.length >= 8) _recent.remove(_recent.keys.first);
        _recent[hash] = encoded;
      }
      return encoded;
    } finally {
      _pending.remove(hash);
    }
  }

  Future<_EncodedMetadata> _loadOrParse(String text, String hash) async {
    final cached = await _db
        .customSelect(
          'SELECT payload, digest FROM content_metadata_cache WHERE hash = ?',
          variables: [Variable(hash)],
        )
        .get();
    final payload = cached.isEmpty
        ? null
        : cached.single.read<String>('payload');
    final digest = cached.isEmpty ? null : cached.single.read<String>('digest');
    return _encodeInBackground(text, hash, payload, digest);
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await _subscription?.cancel();
    await _running;
    await Future.wait(_pending.values);
    _recent.clear();
    await _changes.close();
  }
}

const _sourceTables = {'history_entries', 'notes', 'snippets'};

(String, String) _source(ContentKind kind) => switch (kind) {
  ContentKind.recording => ('history_entries', 'content'),
  ContentKind.recordingEdited => (
    'history_entries',
    'smart_mode_edited_content',
  ),
  ContentKind.note => ('notes', 'content'),
  ContentKind.snippet => ('snippets', 'body'),
};

ContentKey _key(QueryRow row) => (
  kind: ContentKind.values.byName(row.read<String>('kind')),
  id: row.read<String>('id'),
);

// Isolate entry points live in plain (non-async, non-member) functions so the
// closure sent to the isolate captures only its sendable arguments. A closure
// created inside an async method shares that method's context, which holds
// the async machinery (_Future) and `this`, and Isolate.run then fails with
// "object is unsendable" (#1498).
Future<String> _hashInBackground(String text) =>
    Isolate.run(() => contentHash(text));

Future<ContentMetadata?> _decodeInBackground(
  String payload,
  String digest,
  String hash,
) => Isolate.run(() => decodeContentMetadata(payload, digest, hash));

Future<_EncodedMetadata> _encodeInBackground(
  String text,
  String hash,
  String? payload,
  String? digest,
) => Isolate.run(() {
  if (payload != null &&
      digest != null &&
      decodeContentMetadata(payload, digest, hash) != null) {
    return (payload: payload, digest: digest);
  }
  final fresh = jsonEncode(parseContentMetadata(text).toJson());
  return (payload: fresh, digest: contentHash(fresh));
});
