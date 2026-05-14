import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('HistoryDatabase', () {
    test('creates tables without error', () async {
      final entries = await db.allEntries();
      expect(entries, isEmpty);
    });

    test('inserts and retrieves an entry', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'test-1',
          timestamp: DateTime(2025, 1, 15, 10, 30),
          content: const Value('Hello world transcription'),
          title: const Value('Test Entry'),
          model: const Value('whisper-large-v3'),
          isLocal: const Value(true),
          durationSec: const Value(12.5),
        ),
      );

      final entries = await db.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first.id, 'test-1');
      expect(entries.first.content, 'Hello world transcription');
      expect(entries.first.title, 'Test Entry');
      expect(entries.first.isLocal, true);
    });

    test('soft-delete moves entry to trash', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'del-1',
          timestamp: DateTime(2025, 1, 15),
        ),
      );

      expect(await db.allEntries(), hasLength(1));

      await db.softDeleteEntry('del-1');

      expect(await db.allEntries(), isEmpty);
    });

    test('togglePin flips pin state', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'pin-1',
          timestamp: DateTime(2025, 1, 15),
        ),
      );

      var entries = await db.allEntries();
      expect(entries.first.pinned, false);

      await db.togglePin('pin-1');
      entries = await db.allEntries();
      expect(entries.first.pinned, true);

      await db.togglePin('pin-1');
      entries = await db.allEntries();
      expect(entries.first.pinned, false);
    });

    test('pinnedEntries returns only pinned', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'a',
          timestamp: DateTime(2025, 1, 15),
          pinned: const Value(true),
        ),
      );
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'b',
          timestamp: DateTime(2025, 1, 16),
        ),
      );

      final pinned = await db.pinnedEntries();
      expect(pinned, hasLength(1));
      expect(pinned.first.id, 'a');
    });

    test('upsertEntry updates existing entry', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'up-1',
          timestamp: DateTime(2025, 1, 15),
          title: const Value('Original'),
        ),
      );

      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'up-1',
          timestamp: DateTime(2025, 1, 15),
          title: const Value('Updated'),
        ),
      );

      final entries = await db.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first.title, 'Updated');
    });

    test('orders by timestamp descending', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'old',
          timestamp: DateTime(2025, 1, 10),
        ),
      );
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'new',
          timestamp: DateTime(2025, 1, 20),
        ),
      );

      final entries = await db.allEntries();
      expect(entries.first.id, 'new');
      expect(entries.last.id, 'old');
    });
  });

  group('Notes', () {
    test('CRUD operations work', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'entry-1',
          timestamp: DateTime(2025, 1, 15),
        ),
      );

      await db.upsertNote(
        EntryNotesCompanion.insert(
          id: 'note-1',
          entryId: 'entry-1',
          content: const Value('A detailed note'),
          createdAt: DateTime(2025, 1, 15),
          updatedAt: DateTime(2025, 1, 15),
        ),
      );

      final notes = await db.notesForEntry('entry-1');
      expect(notes, hasLength(1));
      expect(notes.first.content, 'A detailed note');

      await db.deleteNote('note-1');
      expect(await db.notesForEntry('entry-1'), isEmpty);
    });
  });

  group('Tags', () {
    test('createTag returns new tag with lowercased name', () async {
      final tag = await db.createTag('Meeting');
      expect(tag.name, 'meeting');
      expect(tag.id, isNotEmpty);
    });

    test('createTag returns existing tag for duplicate name', () async {
      final tag1 = await db.createTag('urgent');
      final tag2 = await db.createTag('Urgent');
      expect(tag1.id, tag2.id);
    });

    test('allTags returns alphabetically sorted tags', () async {
      await db.createTag('zebra');
      await db.createTag('alpha');
      await db.createTag('middle');

      final all = await db.allTags();
      expect(all.map((t) => t.name).toList(), ['alpha', 'middle', 'zebra']);
    });

    test('renameTag changes the tag name', () async {
      final tag = await db.createTag('old-name');
      await db.renameTag(tag.id, 'new-name');

      final all = await db.allTags();
      expect(all.first.name, 'new-name');
    });

    test('renameTag is no-op if new name already exists', () async {
      await db.createTag('existing');
      final tag = await db.createTag('to-rename');
      await db.renameTag(tag.id, 'existing');

      // Original name should remain
      final all = await db.allTags();
      expect(
        all.map((t) => t.name).toList(),
        containsAll(['existing', 'to-rename']),
      );
    });

    test('deleteTag removes tag and its entry links', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'e1',
          timestamp: DateTime(2025, 1, 15),
        ),
      );
      final tag = await db.createTag('removable');
      await db.tagEntry('e1', tag.id);

      await db.deleteTag(tag.id);

      expect(await db.allTags(), isEmpty);
      expect(await db.tagsForEntry('e1'), isEmpty);
    });

    test('tagEntry and untagEntry link/unlink entries and tags', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'e1',
          timestamp: DateTime(2025, 1, 15),
        ),
      );
      final tag = await db.createTag('test-tag');

      await db.tagEntry('e1', tag.id);
      expect(await db.tagsForEntry('e1'), hasLength(1));

      await db.untagEntry('e1', tag.id);
      expect(await db.tagsForEntry('e1'), isEmpty);
    });

    test('tagEntry is idempotent', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'e1',
          timestamp: DateTime(2025, 1, 15),
        ),
      );
      final tag = await db.createTag('dup-tag');

      await db.tagEntry('e1', tag.id);
      await db.tagEntry('e1', tag.id);
      expect(await db.tagsForEntry('e1'), hasLength(1));
    });

    test('frequentTags orders by usage count', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'e1',
          timestamp: DateTime(2025, 1, 15),
        ),
      );
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'e2',
          timestamp: DateTime(2025, 1, 16),
        ),
      );
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'e3',
          timestamp: DateTime(2025, 1, 17),
        ),
      );

      final popular = await db.createTag('popular');
      final rare = await db.createTag('rare');

      await db.tagEntry('e1', popular.id);
      await db.tagEntry('e2', popular.id);
      await db.tagEntry('e3', popular.id);
      await db.tagEntry('e1', rare.id);

      final frequent = await db.frequentTags(limit: 10);
      expect(frequent.first.name, 'popular');
      expect(frequent.last.name, 'rare');
    });

    test('searchTags filters by prefix', () async {
      await db.createTag('flutter');
      await db.createTag('flow');
      await db.createTag('dart');

      final results = await db.searchTags('fl');
      expect(
        results.map((t) => t.name).toList(),
        containsAll(['flutter', 'flow']),
      );
      expect(results.length, 2);
    });

    test('watchTagsForEntry emits updates', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'e1',
          timestamp: DateTime(2025, 1, 15),
        ),
      );
      final tag = await db.createTag('reactive');

      await db.tagEntry('e1', tag.id);

      // Stream emits the current state on subscribe
      final tags = await db.watchTagsForEntry('e1').first;
      expect(tags, hasLength(1));
      expect(tags.first.name, 'reactive');
    });
  });

  group('FTS search', () {
    test('searchEntries finds entries by title', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'fts-1',
          timestamp: DateTime(2025, 1, 15),
          title: const Value('Meeting with engineering team'),
          content: const Value('We discussed roadmap items'),
        ),
      );
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'fts-2',
          timestamp: DateTime(2025, 1, 16),
          title: const Value('Grocery list'),
          content: const Value('Milk, bread, eggs'),
        ),
      );

      final results = await db.searchEntries('meeting');
      expect(results, hasLength(1));
      expect(results.first.id, 'fts-1');
    });

    test('searchEntries finds entries by content', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'fts-1',
          timestamp: DateTime(2025, 1, 15),
          title: const Value('Note'),
          content: const Value('Flutter is a great framework'),
        ),
      );

      final results = await db.searchEntries('flutter');
      expect(results, hasLength(1));
    });

    test('searchEntries finds entries by tags column', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'fts-1',
          timestamp: DateTime(2025, 1, 15),
          title: const Value('Some note'),
          content: const Value('Content here'),
          tags: const Value('["urgent","followup"]'),
        ),
      );

      final results = await db.searchEntries('urgent');
      expect(results, hasLength(1));
      expect(results.first.id, 'fts-1');
    });

    test('searchEntries handles special characters gracefully', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'fts-1',
          timestamp: DateTime(2025, 1, 15),
          title: const Value('Test'),
          content: const Value('Some content'),
        ),
      );

      // Should not throw on special FTS characters
      final results = await db.searchEntries('test* OR "phrase" (grouped)');
      expect(results, isA<List<HistoryEntry>>());
    });

    test('searchEntries returns empty for no match', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'fts-1',
          timestamp: DateTime(2025, 1, 15),
          title: const Value('Hello'),
          content: const Value('World'),
        ),
      );

      final results = await db.searchEntries('nonexistent');
      expect(results, isEmpty);
    });

    test('searchEntries excludes soft-deleted entries', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'fts-1',
          timestamp: DateTime(2025, 1, 15),
          title: const Value('Deletable note'),
          content: const Value('This will be deleted'),
        ),
      );

      await db.softDeleteEntry('fts-1');

      final results = await db.searchEntries('deletable');
      expect(results, isEmpty);
    });

    test('searchEntries uses prefix matching', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'fts-1',
          timestamp: DateTime(2025, 1, 15),
          title: const Value('Engineering standup'),
          content: const Value('Discussed progress'),
        ),
      );

      final results = await db.searchEntries('engin');
      expect(results, hasLength(1));
    });
  });
}
