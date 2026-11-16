import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/note_preview.dart';

/// Recording lists read a stored preview, never the full text (#1324).
void main() {
  late HistoryDatabase db;

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  final longText = List.generate(20000, (i) => 'wort$i').join(' ');

  Future<void> insert(String id, String content) => db.insertHistoryEntry(
    HistoryEntriesCompanion.insert(
      id: id,
      timestamp: DateTime(2026, 11, 2),
      content: Value(content),
      originalTranscript: Value(content),
    ),
  );

  test('a saved long recording shows its preview, lists carry no full '
      'text', () async {
    await insert('e1', 'kurz');
    await db.updateEntry(
      'e1',
      HistoryEntriesCompanion(content: Value(longText)),
    );

    final list = await db.watchEntries().first;
    expect(list.single.content, startsWith('wort0 wort1'));
    expect(list.single.content.length, lessThanOrEqualTo(kNotePreviewLength));
    expect(list.single.preview, list.single.content);
    expect(list.single.originalTranscript, isNull);

    // The full text is read only for the single opened entry.
    expect((await db.getEntry('e1'))!.content, longText);
    expect((await db.entryContents(['e1']))['e1'], longText);
  });

  test('a new preview reaches a running list', () async {
    await insert('e1', 'alt');
    final emissions = <String>[];
    // Waits for the emissions themselves, not a fixed time (#1491).
    final listed = Completer<void>();
    final updated = Completer<void>();
    final sub = db.watchEntries().listen((l) {
      emissions.add(l.single.content);
      if (!listed.isCompleted) listed.complete();
      if (l.single.content.startsWith('neu ') && !updated.isCompleted) {
        updated.complete();
      }
    });
    await listed.future;
    await db.updateEntry(
      'e1',
      HistoryEntriesCompanion(content: Value('neu $longText')),
    );
    await updated.future.timeout(const Duration(seconds: 10));
    await sub.cancel();
    expect(emissions.last, startsWith('neu wort0'));
    expect(emissions.last.length, lessThanOrEqualTo(kNotePreviewLength));
  });

  test('archive and trash lists are light too', () async {
    await insert('e1', longText);
    await db.updateEntry(
      'e1',
      const HistoryEntriesCompanion(archived: Value(true)),
    );
    final archived = await db.watchArchived().first;
    expect(
      archived.single.content.length,
      lessThanOrEqualTo(kNotePreviewLength),
    );
    await db.updateEntry(
      'e1',
      HistoryEntriesCompanion(deletedAt: Value(DateTime(2026, 11, 3))),
    );
    final trash = await db.watchTrash().first;
    expect(trash.single.content.length, lessThanOrEqualTo(kNotePreviewLength));
  });

  test('rows without a stored preview are cut in SQL and backfilled', () async {
    await insert('e1', longText);
    await db.customStatement('UPDATE history_entries SET preview = NULL');
    final list = await db.watchEntries().first;
    expect(list.single.content.length, kNotePreviewLength);

    await db.backfillEntryPreviewsForTesting();
    expect((await db.getEntry('e1'))!.preview, notePreview(longText));
  });
}
