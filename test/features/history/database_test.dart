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
          model: const Value('whisper-large-v3-turbo'),
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

  group('Decorative color slot (Ticket 03, visual-refresh-2026)', () {
    test('insertHistoryEntry assigns a slot in the 8-category range', () async {
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'slot-1',
          timestamp: DateTime(2025, 1, 15),
        ),
      );

      final entries = await db.allEntries();
      expect(entries.first.colorSlot, inInclusiveRange(0, 7));
    });

    test(
      'two consecutive insertHistoryEntry calls never share a slot',
      () async {
        final slots = <int>[];
        for (var i = 0; i < 25; i++) {
          await db.insertHistoryEntry(
            HistoryEntriesCompanion.insert(
              id: 'seq-$i',
              timestamp: DateTime(2025, 1, 1).add(Duration(minutes: i)),
            ),
          );
          final entry = await (db.select(
            db.historyEntries,
          )..where((e) => e.id.equals('seq-$i'))).getSingle();
          slots.add(entry.colorSlot);
        }

        for (var i = 1; i < slots.length; i++) {
          expect(
            slots[i],
            isNot(slots[i - 1]),
            reason: 'entry $i shares a slot with its immediate predecessor',
          );
        }
      },
    );

    test('duplicateEntry copies the source entry\'s slot', () async {
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'src',
          timestamp: DateTime(2025, 1, 15),
        ),
      );
      final source = (await db.allEntries()).first;

      final duplicate = await db.duplicateEntry('src');

      expect(duplicate != null, true);
      expect(duplicate!.colorSlot, source.colorSlot);
    });

    test('mergeEntries keeps the base (oldest) entry\'s slot', () async {
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'base',
          timestamp: DateTime(2025, 1, 10),
        ),
      );
      final base = (await db.allEntries()).firstWhere((e) => e.id == 'base');

      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'other',
          timestamp: DateTime(2025, 1, 11),
        ),
      );

      final merged = await db.mergeEntries(['base', 'other']);

      expect(merged != null, true);
      expect(merged!.colorSlot, base.colorSlot);
    });

    test('a title/tag edit via upsertEntry does not change the slot', () async {
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'edit-1',
          timestamp: DateTime(2025, 1, 15),
        ),
      );
      final before = (await db.allEntries()).first;

      // Simulate a title edit: only title is set, colorSlot is left absent —
      // exactly how the real edit path (updateEntry) behaves.
      await db.updateEntry(
        'edit-1',
        const HistoryEntriesCompanion(title: Value('Renamed')),
      );

      final after = (await db.allEntries()).first;
      expect(after.title, 'Renamed');
      expect(after.colorSlot, before.colorSlot);
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
    test(
      'searchEntries still finds entries created through insertHistoryEntry '
      '— the color_slot column is not indexed and does not disturb the '
      'title/content/tags triggers',
      () async {
        await db.insertHistoryEntry(
          HistoryEntriesCompanion.insert(
            id: 'fts-color-slot',
            timestamp: DateTime(2025, 1, 15),
            title: const Value('Roadmap sync'),
            content: const Value('Discussed the color slot rollout'),
          ),
        );

        final results = await db.searchEntries('roadmap');
        expect(results, hasLength(1));
        expect(results.first.id, 'fts-color-slot');
      },
    );

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

  // ---------------------------------------------------------------------------
  // Shutdown / teardown safety
  // ---------------------------------------------------------------------------
  //
  // These tests cover the double-close bug that caused a native crash in
  // sqlite3_update_hook during app shutdown.
  //
  // The crash scenario:
  //   1. onWindowClose / _quit() calls db.close() explicitly.
  //   2. windowManager.destroy() triggers engine teardown.
  //   3. ProviderScope.dispose() → ProviderContainer.dispose() runs
  //      ref.onDispose(db.close) from historyDatabaseProvider — a second
  //      close() on an already-freed SQLite handle.
  //   4. sqlite3_close_v2 deregisters the update_hook on freed memory →
  //      SIGABRT inside sqlite3_update_hook.
  //
  // A native C crash is not catchable in Dart unit tests, so these tests
  // verify the Dart-visible invariants that the fix establishes:
  //   - close() is idempotent (second call does not throw).
  //   - watch*() methods return Stream.empty() after close, so any
  //     Riverpod StreamProvider rebuild triggered by ProviderScope teardown
  //     does not attempt to register a new sqlite3_update_hook on the freed
  //     connection.

  group('shutdown safety', () {
    test('close() is idempotent — second call does not throw', () async {
      // First close: orderly drift / SQLite shutdown.
      await db.close();
      // Second close: simulates the ref.onDispose(db.close) that fires during
      // ProviderScope teardown after windowManager.destroy().
      // Must be a no-op, not a native crash or Dart exception.
      await expectLater(db.close(), completes);
    });

    test('watchEntries() returns Stream.empty() after close', () async {
      await db.close();
      final events = await db.watchEntries().toList();
      expect(events, isEmpty);
    });

    test('watchArchived() returns Stream.empty() after close', () async {
      await db.close();
      final events = await db.watchArchived().toList();
      expect(events, isEmpty);
    });

    test('watchTrash() returns Stream.empty() after close', () async {
      await db.close();
      final events = await db.watchTrash().toList();
      expect(events, isEmpty);
    });

    test('watchAllReplacements() returns Stream.empty() after close', () async {
      await db.close();
      final events = await db.watchAllReplacements().toList();
      expect(events, isEmpty);
    });

    test('watchNotesForEntry() returns Stream.empty() after close', () async {
      await db.close();
      final events = await db.watchNotesForEntry('any-id').toList();
      expect(events, isEmpty);
    });

    test('watchTagsForEntry() returns Stream.empty() after close', () async {
      await db.close();
      final events = await db.watchTagsForEntry('any-id').toList();
      expect(events, isEmpty);
    });

    test('close() is idempotent even with an active watch subscription', () async {
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'shutdown-1',
          timestamp: DateTime(2025, 1, 15),
        ),
      );

      // Simulate a live historyEntriesProvider subscription still open.
      final subscription = db.watchEntries().listen((_) {});

      // First close: should complete the watch stream and close the connection.
      await db.close();

      // Second close: ref.onDispose() path — must be a no-op.
      await expectLater(db.close(), completes);

      // Clean up the subscription (stream completed, so cancel is a no-op too).
      await subscription.cancel();
    });
  });
}
