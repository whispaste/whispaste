/// File storage of note image assets (WP-31a): layout under the app data
/// directory, atomic writes, removal per note, and the orphan sweep.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/features/notes/data/note_asset_store.dart';
import 'package:whispaste/features/notes/data/note_image_inspector.dart';

void main() {
  late Directory appData;
  late NoteAssetStore store;

  setUp(() {
    appData = Directory.systemTemp.createTempSync('wp31a_assets_');
    store = NoteAssetStore(appDataDirPath: appData.path);
  });

  tearDown(() {
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  test(
    'relative path puts the asset in the note folder with its extension',
    () {
      expect(
        NoteAssetStore.relativePathFor('note-1', 'asset-9', NoteImageType.jpeg),
        'note_assets/note-1/asset-9.jpg',
      );
    },
  );

  test('write creates the note folder and the file holds the bytes', () async {
    final rel = NoteAssetStore.relativePathFor(
      'note-1',
      'asset-1',
      NoteImageType.png,
    );
    await store.write(rel, Uint8List.fromList([1, 2, 3]));

    final file = File(
      p.join(appData.path, 'note_assets', 'note-1', 'asset-1.png'),
    );
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), [1, 2, 3]);
    expect(
      File('${file.path}.tmp').existsSync(),
      isFalse,
      reason: 'the temporary file is renamed away',
    );
  });

  test('delete removes one file and tolerates a missing one', () async {
    final rel = NoteAssetStore.relativePathFor('n', 'a', NoteImageType.gif);
    await store.write(rel, Uint8List.fromList([9]));
    await store.delete(rel);
    expect(File(store.absolutePath(rel)).existsSync(), isFalse);
    await store.delete(rel); // no throw
  });

  test('deleteNoteFolder removes every asset of that note only', () async {
    await store.write(
      NoteAssetStore.relativePathFor('keep', 'a', NoteImageType.png),
      Uint8List.fromList([1]),
    );
    await store.write(
      NoteAssetStore.relativePathFor('drop', 'a', NoteImageType.png),
      Uint8List.fromList([1]),
    );
    await store.write(
      NoteAssetStore.relativePathFor('drop', 'b', NoteImageType.webp),
      Uint8List.fromList([1]),
    );

    await store.deleteNoteFolder('drop');

    expect(Directory(p.join(store.rootPath, 'drop')).existsSync(), isFalse);
    expect(Directory(p.join(store.rootPath, 'keep')).existsSync(), isTrue);
  });

  test('deleteNoteFolder refuses ids that could leave the folder', () async {
    await store.write(
      NoteAssetStore.relativePathFor('safe', 'a', NoteImageType.png),
      Uint8List.fromList([1]),
    );
    await store.deleteNoteFolder('..');
    await store.deleteNoteFolder('../safe');
    await store.deleteNoteFolder('');
    expect(Directory(p.join(store.rootPath, 'safe')).existsSync(), isTrue);
    expect(Directory(appData.path).existsSync(), isTrue);
  });

  test(
    'sweepOrphans keeps folders of live notes and removes the rest',
    () async {
      for (final id in ['live-1', 'gone-1', 'live-2']) {
        await store.write(
          NoteAssetStore.relativePathFor(id, 'a', NoteImageType.png),
          Uint8List.fromList([1]),
        );
      }

      await store.sweepOrphans({'live-1', 'live-2'});

      expect(Directory(p.join(store.rootPath, 'gone-1')).existsSync(), isFalse);
      expect(Directory(p.join(store.rootPath, 'live-1')).existsSync(), isTrue);
      expect(Directory(p.join(store.rootPath, 'live-2')).existsSync(), isTrue);
    },
  );

  test('sweepOrphans is a no-op when no asset folder exists yet', () async {
    await store.sweepOrphans(const {});
    expect(Directory(store.rootPath).existsSync(), isFalse);
  });

  test('stored paths outside the note image folder are refused', () {
    for (final bad in [
      '../x.png',
      'note_assets/../../x.png',
      'note_assets/n1/../../x.png',
      '/etc/passwd',
      'note_assets//a1.png',
      'note_assets\\n1\\a1.png',
      'other/n1/a1.png',
      'note_assets/n1/a1.png/extra',
      '',
    ]) {
      expect(store.resolveAssetPath(bad), isNull, reason: bad);
    }
    expect(
      store.resolveAssetPath('note_assets/n1/a1.png'),
      p.join(appData.path, 'note_assets', 'n1', 'a1.png'),
    );
    expect(() => store.absolutePath('../x.png'), throwsArgumentError);
  });

  test('delete never touches a file outside the folder', () async {
    final outside = File(p.join(appData.path, 'outside.png'))
      ..writeAsBytesSync([1, 2, 3]);

    await store.delete('../outside.png');

    expect(outside.existsSync(), isTrue);
  });
}
