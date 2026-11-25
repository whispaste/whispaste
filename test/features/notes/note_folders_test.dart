/// Note folders (#659, ADR 0034, schema v47): at most two levels, moving with
/// undo, deleting a folder never drops notes without the choice, and the
/// folder filter / saved-view rule cover a parent's subfolders.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/views/smart_view.dart';
import 'package:whispaste/core/views/smart_view_items.dart';
import 'package:whispaste/features/notes/data/note_folder_tree.dart';

void main() {
  group('database', () {
    late HistoryDatabase db;

    setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('folders have at most two levels and a name', () async {
      final top = await db.createNoteFolder('  Work ');
      expect(top.name, 'Work');
      final sub = await db.createNoteFolder('Clients', parentId: top.id);
      expect(sub.parentId, top.id);
      await expectLater(
        db.createNoteFolder('Deep', parentId: sub.id),
        throwsArgumentError,
      );
      await expectLater(
        db.createNoteFolder('Orphan', parentId: 'missing'),
        throwsArgumentError,
      );
      await expectLater(db.createNoteFolder('  '), throwsArgumentError);

      expect(await db.renameNoteFolder(top.id, ' '), 0);
      await db.renameNoteFolder(top.id, 'Job');
      final names = (await db.watchNoteFolders().first).map((f) => f.name);
      expect(names, ['Clients', 'Job']);
    });

    test('moving returns the old folders and the undo restores them', () async {
      final a = await db.createNoteFolder('A');
      final n1 = await db.createNote(folderId: a.id);
      final n2 = await db.createNote();
      final before = (await db.getNote(n1.id))!.updatedAt;

      final previous = await db.moveNotesToFolder([n1.id, n2.id], null);
      expect(previous, {n1.id: a.id, n2.id: null});
      expect((await db.getNote(n1.id))!.folderId, isNull);
      // Filing a note is not an edit.
      expect((await db.getNote(n1.id))!.updatedAt, before);

      await db.restoreNoteFolderIds(previous);
      expect((await db.getNote(n1.id))!.folderId, a.id);
      expect((await db.getNote(n2.id))!.folderId, isNull);
    });

    test(
      'the count covers subfolders and archived notes, not the trash',
      () async {
        final top = await db.createNoteFolder('Top');
        final sub = await db.createNoteFolder('Sub', parentId: top.id);
        await db.createNote(folderId: top.id);
        final archived = await db.createNote(folderId: sub.id);
        await db.setNotesArchived([archived.id], archived: true);
        final trashed = await db.createNote(folderId: sub.id);
        await db.softDeleteNote(trashed.id);
        await db.createNote();

        expect(await db.countNoteFolderNotes(top.id), 2);
        expect(await db.countNoteFolderNotes(sub.id), 1);
      },
    );

    for (final trash in [false, true]) {
      test(
        'deleting a folder ${trash ? 'trashes' : 'keeps'} its notes',
        () async {
          final top = await db.createNoteFolder('Top');
          final sub = await db.createNoteFolder('Sub', parentId: top.id);
          final other = await db.createNoteFolder('Other');
          final inTop = await db.createNote(folderId: top.id);
          final inSub = await db.createNote(folderId: sub.id);
          final elsewhere = await db.createNote(folderId: other.id);

          final ids = await db.deleteNoteFolder(top.id, trashNotes: trash);
          expect(ids, unorderedEquals([inTop.id, inSub.id]));

          expect((await db.watchNoteFolders().first).map((f) => f.id), [
            other.id,
          ]);
          for (final id in [inTop.id, inSub.id]) {
            final note = await db.getNote(id);
            expect(note, isNotNull, reason: 'notes are never deleted for good');
            expect(note!.folderId, isNull);
            expect(note.deletedAt != null, trash);
          }
          final kept = (await db.getNote(elsewhere.id))!;
          expect(kept.folderId, other.id);
          expect(kept.deletedAt, isNull);
        },
      );
    }
  });

  group('tree', () {
    NoteFolder folder(String id, {String? parent}) => NoteFolder(
      id: id,
      name: id,
      parentId: parent,
      createdAt: DateTime(2026),
    );
    Note note(String id, String? folderId) => Note(
      id: id,
      content: '',
      preview: '',
      pinned: false,
      isQuickNote: false,
      archived: false,
      folderId: folderId,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final folders = [
      folder('a'),
      folder('a1', parent: 'a'),
      folder('b'),
      // Broken data: a third level and a lost parent show at the top level.
      folder('deep', parent: 'a1'),
      folder('lost', parent: 'gone'),
    ];
    final byId = {for (final f in folders) f.id: f};

    test('two levels; broken links fall back to the top level', () {
      final tree = buildNoteFolderTree(folders);
      expect(tree.map((n) => n.folder.id), ['a', 'b', 'deep', 'lost']);
      expect(tree.first.children.map((f) => f.id), ['a1']);
      expect(canHoldSubfolder(null, byId), isTrue);
      expect(canHoldSubfolder('a', byId), isTrue);
      expect(canHoldSubfolder('a1', byId), isFalse);
      expect(canHoldSubfolder('gone', byId), isFalse);
    });

    test('a parent covers its subfolders in filter, counts and rules', () {
      expect(noteInFolder('a1', 'a', byId), isTrue);
      expect(noteInFolder('a', 'a1', byId), isFalse);
      expect(noteInFolder('b', 'a', byId), isFalse);
      expect(noteInFolder('gone', null, byId), isTrue);
      expect(noteInFolder('gone', 'gone', byId), isFalse);
      expect(
        noteCountsByFolder([
          note('1', 'a'),
          note('2', 'a1'),
          note('3', 'b'),
          note('4', null),
        ], byId),
        {'a': 2, 'a1': 1, 'b': 1},
      );

      const rule = FolderRule(folderId: 'a', folderName: 'A');
      bool matches(String? folderId) => rule.matches(
        noteSmartViewItem(
          note('n', folderId),
          const [],
          hasAppends: false,
          hasChecklist: false,
          folderIds: noteFolderAncestry(folderId, byId),
        ),
        DateTime(2026),
      );
      expect(matches('a1'), isTrue);
      expect(matches('a'), isTrue);
      expect(matches('b'), isFalse);
      expect(matches(null), isFalse);
    });
  });
}
