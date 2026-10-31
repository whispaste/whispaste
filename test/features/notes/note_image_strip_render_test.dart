/// A note with attached images shows its image strip in the editor (WP-31a).
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/note_asset_storage.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/features/notes/data/note_asset_store.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';

import '../../fixtures/test_helpers.dart';
import '../../test_helpers/temp_dir_cleanup.dart';

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
    appData = Directory.systemTemp.createTempSync('wp31a-strip-render-');
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    store = NoteAssetStore(appDataDirPath: appData.path);
  });

  tearDown(() async {
    await db.close();
    deleteTempDir(appData);
  });

  testWidgets('an open note shows all of its attached images', (tester) async {
    final id = (await tester.runAsync(() => db.createNote()))!.id;
    await tester.runAsync(() => db.updateNoteContent(id, 'Mit Bildern'));
    final note = (await tester.runAsync(() => db.getNote(id)))!;
    final now = DateTime(2026, 10, 1);
    final bytes = _png();
    for (var i = 0; i < 3; i++) {
      final rel = 'note_assets/$id/img$i.png';
      await tester.runAsync(() async {
        await store.write(rel, bytes);
        await db.insertNoteAssetWithinLimits(
          NoteAssetsCompanion.insert(
            id: 'img$i',
            noteId: id,
            relativePath: rel,
            mimeType: 'image/png',
            sizeBytes: bytes.length,
            width: 1,
            height: 1,
            createdAt: now,
          ),
          const NoteAssetLimits(),
        );
      });
    }

    await tester.pumpWidget(
      makeTestable(
        const NotesPage(),
        db: db,
        liveNoteAssets: true,
        overrides: [
          noteAssetStoreProvider.overrideWithValue(store),
          notesProvider.overrideWith((ref) => Stream.value([note])),
          allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
          noteTagsProvider.overrideWith(
            (ref, noteId) => Stream.value(const []),
          ),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mit Bildern').first);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      expect(
        find.byKey(ValueKey('notes-editor-image-img$i')),
        findsOneWidget,
        reason: 'image img$i is in the strip',
      );
    }
    // Drift's stream-query timer must finish before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
