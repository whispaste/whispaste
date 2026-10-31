/// `HistoryDatabase.deleteAllHistory` — the "Forgot PIN?" wipe: every
/// history entry (active, archived, trashed) and everything hanging off it
/// goes; standalone notes, tags and settings stay.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'removes all entries and their rows, returns attachment paths',
    () async {
      final now = DateTime.now();
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(id: 'active', timestamp: now),
      );
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'archived',
          timestamp: now,
          archived: const Value(true),
        ),
      );
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'trashed',
          timestamp: now,
          deletedAt: Value(now),
        ),
      );
      final tag = await db.createTag('work');
      await db.tagEntry('active', tag.id);
      await db.upsertNote(
        EntryNotesCompanion.insert(
          id: 'n1',
          entryId: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.insertAudioAttachment(
        entryId: 'active',
        filePath: '/tmp/retained/a.wav',
        sizeBytes: 1,
      );
      final standalone = await db.createNote();
      await db.writeAppSettings({'history_hide_on_open': 'true'});

      final files = await db.deleteAllHistory();

      expect(files, ['/tmp/retained/a.wav']);
      expect(await db.select(db.historyEntries).get(), isEmpty);
      expect(await db.select(db.entryTags).get(), isEmpty);
      expect(await db.select(db.entryNotes).get(), isEmpty);
      expect(await db.select(db.entryAttachments).get(), isEmpty);
      expect(await db.getNote(standalone.id), isNotNull);
      expect(await db.select(db.tags).get(), hasLength(1));
      expect((await db.readAppSettings())['history_hide_on_open'], 'true');
    },
  );
}
