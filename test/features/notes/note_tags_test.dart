/// Tag-integration DAO tests for the sidebar Notizen area (Ticket 05).
///
/// Vorbild `tag_crud_test.dart`. Includes a dedicated regression group for
/// the verified tag-usage-count bug: before this ticket, `allTagsWithCount`/
/// `unusedTags`/`deleteUnusedTags` only counted `entryTags`, so a tag used
/// exclusively by a note showed count 0 and was silently deleted as unused.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> insertEntry(String id) {
    return db.upsertEntry(
      HistoryEntriesCompanion.insert(id: id, timestamp: DateTime(2025, 6, 1)),
    );
  }

  group('tagNote / untagNote', () {
    test('links and unlinks a note and tag', () async {
      final note = await db.createNote();
      final tag = await db.createTag('link-test');

      await db.tagNote(note.id, tag.id);
      expect(await db.tagsForNote(note.id), hasLength(1));

      await db.untagNote(note.id, tag.id);
      expect(await db.tagsForNote(note.id), isEmpty);
    });

    test('tagNote is idempotent (no duplicate links)', () async {
      final note = await db.createNote();
      final tag = await db.createTag('dup');

      await db.tagNote(note.id, tag.id);
      await db.tagNote(note.id, tag.id);
      await db.tagNote(note.id, tag.id);

      expect(await db.tagsForNote(note.id), hasLength(1));
    });

    test('one note can have multiple tags, sorted alphabetically', () async {
      final note = await db.createNote();
      final z = await db.createTag('zebra');
      final a = await db.createTag('alpha');
      final m = await db.createTag('middle');

      await db.tagNote(note.id, z.id);
      await db.tagNote(note.id, a.id);
      await db.tagNote(note.id, m.id);

      final tags = await db.tagsForNote(note.id);
      expect(tags.map((t) => t.name).toList(), ['alpha', 'middle', 'zebra']);
    });

    test('a tag can be shared between an entry and a note', () async {
      await insertEntry('e1');
      final note = await db.createNote();
      final tag = await db.createTag('shared');

      await db.tagEntry('e1', tag.id);
      await db.tagNote(note.id, tag.id);

      expect(await db.tagsForEntry('e1'), hasLength(1));
      expect(await db.tagsForNote(note.id), hasLength(1));
    });
  });

  group('watchTagsForNote', () {
    test('emits current state on subscribe', () async {
      final note = await db.createNote();
      final tag = await db.createTag('watched');
      await db.tagNote(note.id, tag.id);

      final tags = await db.watchTagsForNote(note.id).first;
      expect(tags, hasLength(1));
      expect(tags.first.name, 'watched');
    });

    test('emits empty list for an untagged note', () async {
      final note = await db.createNote();
      expect(await db.watchTagsForNote(note.id).first, isEmpty);
    });
  });

  group('watchAllNoteTags', () {
    test('groups tags by note id', () async {
      final n1 = await db.createNote();
      final n2 = await db.createNote();
      final t1 = await db.createTag('a');
      final t2 = await db.createTag('b');

      await db.tagNote(n1.id, t1.id);
      await db.tagNote(n1.id, t2.id);
      await db.tagNote(n2.id, t1.id);

      final grouped = await db.watchAllNoteTags().first;
      expect(grouped[n1.id]?.map((t) => t.name).toList(), ['a', 'b']);
      expect(grouped[n2.id]?.map((t) => t.name).toList(), ['a']);
    });

    test('omits notes with no tags', () async {
      final note = await db.createNote();
      final grouped = await db.watchAllNoteTags().first;
      expect(grouped.containsKey(note.id), isFalse);
    });
  });

  // ===========================================================================
  // Tag-usage-count bugfix regression (Ticket 05)
  // ===========================================================================

  group('allTagsWithCount — combined entry + note usage', () {
    test('a tag used only by a note has count 1, not 0', () async {
      final note = await db.createNote();
      final tag = await db.createTag('note-only');

      await db.tagNote(note.id, tag.id);

      final all = await db.allTagsWithCount();
      final entry = all.firstWhere((r) => r.$1.id == tag.id);
      expect(entry.$2, 1);
    });

    test('a tag used by both an entry and a note has count 2', () async {
      await insertEntry('e1');
      final note = await db.createNote();
      final tag = await db.createTag('both');

      await db.tagEntry('e1', tag.id);
      await db.tagNote(note.id, tag.id);

      final all = await db.allTagsWithCount();
      final result = all.firstWhere((r) => r.$1.id == tag.id);
      expect(result.$2, 2);
    });

    test('an unused tag still has count 0', () async {
      final tag = await db.createTag('unused');
      final all = await db.allTagsWithCount();
      final result = all.firstWhere((r) => r.$1.id == tag.id);
      expect(result.$2, 0);
    });
  });

  group(
    'frequentTags / frequentTagsWithCount — combined entry + note usage',
    () {
      test('a tag used only by a note is surfaced, not omitted', () async {
        final note = await db.createNote();
        final tag = await db.createTag('note-only');
        await db.tagNote(note.id, tag.id);

        final frequent = await db.frequentTags();
        expect(frequent.map((t) => t.id), contains(tag.id));

        final withCount = await db.frequentTagsWithCount();
        final result = withCount.firstWhere((r) => r.$1.id == tag.id);
        expect(result.$2, 1);
      });

      test('an unused tag is excluded (unlike allTagsWithCount)', () async {
        final tag = await db.createTag('unused');
        final frequent = await db.frequentTags();
        expect(frequent.map((t) => t.id), isNot(contains(tag.id)));
      });

      test(
        'limit is applied after merging both counts, not per source',
        () async {
          // t-notes: 3 links, all via notes. t-entries: 2 links, all via
          // entries. A per-query-then-limit(1) implementation would keep only
          // one of these depending on which junction table it queried first
          // (or drop t-notes if entryTags is queried alone); limit(1) after
          // merging must keep the actually-higher-count tag (t-notes, 3).
          final n1 = await db.createNote();
          final n2 = await db.createNote();
          final n3 = await db.createNote();
          final tNotes = await db.createTag('t-notes');
          await db.tagNote(n1.id, tNotes.id);
          await db.tagNote(n2.id, tNotes.id);
          await db.tagNote(n3.id, tNotes.id);

          await insertEntry('e1');
          await insertEntry('e2');
          final tEntries = await db.createTag('t-entries');
          await db.tagEntry('e1', tEntries.id);
          await db.tagEntry('e2', tEntries.id);

          final top = await db.frequentTagsWithCount(limit: 1);
          expect(top, hasLength(1));
          expect(top.single.$1.id, tNotes.id);
          expect(top.single.$2, 3);
        },
      );
    },
  );

  group('unusedTags / deleteUnusedTags — note-only tags are NOT unused', () {
    test('a tag attached only to a note is excluded from unusedTags', () async {
      final note = await db.createNote();
      final noteOnly = await db.createTag('note-only');
      final trulyUnused = await db.createTag('truly-unused');

      await db.tagNote(note.id, noteOnly.id);

      final unused = await db.unusedTags();
      expect(unused.map((t) => t.id), isNot(contains(noteOnly.id)));
      expect(unused.map((t) => t.id), contains(trulyUnused.id));
    });

    test(
      'deleteUnusedTags does not delete a tag only linked to a note',
      () async {
        final note = await db.createNote();
        final noteOnly = await db.createTag('note-only');
        await db.createTag('truly-unused');

        await db.tagNote(note.id, noteOnly.id);

        final deletedCount = await db.deleteUnusedTags();
        expect(deletedCount, 1);

        final remaining = await db.allTags();
        expect(remaining.map((t) => t.name), contains('note-only'));
        expect(remaining.map((t) => t.name), isNot(contains('truly-unused')));
      },
    );
  });

  group('deleteTag — cleans up both junction tables', () {
    test('removes note_tags links when a tag is deleted', () async {
      final n1 = await db.createNote();
      final n2 = await db.createNote();
      final tag = await db.createTag('shared');

      await db.tagNote(n1.id, tag.id);
      await db.tagNote(n2.id, tag.id);

      await db.deleteTag(tag.id);

      expect(await db.tagsForNote(n1.id), isEmpty);
      expect(await db.tagsForNote(n2.id), isEmpty);
    });

    test('removes both entry_tags and note_tags links', () async {
      await insertEntry('e1');
      final note = await db.createNote();
      final tag = await db.createTag('cross-linked');

      await db.tagEntry('e1', tag.id);
      await db.tagNote(note.id, tag.id);

      await db.deleteTag(tag.id);

      expect(await db.tagsForEntry('e1'), isEmpty);
      expect(await db.tagsForNote(note.id), isEmpty);
      expect(await db.allTags(), isEmpty);
    });
  });
}
