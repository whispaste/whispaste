/// Note image limits and file cleanup (WP-31a, DEV-281 / GS-081): a refused
/// import writes neither a row nor a file, every deletion path removes the
/// image files, the factory reset erases the folder, the orphan sweep keeps
/// only referenced files, and thumbnails decode at thumbnail size.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/note_asset_storage.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/data/note_asset_store.dart';
import 'package:whispaste/features/notes/data/note_image_inspector.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/widgets/note_image_strip.dart';

/// Complete 1x1 PNG, 45 bytes: signature, IHDR, IEND.
Uint8List _png() {
  final head = Uint8List(33);
  head.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  head.setAll(8, [0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  final d = ByteData.sublistView(head);
  d.setUint32(16, 1);
  d.setUint32(20, 1);
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

  setUp(() {
    appData = Directory.systemTemp.createTempSync('wp31a_limits_');
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    store = NoteAssetStore(appDataDirPath: appData.path);
  });

  tearDown(() async {
    await db.close();
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  int filesIn(String noteId) {
    final dir = Directory('${store.rootPath}/$noteId');
    if (!dir.existsSync()) return 0;
    return dir.listSync().whereType<File>().length;
  }

  group('amount limits', () {
    test(
      'a per-note count limit refuses the next image, writing nothing',
      () async {
        final actions = NotesActions(
          db,
          assets: store,
          limits: const NoteAssetLimits(maxCountPerNote: 2),
        );
        final note = await db.createNote();
        await actions.addImage(note.id, _png());
        await actions.addImage(note.id, _png());

        await expectLater(
          actions.addImage(note.id, _png()),
          throwsA(
            isA<NoteAssetLimitException>().having(
              (e) => e.reason,
              'reason',
              NoteAssetLimit.perNoteCount,
            ),
          ),
        );

        expect(await db.noteAssetsFor(note.id), hasLength(2));
        expect(filesIn(note.id), 2);
      },
    );

    test(
      'a per-note byte limit refuses the import that would exceed it',
      () async {
        final actions = NotesActions(
          db,
          assets: store,
          limits: const NoteAssetLimits(maxBytesPerNote: 100),
        );
        final note = await db.createNote();
        await actions.addImage(note.id, _png()); // 45 bytes
        await actions.addImage(note.id, _png()); // 90 bytes

        await expectLater(
          actions.addImage(note.id, _png()), // would reach 135
          throwsA(
            isA<NoteAssetLimitException>().having(
              (e) => e.reason,
              'reason',
              NoteAssetLimit.perNoteBytes,
            ),
          ),
        );

        expect(await db.noteAssetsFor(note.id), hasLength(2));
        expect(filesIn(note.id), 2);
      },
    );

    test('the global cap counts the images of all notes together', () async {
      final actions = NotesActions(
        db,
        assets: store,
        limits: const NoteAssetLimits(maxTotalBytes: 100),
      );
      final first = await db.createNote();
      final second = await db.createNote();
      await actions.addImage(first.id, _png());
      await actions.addImage(second.id, _png()); // 90 bytes in total

      await expectLater(
        actions.addImage(first.id, _png()),
        throwsA(
          isA<NoteAssetLimitException>().having(
            (e) => e.reason,
            'reason',
            NoteAssetLimit.globalBytes,
          ),
        ),
      );

      expect(await db.allNoteAssetPaths(), hasLength(2));
      expect(filesIn(first.id), 1);
    });

    test('an oversize image is refused before any row or file', () async {
      final actions = NotesActions(db, assets: store);
      final note = await db.createNote();
      final huge = Uint8List(10 * 1024 * 1024 + 1);

      await expectLater(
        actions.addImage(note.id, huge),
        throwsA(
          isA<NoteImageRejectedException>().having(
            (e) => e.rejection,
            'rejection',
            NoteImageRejection.tooLarge,
          ),
        ),
      );

      expect(await db.noteAssetsFor(note.id), isEmpty);
      expect(Directory(store.rootPath).existsSync(), isFalse);
    });
  });

  group('file cleanup on every deletion path', () {
    test('deleting a note forever removes its image folder', () async {
      final actions = NotesActions(db, assets: store);
      final note = await db.createNote();
      await actions.addImage(note.id, _png());

      await actions.deleteForever(note.id);

      expect(Directory('${store.rootPath}/${note.id}').existsSync(), isFalse);
    });

    test(
      'purging blank notes removes the images of the purged notes',
      () async {
        final actions = NotesActions(db, assets: store);
        final note = await db.createNote();
        await actions.addImage(note.id, _png());

        expect(await actions.purgeEmpty(), 1);

        expect(Directory('${store.rootPath}/${note.id}').existsSync(), isFalse);
      },
    );

    test('discarding a blank note removes its images', () async {
      final actions = NotesActions(db, assets: store);
      final note = await db.createNote();
      await actions.addImage(note.id, _png());

      expect(await actions.discardIfBlank(note.id), isTrue);

      expect(Directory('${store.rootPath}/${note.id}').existsSync(), isFalse);
    });

    test(
      'emptying the trash removes the images of the trashed notes',
      () async {
        final actions = NotesActions(db, assets: store);
        final note = await db.createNote();
        await actions.addImage(note.id, _png());
        await actions.moveToTrash(note.id);

        await actions.emptyTrash();

        expect(Directory('${store.rootPath}/${note.id}').existsSync(), isFalse);
      },
    );

    test(
      'the factory reset erases the image folder and nothing else',
      () async {
        final actions = NotesActions(db, assets: store);
        final note = await db.createNote();
        await actions.addImage(note.id, _png());
        final database = File('${appData.path}/history.sqlite')
          ..writeAsStringSync('db');

        await eraseNoteAssetRoot(appData.path);

        expect(Directory(store.rootPath).existsSync(), isFalse);
        expect(database.existsSync(), isTrue);
      },
    );
  });

  group('orphan sweep', () {
    test('removes unreferenced files and keeps referenced ones', () async {
      final actions = NotesActions(db, assets: store);
      final note = await db.createNote();
      final kept = await actions.addImage(note.id, _png());
      final stray = NoteAssetStore.relativePathFor(
        note.id,
        'stray',
        NoteImageType.png,
      );
      await store.write(stray, _png());
      final tmp = '${store.absolutePath(stray)}.tmp';
      File(tmp).writeAsBytesSync([1]);

      await actions.sweepAssetFolders();

      expect(File(store.absolutePath(kept.relativePath)).existsSync(), isTrue);
      expect(File(store.absolutePath(stray)).existsSync(), isFalse);
      expect(File(tmp).existsSync(), isTrue, reason: 'a write may be running');
    });

    test('removes folders of notes that no longer exist', () async {
      final actions = NotesActions(db, assets: store);
      await store.write(
        NoteAssetStore.relativePathFor('gone', 'a', NoteImageType.png),
        _png(),
      );

      await actions.sweepAssetFolders();

      expect(Directory('${store.rootPath}/gone').existsSync(), isFalse);
    });
  });

  test('a PNG whose first chunk is not IHDR is refused, not read', () {
    final forged = _png();
    forged.setAll(12, 'tEXt'.codeUnits);

    final check = inspectNoteImage(forged);

    expect(check.info, isNull);
    expect(check.rejection, NoteImageRejection.unreadableHeader);
  });

  testWidgets('thumbnails decode at thumbnail size, not at the file size', (
    tester,
  ) async {
    final asset = NoteAsset(
      id: 'a1',
      noteId: 'n1',
      relativePath: NoteAssetStore.relativePathFor(
        'n1',
        'a1',
        NoteImageType.png,
      ),
      mimeType: 'image/png',
      sizeBytes: 45,
      width: 40000,
      height: 1000,
      createdAt: DateTime(2026),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteAssetStoreProvider.overrideWithValue(store),
          noteAssetsProvider.overrideWith(
            (ref, noteId) => Stream.value([asset]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(body: NoteImageStrip(noteId: 'n1')),
        ),
      ),
    );
    await tester.pump();
    final semantics = tester.ensureSemantics();

    final image = tester.widget<Image>(
      find.descendant(
        of: find.bySemanticsIdentifier('notes-editor-image-a1'),
        matching: find.byType(Image),
      ),
    );
    final decoded = image.image as ResizeImage;
    expect(decoded.width, 192);
    expect(decoded.height, 192);
    expect(decoded.policy, ResizeImagePolicy.fit);
    semantics.dispose();
  });
}
