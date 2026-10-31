/// NotesActions for images and Textbausteine (WP-31a): a valid image is stored
/// with its row, a refused file leaves nothing behind, removal and the orphan
/// sweep clean up files, and "Als Textbaustein" keeps the link to its note.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/notes/data/note_asset_store.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';

/// A minimal complete PNG: signature, IHDR with [w] x [h], then IEND. The
/// metadata walk needs IEND to see the file through.
Uint8List _png(int w, int h) {
  final head = Uint8List(33);
  head.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  head.setAll(8, [0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  final d = ByteData.sublistView(head);
  d.setUint32(16, w);
  d.setUint32(20, h);
  return Uint8List.fromList([
    ...head,
    0,
    0,
    0,
    0,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
}

void main() {
  late Directory appData;
  late HistoryDatabase db;
  late NoteAssetStore store;
  late NotesActions actions;

  setUp(() {
    appData = Directory.systemTemp.createTempSync('wp31a_actions_');
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    store = NoteAssetStore(appDataDirPath: appData.path);
    actions = NotesActions(db, assets: store);
  });

  tearDown(() async {
    await db.close();
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  test('addImage stores the file and a row with the measured size', () async {
    final note = await db.createNote();

    final asset = await actions.addImage(note.id, _png(640, 480));

    expect(asset.noteId, note.id);
    expect(asset.mimeType, 'image/png');
    expect(asset.width, 640);
    expect(asset.height, 480);
    expect(asset.relativePath, endsWith('.png'));
    expect(File(store.absolutePath(asset.relativePath)).existsSync(), isTrue);
    expect((await db.noteAssetsFor(note.id)).single.id, asset.id);
  });

  test('a refused image writes no file and no row', () async {
    final note = await db.createNote();
    final svg = Uint8List.fromList(
      '<svg xmlns="http://www.w3.org/2000/svg"/>'.codeUnits,
    );

    await expectLater(
      actions.addImage(note.id, svg),
      throwsA(isA<NoteImageRejectedException>()),
    );

    expect(await db.noteAssetsFor(note.id), isEmpty);
    expect(Directory(store.rootPath).existsSync(), isFalse);
  });

  test('removeImage deletes the row and the file', () async {
    final note = await db.createNote();
    final asset = await actions.addImage(note.id, _png(10, 10));

    await actions.removeImage(asset);

    expect(await db.noteAssetsFor(note.id), isEmpty);
    expect(File(store.absolutePath(asset.relativePath)).existsSync(), isFalse);
  });

  test(
    'sweepAssetFolders removes folders of notes that no longer exist',
    () async {
      final kept = await db.createNote();
      await actions.addImage(kept.id, _png(10, 10));
      await actions.addImage('gone-note', _png(10, 10));

      await actions.sweepAssetFolders();

      final remaining = Directory(
        store.rootPath,
      ).listSync().map((e) => p.basename(e.path)).toList();
      expect(remaining, [kept.id]);
    },
  );

  test('image methods refuse to run without a file store', () async {
    final bare = NotesActions(db);
    final note = await db.createNote();
    await expectLater(
      bare.addImage(note.id, _png(10, 10)),
      throwsA(isA<StateError>()),
    );
  });

  test('"Als Textbaustein" keeps the link back to the source note', () async {
    final note = await db.createNote();

    final snippetId = await actions.createSnippetFromNote(
      noteId: note.id,
      title: 'Gruß',
      body: 'Mit freundlichen Grüßen',
    );

    final snippets = await db.readAllSnippets();
    final created = snippets.singleWhere((s) => s.id == snippetId);
    expect(created.title, 'Gruß');
    expect(created.body, 'Mit freundlichen Grüßen');
    expect(created.sourceNoteId, note.id);
  });

  test('re-saving a snippet without a source keeps its back-link', () async {
    final note = await db.createNote();
    final snippetId = await actions.createSnippetFromNote(
      noteId: note.id,
      title: 'Gruß',
      body: 'alt',
    );

    await db.upsertSnippet(
      id: snippetId,
      title: 'Gruß',
      body: 'neu',
      createdAt: DateTime(2026, 10, 18),
    );

    final snippet = (await db.readAllSnippets()).singleWhere(
      (s) => s.id == snippetId,
    );
    expect(snippet.body, 'neu');
    expect(snippet.sourceNoteId, note.id);
  });
}
