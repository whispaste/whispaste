/// Database behaviour of the notes core (WP-31a, schema v29): explicit title,
/// version history with count and byte bounds, restore as an undoable step,
/// image asset rows, and removal of dependent rows with their note.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/note_version_limits.dart';

void main() {
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('title', () {
    test('an explicit title is stored; blank clears it', () async {
      final note = await db.createNote();
      await db.setNoteTitle(note.id, '  Einkauf  ');
      expect((await db.getNote(note.id))!.title, 'Einkauf');

      await db.setNoteTitle(note.id, '   ');
      expect((await db.getNote(note.id))!.title, isNull);
    });
  });

  group('version history', () {
    test(
      'stores a snapshot, skips an identical one, stores a change',
      () async {
        final note = await db.createNote();
        expect(
          await db.recordNoteVersionIfChanged(
            note.id,
            title: null,
            content: 'a',
          ),
          isTrue,
        );
        expect(
          await db.recordNoteVersionIfChanged(
            note.id,
            title: null,
            content: 'a',
          ),
          isFalse,
        );
        expect(
          await db.recordNoteVersionIfChanged(
            note.id,
            title: null,
            content: 'ab',
          ),
          isTrue,
        );
        final versions = await db.noteVersionsFor(note.id);
        expect(versions.map((v) => v.content), ['ab', 'a']);
      },
    );

    test('keeps at most maxCount versions, dropping the oldest', () async {
      final note = await db.createNote();
      const limits = NoteVersionLimits(maxCount: 5);
      final base = DateTime(2026, 10, 1, 9);
      for (var i = 0; i < 9; i++) {
        await db.recordNoteVersionIfChanged(
          note.id,
          title: null,
          content: 'stand $i',
          limits: limits,
          now: base.add(Duration(minutes: i)),
        );
      }
      final versions = await db.noteVersionsFor(note.id);
      expect(versions, hasLength(5));
      expect(versions.first.content, 'stand 8');
      expect(versions.last.content, 'stand 4');
    });

    test('keeps the history within the byte budget', () async {
      final note = await db.createNote();
      const limits = NoteVersionLimits(maxTotalBytes: 400);
      final base = DateTime(2026, 10, 1, 9);
      for (var i = 0; i < 6; i++) {
        await db.recordNoteVersionIfChanged(
          note.id,
          title: null,
          content: '$i' * 50,
          limits: limits,
          now: base.add(Duration(minutes: i)),
        );
      }
      final versions = await db.noteVersionsFor(note.id);
      final total = versions.fold<int>(0, (sum, v) => sum + v.sizeBytes);
      expect(total, lessThanOrEqualTo(400));
      expect(versions.first.content, startsWith('5'));
    });

    test('restore replaces the current state and is itself undoable', () async {
      final note = await db.createNote();
      await db.setNoteTitle(note.id, 'Titel');
      await db.updateNoteContent(note.id, 'eins');
      await db.recordNoteVersionIfChanged(
        note.id,
        title: 'Titel',
        content: 'eins',
      );
      final eins = (await db.noteVersionsFor(note.id)).single;

      // An edit that was never snapshotted must not be lost by a restore.
      await db.updateNoteContent(note.id, 'zwei');

      expect(await db.restoreNoteVersion(eins.id), isTrue);
      expect((await db.getNote(note.id))!.content, 'eins');
      final afterRestore = await db.noteVersionsFor(note.id);
      expect(afterRestore, hasLength(2));
      expect(afterRestore.first.content, 'zwei');

      // Undo: restore the snapshot the restore created.
      expect(await db.restoreNoteVersion(afterRestore.first.id), isTrue);
      expect((await db.getNote(note.id))!.content, 'zwei');
    });

    test('restore of an unknown version does nothing', () async {
      expect(await db.restoreNoteVersion('missing'), isFalse);
    });

    test('a version can be deleted on its own', () async {
      final note = await db.createNote();
      await db.recordNoteVersionIfChanged(note.id, title: null, content: 'x');
      final version = (await db.noteVersionsFor(note.id)).single;
      await db.deleteNoteVersion(version.id);
      expect(await db.noteVersionsFor(note.id), isEmpty);
      expect((await db.getNote(note.id)), isNotNull);
    });
  });

  group('image assets', () {
    test('insert, list and remove asset rows per note', () async {
      final note = await db.createNote();
      await db.insertNoteAsset(
        NoteAssetsCompanion.insert(
          id: 'a1',
          noteId: note.id,
          relativePath: 'note_assets/${note.id}/a1.png',
          mimeType: 'image/png',
          sizeBytes: 120,
          width: 10,
          height: 20,
          createdAt: DateTime(2026, 10, 18),
        ),
      );
      final assets = await db.noteAssetsFor(note.id);
      expect(assets.single.id, 'a1');
      expect(assets.single.width, 10);
      expect((await db.getNoteAsset('a1'))!.relativePath, endsWith('a1.png'));

      await db.deleteNoteAsset('a1');
      expect(await db.noteAssetsFor(note.id), isEmpty);
    });

    test(
      'permanently deleting a note removes its versions and assets',
      () async {
        final note = await db.createNote();
        final other = await db.createNote();
        await db.recordNoteVersionIfChanged(note.id, title: null, content: 'x');
        await db.recordNoteVersionIfChanged(
          other.id,
          title: null,
          content: 'y',
        );
        for (final id in [note.id, other.id]) {
          await db.insertNoteAsset(
            NoteAssetsCompanion.insert(
              id: 'asset-$id',
              noteId: id,
              relativePath: 'note_assets/$id/x.png',
              mimeType: 'image/png',
              sizeBytes: 1,
              width: 1,
              height: 1,
              createdAt: DateTime(2026, 10, 18),
            ),
          );
        }

        await db.softDeleteNote(note.id);
        await db.permanentDeleteNote(note.id);

        expect(await db.getNote(note.id), isNull);
        expect(await db.noteVersionsFor(note.id), isEmpty);
        expect(await db.noteAssetsFor(note.id), isEmpty);
        expect(await db.noteVersionsFor(other.id), hasLength(1));
        expect(await db.noteAssetsFor(other.id), hasLength(1));
      },
    );

    test(
      'emptying the trash removes dependents of every trashed note',
      () async {
        final trashed = await db.createNote();
        await db.recordNoteVersionIfChanged(
          trashed.id,
          title: null,
          content: 'x',
        );
        await db.softDeleteNote(trashed.id);
        await db.emptyNotesTrash();
        expect(await db.noteVersionsFor(trashed.id), isEmpty);
      },
    );

    test('deleting all data clears the new tables', () async {
      final note = await db.createNote();
      await db.recordNoteVersionIfChanged(note.id, title: null, content: 'x');
      await db.deleteAllData();
      expect(await db.allNoteIds(), isEmpty);
      expect(await db.noteVersionsFor(note.id), isEmpty);
    });
  });
}
