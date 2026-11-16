import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:whispaste/core/data/content_metadata_index.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;
  late Completer<LogRecord> workerFailure;
  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    workerFailure = Completer<LogRecord>();
    final logs = Logger.root.onRecord.listen((record) {
      if (record.loggerName == 'ContentMetadataIndex' &&
          record.level >= Level.WARNING &&
          !workerFailure.isCompleted) {
        workerFailure.complete(record);
      }
    });
    addTearDown(logs.cancel);
  });
  tearDown(() => db.close());

  Future<void> recording(String id, String text) => db.upsertEntry(
    HistoryEntriesCompanion.insert(
      id: id,
      timestamp: DateTime(2026),
      content: Value(text),
    ),
  );

  Future<ContentMetadata> indexed(
    ContentKind kind,
    String id,
    String text,
  ) async {
    final hash = contentHash(text);
    final values = StreamIterator(db.contentIndex.watch((kind: kind, id: id)));
    // A test timeout must also release the listener before db.close waits
    // for the metadata change stream to close.
    addTearDown(values.cancel);
    Future<ContentMetadata> matching() async {
      while (await values.moveNext()) {
        final metadata = values.current;
        if (metadata?.hash == hash) return metadata!;
      }
      throw StateError('Metadata stream closed before the requested hash');
    }

    try {
      return await Future.any([
        matching(),
        workerFailure.future.then<ContentMetadata>((record) {
          Error.throwWithStackTrace(
            StateError('${record.message}: ${record.error}'),
            record.stackTrace ?? StackTrace.current,
          );
        }),
      ]);
    } finally {
      await values.cancel();
    }
  }

  test(
    'isolate path sends only sendable data and matches the sync parser',
    () async {
      const source = '# Title\n[[target]] #tag\n- [x] done';
      final preview = await db.contentIndex.preview(source);
      final expected = parseContentMetadata(source);
      expect(preview?.toJson(), expected.toJson());
      await recording('iso', source);
      final stored = await indexed(ContentKind.recording, 'iso', source);
      expect(stored.toJson(), expected.toJson());
      expect(
        await db.contentIndex.read((kind: ContentKind.recording, id: 'iso')),
        isA<ContentMetadata>(),
      );
    },
  );

  test(
    'save indexes all content kinds and shares a single content hash cache',
    () async {
      const source = '# Shared\n[[target]] #tag\n- [x] done';
      await recording('recording', source);
      final note = await db.createNote();
      await db.updateNoteContent(note.id, source);
      await db.upsertSnippet(
        id: 'snippet',
        title: 'Snippet',
        body: source,
        createdAt: DateTime(2026),
      );
      final results = await Future.wait([
        indexed(ContentKind.recording, 'recording', source),
        indexed(ContentKind.note, note.id, source),
        indexed(ContentKind.snippet, 'snippet', source),
      ]);
      expect(
        results.map((m) => m.toJson()),
        everyElement(results.first.toJson()),
      );
      final rows = await db
          .customSelect(
            'SELECT hash FROM content_metadata_cache WHERE hash = ?',
            variables: [Variable(contentHash(source))],
          )
          .get();
      expect(rows, hasLength(1));
      final backlinks = await db.contentIndex.watchBacklinks('target').first;
      expect(backlinks.toSet(), {
        (kind: ContentKind.recording, id: 'recording'),
        (kind: ContentKind.note, id: note.id),
        (kind: ContentKind.snippet, id: 'snippet'),
      });
    },
  );

  test('changed source replaces metadata and sweeps the old hash', () async {
    await recording('r', '# Before');
    final old = await indexed(ContentKind.recording, 'r', '# Before');
    await recording('r', '# After\nmore words');
    final fresh = await indexed(
      ContentKind.recording,
      'r',
      '# After\nmore words',
    );
    expect(fresh.hash, isNot(old.hash));
    expect(fresh.headings.single.text, 'After');
    expect(
      await db
          .customSelect(
            'SELECT hash FROM content_metadata_cache WHERE hash = ?',
            variables: [Variable(old.hash)],
          )
          .get(),
      isEmpty,
    );
  });

  test('saving unchanged content keeps the ready hash reference', () async {
    await recording('r', '# Same');
    final metadata = await indexed(ContentKind.recording, 'r', '# Same');
    await recording('r', '# Same');
    final row = await db.customSelect('''
      SELECT hash, dirty FROM content_metadata_documents
      WHERE kind = 'recording' AND id = 'r'
    ''').getSingle();
    expect(row.read<String>('hash'), metadata.hash);
    expect(row.read<int>('dirty'), 0);
  });

  test(
    'draft snapshots use the index without persisting private draft data',
    () async {
      final first = await db.contentIndex.preview('# Draft\n[[target]]');
      final second = await db.contentIndex.preview('# Draft\n[[target]]');
      expect(second?.toJson(), first?.toJson());
      expect(first?.links.single.target, 'target');
      expect(
        await db.customSelect('SELECT * FROM content_metadata_cache').get(),
        isEmpty,
      );
      expect(await db.contentIndex.watchBacklinks('target').first, isEmpty);
    },
  );

  test(
    'new saves overtake pending work and deleted sources stay deleted',
    () async {
      final old = '# Old\n${'paragraph ' * 10000}';
      await recording('r', old);
      final subscription = db.contentIndex
          .watch((kind: ContentKind.recording, id: 'r'))
          .listen((_) {});
      await recording('r', '# New');
      final fresh = await indexed(ContentKind.recording, 'r', '# New');
      expect(fresh.headings.single.text, 'New');
      await db.deleteAllData();
      await subscription.cancel();
      await db.contentIndex.close();
      expect(
        await db.customSelect('SELECT * FROM content_metadata_documents').get(),
        isEmpty,
      );
      expect(
        await db.customSelect('SELECT * FROM content_metadata_cache').get(),
        isEmpty,
      );
    },
  );

  test(
    'missing and damaged payloads repair on open without touching source',
    () async {
      const text = '# Keep me';
      await recording('r', text);
      final expected = await indexed(ContentKind.recording, 'r', text);
      await db.customStatement(
        'UPDATE content_metadata_cache SET payload = ? WHERE hash = ?',
        ['broken JSON', expected.hash],
      );
      expect(
        (await indexed(ContentKind.recording, 'r', text)).toJson(),
        expected.toJson(),
      );
      await db.customStatement(
        'DELETE FROM content_metadata_cache WHERE hash = ?',
        [expected.hash],
      );
      expect(
        (await indexed(ContentKind.recording, 'r', text)).toJson(),
        expected.toJson(),
      );
      await db.customStatement(
        "DELETE FROM content_metadata_documents WHERE kind = 'recording' AND id = 'r'",
      );
      expect(
        (await indexed(ContentKind.recording, 'r', text)).toJson(),
        expected.toJson(),
      );
      expect((await db.allEntries()).single.content, text);
    },
  );

  test('delete and factory reset remove derived private data', () async {
    final note = await db.createNote();
    await db.updateNoteContent(note.id, '# Private note');
    final metadata = await indexed(ContentKind.note, note.id, '# Private note');
    await db.deleteAllNotes();
    expect(
      await db
          .customSelect(
            'SELECT hash FROM content_metadata_cache WHERE hash = ?',
            variables: [Variable(metadata.hash)],
          )
          .get(),
      isEmpty,
    );
    await recording('r', '# Private recording');
    await indexed(ContentKind.recording, 'r', '# Private recording');
    await db.deleteAllData();
    expect(
      await db.customSelect('SELECT * FROM content_metadata_documents').get(),
      isEmpty,
    );
    expect(
      await db.customSelect('SELECT * FROM content_metadata_cache').get(),
      isEmpty,
    );
  });

  test(
    'reopening repairs a missing index from existing saved content',
    () async {
      await db.close();
      final folder = await Directory.systemTemp.createTemp(
        'metadata-index-test',
      );
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/history.db');
      db = HistoryDatabase.forTesting(NativeDatabase(file));
      await recording('r', '# Persisted');
      final expected = await indexed(ContentKind.recording, 'r', '# Persisted');
      await db.close();
      // Simulate a missing cache while the app is closed.
      final executor = NativeDatabase(file);
      final temporary = HistoryDatabase.forTesting(executor);
      await temporary.customStatement('DROP TABLE content_metadata_cache');
      await temporary.close();
      db = HistoryDatabase.forTesting(NativeDatabase(file));
      expect(
        (await indexed(ContentKind.recording, 'r', '# Persisted')).toJson(),
        expected.toJson(),
      );
      await db.close();
    },
  );

  test(
    'rebuildDisposableCache drops derived rows and rebuilds them from user data',
    () async {
      await recording('r', '# Kept');
      final before = await indexed(ContentKind.recording, 'r', '# Kept');
      await db.customStatement(
        "UPDATE content_metadata_cache SET payload = 'broken'",
      );
      await db.contentIndex.rebuildDisposableCache();
      final after = await indexed(ContentKind.recording, 'r', '# Kept');
      expect(after.toJson(), before.toJson());
      expect((await db.getEntry('r'))!.content, '# Kept');
    },
  );
}
