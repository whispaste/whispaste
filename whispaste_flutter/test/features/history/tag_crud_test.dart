/// Tag DAO / CRUD unit tests (Phase 4B).
///
/// Tests normalized tag operations directly against the Drift database:
/// create, delete, rename, link/unlink, search, frequency, and FTS5
/// integration.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  /// Helper: insert a minimal history entry.
  Future<void> insertEntry(String id, {String content = '', String title = ''}) {
    return db.upsertEntry(HistoryEntriesCompanion.insert(
      id: id,
      timestamp: DateTime(2025, 6, 1),
      content: Value(content),
      title: Value(title),
    ));
  }

  // =========================================================================
  // createTag
  // =========================================================================

  group('createTag', () {
    test('creates a tag with lowercased, trimmed name', () async {
      final tag = await db.createTag('  Meeting  ');
      expect(tag.name, 'meeting');
      expect(tag.id, isNotEmpty);
      expect(tag.createdAt, isNotNull);
    });

    test('returns existing tag for duplicate (case-insensitive)', () async {
      final first = await db.createTag('flutter');
      final second = await db.createTag('Flutter');
      final third = await db.createTag('FLUTTER');

      expect(first.id, second.id);
      expect(second.id, third.id);

      final all = await db.allTags();
      expect(all, hasLength(1));
    });

    test('creates distinct tags for different names', () async {
      await db.createTag('alpha');
      await db.createTag('beta');
      await db.createTag('gamma');

      final all = await db.allTags();
      expect(all, hasLength(3));
    });
  });

  // =========================================================================
  // deleteTag
  // =========================================================================

  group('deleteTag', () {
    test('removes tag from tags table', () async {
      final tag = await db.createTag('temporary');
      await db.deleteTag(tag.id);

      expect(await db.allTags(), isEmpty);
    });

    test('removes all entry_tags links when tag is deleted', () async {
      await insertEntry('e1');
      await insertEntry('e2');

      final tag = await db.createTag('shared');
      await db.tagEntry('e1', tag.id);
      await db.tagEntry('e2', tag.id);

      await db.deleteTag(tag.id);

      expect(await db.tagsForEntry('e1'), isEmpty);
      expect(await db.tagsForEntry('e2'), isEmpty);
    });

    test('does not affect other tags', () async {
      final keep = await db.createTag('keep');
      final remove = await db.createTag('remove');

      await db.deleteTag(remove.id);

      final all = await db.allTags();
      expect(all, hasLength(1));
      expect(all.first.id, keep.id);
    });
  });

  // =========================================================================
  // renameTag
  // =========================================================================

  group('renameTag', () {
    test('changes tag name (lowercased)', () async {
      final tag = await db.createTag('draft');
      await db.renameTag(tag.id, 'Final');

      final all = await db.allTags();
      expect(all.first.name, 'final');
    });

    test('is no-op when new name collides with another tag', () async {
      await db.createTag('target');
      final source = await db.createTag('source');

      await db.renameTag(source.id, 'target');

      // Both tags still exist with original names.
      final all = await db.allTags();
      expect(all.map((t) => t.name).toList(), containsAll(['source', 'target']));
    });

    test('allows renaming to same name (no-op but valid)', () async {
      final tag = await db.createTag('same');
      await db.renameTag(tag.id, 'same');

      final all = await db.allTags();
      expect(all, hasLength(1));
      expect(all.first.name, 'same');
    });

    test('preserves entry links after rename', () async {
      await insertEntry('e1');
      final tag = await db.createTag('old-name');
      await db.tagEntry('e1', tag.id);

      await db.renameTag(tag.id, 'new-name');

      final entryTags = await db.tagsForEntry('e1');
      expect(entryTags, hasLength(1));
      expect(entryTags.first.name, 'new-name');
    });
  });

  // =========================================================================
  // tagEntry / untagEntry
  // =========================================================================

  group('tagEntry / untagEntry', () {
    test('links and unlinks an entry and tag', () async {
      await insertEntry('e1');
      final tag = await db.createTag('link-test');

      await db.tagEntry('e1', tag.id);
      expect(await db.tagsForEntry('e1'), hasLength(1));

      await db.untagEntry('e1', tag.id);
      expect(await db.tagsForEntry('e1'), isEmpty);
    });

    test('tagEntry is idempotent (no duplicate links)', () async {
      await insertEntry('e1');
      final tag = await db.createTag('dup');

      await db.tagEntry('e1', tag.id);
      await db.tagEntry('e1', tag.id);
      await db.tagEntry('e1', tag.id);

      expect(await db.tagsForEntry('e1'), hasLength(1));
    });

    test('one tag can be linked to multiple entries', () async {
      await insertEntry('e1');
      await insertEntry('e2');
      await insertEntry('e3');
      final tag = await db.createTag('shared');

      await db.tagEntry('e1', tag.id);
      await db.tagEntry('e2', tag.id);
      await db.tagEntry('e3', tag.id);

      expect(await db.tagsForEntry('e1'), hasLength(1));
      expect(await db.tagsForEntry('e2'), hasLength(1));
      expect(await db.tagsForEntry('e3'), hasLength(1));
    });

    test('one entry can have multiple tags', () async {
      await insertEntry('e1');
      final t1 = await db.createTag('a');
      final t2 = await db.createTag('b');
      final t3 = await db.createTag('c');

      await db.tagEntry('e1', t1.id);
      await db.tagEntry('e1', t2.id);
      await db.tagEntry('e1', t3.id);

      final tags = await db.tagsForEntry('e1');
      expect(tags, hasLength(3));
      // Sorted alphabetically.
      expect(tags.map((t) => t.name).toList(), ['a', 'b', 'c']);
    });

    test('untagEntry only removes the specified link', () async {
      await insertEntry('e1');
      final t1 = await db.createTag('keep');
      final t2 = await db.createTag('remove');

      await db.tagEntry('e1', t1.id);
      await db.tagEntry('e1', t2.id);

      await db.untagEntry('e1', t2.id);

      final tags = await db.tagsForEntry('e1');
      expect(tags, hasLength(1));
      expect(tags.first.name, 'keep');
    });
  });

  // =========================================================================
  // tagsForEntry
  // =========================================================================

  group('tagsForEntry', () {
    test('returns empty list for entry with no tags', () async {
      await insertEntry('lonely');
      expect(await db.tagsForEntry('lonely'), isEmpty);
    });

    test('returns tags sorted alphabetically', () async {
      await insertEntry('e1');
      final z = await db.createTag('zebra');
      final a = await db.createTag('alpha');
      final m = await db.createTag('middle');

      await db.tagEntry('e1', z.id);
      await db.tagEntry('e1', a.id);
      await db.tagEntry('e1', m.id);

      final tags = await db.tagsForEntry('e1');
      expect(tags.map((t) => t.name).toList(), ['alpha', 'middle', 'zebra']);
    });
  });

  // =========================================================================
  // frequentTags
  // =========================================================================

  group('frequentTags', () {
    test('orders by usage count descending', () async {
      await insertEntry('e1');
      await insertEntry('e2');
      await insertEntry('e3');

      final popular = await db.createTag('popular');
      final moderate = await db.createTag('moderate');
      final rare = await db.createTag('rare');

      // popular → 3 entries, moderate → 2, rare → 1.
      await db.tagEntry('e1', popular.id);
      await db.tagEntry('e2', popular.id);
      await db.tagEntry('e3', popular.id);
      await db.tagEntry('e1', moderate.id);
      await db.tagEntry('e2', moderate.id);
      await db.tagEntry('e1', rare.id);

      final frequent = await db.frequentTags(limit: 10);
      expect(frequent.map((t) => t.name).toList(), ['popular', 'moderate', 'rare']);
    });

    test('respects limit parameter', () async {
      await insertEntry('e1');
      final t1 = await db.createTag('a');
      final t2 = await db.createTag('b');
      final t3 = await db.createTag('c');

      await db.tagEntry('e1', t1.id);
      await db.tagEntry('e1', t2.id);
      await db.tagEntry('e1', t3.id);

      final limited = await db.frequentTags(limit: 2);
      expect(limited, hasLength(2));
    });

    test('returns empty when no tags are linked', () async {
      await db.createTag('orphan');
      final frequent = await db.frequentTags(limit: 10);
      expect(frequent, isEmpty);
    });
  });

  // =========================================================================
  // searchTags
  // =========================================================================

  group('searchTags', () {
    test('filters by prefix', () async {
      await db.createTag('flutter');
      await db.createTag('flow');
      await db.createTag('dart');

      final results = await db.searchTags('fl');
      expect(results.map((t) => t.name).toList(), containsAll(['flutter', 'flow']));
      expect(results, hasLength(2));
    });

    test('is case-insensitive (input is lowercased)', () async {
      await db.createTag('important');

      final results = await db.searchTags('IMP');
      expect(results, hasLength(1));
      expect(results.first.name, 'important');
    });

    test('returns empty for no match', () async {
      await db.createTag('something');
      expect(await db.searchTags('xyz'), isEmpty);
    });

    test('returns all tags when prefix is empty', () async {
      await db.createTag('a');
      await db.createTag('b');
      await db.createTag('c');

      final results = await db.searchTags('');
      expect(results, hasLength(3));
    });

    test('limits results to 20', () async {
      for (var i = 0; i < 25; i++) {
        await db.createTag('tag-${i.toString().padLeft(2, '0')}');
      }

      final results = await db.searchTags('tag-');
      expect(results.length, lessThanOrEqualTo(20));
    });
  });

  // =========================================================================
  // watchTagsForEntry (reactive stream)
  // =========================================================================

  group('watchTagsForEntry', () {
    test('emits current state on subscribe', () async {
      await insertEntry('e1');
      final tag = await db.createTag('watched');
      await db.tagEntry('e1', tag.id);

      final tags = await db.watchTagsForEntry('e1').first;
      expect(tags, hasLength(1));
      expect(tags.first.name, 'watched');
    });

    test('emits empty list for untagged entry', () async {
      await insertEntry('e1');
      final tags = await db.watchTagsForEntry('e1').first;
      expect(tags, isEmpty);
    });
  });

  // =========================================================================
  // FTS5 includes tags in search results
  // =========================================================================

  group('FTS5 tag search', () {
    test('searchEntries finds entries by tags JSON column', () async {
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'fts-tag-1',
        timestamp: DateTime(2025, 6, 1),
        title: const Value('Some note'),
        content: const Value('Generic content'),
        tags: const Value('["urgent","followup"]'),
      ));

      final results = await db.searchEntries('urgent');
      expect(results, hasLength(1));
      expect(results.first.id, 'fts-tag-1');
    });

    test('searchEntries matches tag that is not in title or content', () async {
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'fts-tag-2',
        timestamp: DateTime(2025, 6, 1),
        title: const Value('Meeting Notes'),
        content: const Value('Discussed Q3 goals'),
        tags: const Value('["quarterly-review"]'),
      ));

      final results = await db.searchEntries('quarterly');
      expect(results, hasLength(1));
      expect(results.first.id, 'fts-tag-2');
    });

    test('searchEntries still works for title/content without tags', () async {
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'fts-tag-3',
        timestamp: DateTime(2025, 6, 1),
        title: const Value('Architecture discussion'),
        content: const Value('Talked about microservices'),
      ));

      final resultsByTitle = await db.searchEntries('architecture');
      expect(resultsByTitle, hasLength(1));

      final resultsByContent = await db.searchEntries('microservices');
      expect(resultsByContent, hasLength(1));
    });
  });
}
