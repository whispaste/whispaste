/// Tags for Textbausteine (#662, schema v46): the link table shares the tags
/// of notes and recordings, counts in the tag management, and goes with the
/// snippet when it is deleted for good.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  group('links', () {
    late HistoryDatabase db;

    setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> snippet(String id) => db.upsertSnippet(
      id: id,
      title: 'Title $id',
      body: 'Body $id',
      createdAt: DateTime(2026),
    );

    test('tagging is idempotent and reads back by name', () async {
      await snippet('s1');
      final b = await db.createTag('beta');
      final a = await db.createTag('alpha');
      await db.tagSnippet('s1', b.id);
      await db.tagSnippet('s1', a.id);
      await db.tagSnippet('s1', a.id);

      expect((await db.tagsForSnippet('s1')).map((t) => t.name), [
        'alpha',
        'beta',
      ]);
      final all = await db.readAllSnippetTags();
      expect(all.keys, ['s1']);
      expect(all['s1']!.map((t) => t.name), ['alpha', 'beta']);

      await db.untagSnippet('s1', a.id);
      expect((await db.tagsForSnippet('s1')).map((t) => t.name), ['beta']);
    });

    test('a tag only a snippet carries is in use, not unused', () async {
      await snippet('s1');
      final tag = await db.createTag('mail');
      await db.tagSnippet('s1', tag.id);

      final counts = {
        for (final (t, n) in await db.allTagsWithCount()) t.name: n,
      };
      expect(counts['mail'], 1);
      expect(await db.deleteUnusedTags(), 0);
      expect((await db.frequentTags()).map((t) => t.name), ['mail']);
    });

    test('a note and a snippet share one tag', () async {
      await snippet('s1');
      final note = await db.createNote();
      final tag = await db.createTag('Work');
      final again = await db.createTag('work');
      await db.tagSnippet('s1', tag.id);
      await db.tagNote(note.id, again.id);

      expect(again.id, tag.id);
      final counts = {
        for (final (t, n) in await db.allTagsWithCount()) t.name: n,
      };
      expect(counts['work'], 2);
    });

    test('deleting a tag removes its snippet links', () async {
      await snippet('s1');
      final tag = await db.createTag('mail');
      await db.tagSnippet('s1', tag.id);

      await db.deleteTag(tag.id);

      expect(await db.tagsForSnippet('s1'), isEmpty);
      expect(await db.readAllSnippetTags(), isEmpty);
    });

    test('trash keeps the tags, deleting for good removes them', () async {
      await snippet('s1');
      final tag = await db.createTag('mail');
      await db.tagSnippet('s1', tag.id);

      await db.trashSnippets(['s1']);
      await db.restoreSnippetsFromTrash(['s1']);
      expect((await db.tagsForSnippet('s1')).map((t) => t.name), ['mail']);

      await db.trashSnippets(['s1']);
      await db.permanentlyDeleteTrashedSnippets(['s1']);
      final rows = await db
          .customSelect('SELECT COUNT(*) AS c FROM snippet_tags')
          .getSingle();
      expect(rows.data['c'], 0);
      // The tag itself stays for the tag management to clean up.
      expect((await db.allTags()).map((t) => t.name), ['mail']);
    });

    test('tag names for search hits, grouped by snippet', () async {
      await snippet('s1');
      await snippet('s2');
      final tag = await db.createTag('mail');
      await db.tagSnippet('s1', tag.id);

      expect(await db.tagNamesForSnippets(['s1', 's2']), {
        's1': ['mail'],
      });
      expect(await db.tagNamesForSnippets(const []), isEmpty);
    });
  });

  group('upgrade', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('wp662_v46_');
      dbFile = File('${tempDir.path}/history.sqlite');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('upgrade from 45 adds the link table, snippets stay', () async {
      final first = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await first.customSelect('SELECT 1').get();
      await first.upsertSnippet(
        id: 's1',
        title: 'Old',
        body: 'body',
        createdAt: DateTime(2026),
      );
      await first.customStatement('DROP TABLE snippet_tags');
      await first.customStatement('PRAGMA user_version = 45');
      await first.close();

      final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);
      final active = await db.readAllSnippetsWithFields();
      expect(active.single.row.title, 'Old');
      expect(await db.tagsForSnippet('s1'), isEmpty);

      final tag = await db.createTag('mail');
      await db.tagSnippet('s1', tag.id);
      expect((await db.tagsForSnippet('s1')).map((t) => t.name), ['mail']);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], db.schemaVersion);
    });
  });
}
