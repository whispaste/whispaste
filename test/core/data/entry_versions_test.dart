/// Version history of a recording transcript (#635): the merge rule with a
/// simulated clock, the count cap, and edit then restore giving back exactly
/// the earlier text.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/entry_version_rules.dart';
import 'package:whispaste/core/data/note_version_limits.dart';

String _title(String text) => text;

void main() {
  late HistoryDatabase db;
  final t0 = DateTime(2026, 11, 7, 10);

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: 'e1',
        timestamp: t0,
        content: const Value('dictated text'),
        originalTranscript: const Value('dictated text'),
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> edit(String text, DateTime at) async {
    await db.updateEntry('e1', HistoryEntriesCompanion(content: Value(text)));
    await db.recordEntryVersion('e1', text, EntryVersionSource.typed, now: at);
  }

  Future<List<String>> texts() async => [
    for (final v in await db.entryVersionsFor('e1'))
      decodeNoteVersionBody(v.content),
  ];

  test('edit then restore gives exactly the earlier text', () async {
    await db.recordEntryBaseline('e1', 'dictated text', now: t0);
    await edit('first edit', t0.add(const Duration(minutes: 1)));
    final versions = await db.entryVersionsFor('e1');
    final baseline = versions.last;
    expect(baseline.source, 'dictated');

    final ok = await db.restoreEntryVersion(
      baseline.id,
      deriveTitle: _title,
      now: t0.add(const Duration(minutes: 2)),
    );
    expect(ok, isTrue);
    expect((await db.getEntry('e1'))!.content, 'dictated text');
    // The replaced text is still a version, so the restore can be undone.
    expect(await texts(), contains('first edit'));
    final edited = (await db.entryVersionsFor(
      'e1',
    )).firstWhere((v) => decodeNoteVersionBody(v.content) == 'first edit');
    await db.restoreEntryVersion(
      edited.id,
      deriveTitle: _title,
      now: t0.add(const Duration(minutes: 3)),
    );
    expect((await db.getEntry('e1'))!.content, 'first edit');
  });

  test('original log and Smart Mode result stay untouched', () async {
    await db.updateEntry(
      'e1',
      const HistoryEntriesCompanion(smartModeEditedContent: Value('smart')),
    );
    await db.recordEntryBaseline('e1', 'dictated text', now: t0);
    await edit('typed', t0.add(const Duration(minutes: 1)));
    final first = (await db.entryVersionsFor('e1')).last;
    await db.restoreEntryVersion(
      first.id,
      deriveTitle: _title,
      now: t0.add(const Duration(minutes: 2)),
    );
    final entry = (await db.getEntry('e1'))!;
    expect(entry.originalTranscript, 'dictated text');
    expect(entry.smartModeEditedContent, 'smart');
  });

  test('typed versions within 10 minutes merge into one', () async {
    await db.recordEntryBaseline('e1', 'dictated text', now: t0);
    await edit('a', t0.add(const Duration(minutes: 1)));
    await edit('ab', t0.add(const Duration(minutes: 5)));
    await edit('abc', t0.add(const Duration(minutes: 10)));
    expect(await texts(), ['abc', 'dictated text']);
    // Past the window since the merged row was created: a new row.
    await edit('abcd', t0.add(const Duration(minutes: 12)));
    expect(await texts(), ['abcd', 'abc', 'dictated text']);
  });

  test('a merge that returns to the previous version drops the row', () async {
    await db.recordEntryBaseline('e1', 'dictated text', now: t0);
    await edit('changed', t0.add(const Duration(minutes: 1)));
    await edit('dictated text', t0.add(const Duration(minutes: 2)));
    expect(await texts(), ['dictated text']);
  });

  test('a restore never merges with typing', () async {
    await db.recordEntryBaseline('e1', 'dictated text', now: t0);
    await edit('typed', t0.add(const Duration(minutes: 1)));
    final first = (await db.entryVersionsFor('e1')).last;
    await db.restoreEntryVersion(
      first.id,
      deriveTitle: _title,
      now: t0.add(const Duration(minutes: 2)),
    );
    final sources = [for (final v in await db.entryVersionsFor('e1')) v.source];
    expect(sources.first, 'restored');
  });

  test('keeps at most 50 versions, oldest first', () async {
    await db.recordEntryBaseline('e1', 'dictated text', now: t0);
    for (var i = 1; i <= 60; i++) {
      // 11 minutes apart: no merging.
      await edit('v$i', t0.add(Duration(minutes: 11 * i)));
    }
    final list = await texts();
    expect(list.length, 50);
    expect(list.first, 'v60');
    expect(list.last, 'v11');
  });

  test('versions go with the entry', () async {
    await db.recordEntryBaseline('e1', 'dictated text', now: t0);
    await db.permanentDeleteEntry('e1');
    expect(await db.entryVersionsFor('e1'), isEmpty);
  });

  group('planEntryVersion', () {
    EntryVersionSnapshot snap(
      String id,
      String text,
      EntryVersionSource s,
      DateTime at,
    ) => EntryVersionSnapshot(id: id, content: text, source: s, createdAt: at);

    test('simulated clock: merge only inside the window', () {
      final newest = snap('n', 'x', EntryVersionSource.typed, t0);
      EntryVersionPlan at(int minutes) => planEntryVersion(
        content: 'y',
        source: EntryVersionSource.typed,
        now: t0.add(Duration(minutes: minutes)),
        newest: newest,
        previous: null,
      );
      expect(at(10), isA<EntryVersionMerge>());
      expect(at(11), isA<EntryVersionInsert>());
    });

    test('unchanged text is a no-op', () {
      expect(
        planEntryVersion(
          content: 'x',
          source: EntryVersionSource.typed,
          now: t0,
          newest: snap('n', 'x', EntryVersionSource.typed, t0),
          previous: null,
        ),
        isA<EntryVersionNoop>(),
      );
    });
  });
}
