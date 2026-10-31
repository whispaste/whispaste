/// Images reach a note by drop (desktop_drop) and by paste (Cmd/Ctrl+V) as
/// well as by the file picker: every path runs the same checks, cleaning and
/// limits, and a trashed note takes none (WP-31a).
library;

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/features/notes/data/note_asset_store.dart';
import 'package:whispaste/features/notes/data/note_clipboard_image.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';

import '../../fixtures/test_helpers.dart';

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
    appData = Directory.systemTemp.createTempSync('wp31a-image-input-');
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    store = NoteAssetStore(appDataDirPath: appData.path);
  });

  tearDown(() async {
    await db.close();
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  /// Real database for attachments; the list gets the note from a plain
  /// stream so no Drift watch Timer outlives the test.
  Future<Note> seedNote(WidgetTester tester, String content) async {
    final id = (await tester.runAsync(() => db.createNote()))!.id;
    await tester.runAsync(() => db.updateNoteContent(id, content));
    return (await tester.runAsync(() => db.getNote(id)))!;
  }

  File writeFile(String name, Uint8List bytes) =>
      File('${appData.path}/$name')..writeAsBytesSync(bytes);

  Future<void> pumpPage(
    WidgetTester tester, {
    required Note note,
    NoteClipboardImageReader? clipboard,
  }) async {
    await tester.pumpWidget(
      makeTestable(
        const NotesPage(),
        db: db,
        overrides: [
          noteAssetStoreProvider.overrideWithValue(store),
          notesProvider.overrideWith((ref) => Stream.value([note])),
          allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
          noteTagsProvider.overrideWith(
            (ref, noteId) => Stream.value(const []),
          ),
          if (clipboard != null)
            noteClipboardImageReaderProvider.overrideWithValue(clipboard),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a dropped image file is attached to the open note', (
    tester,
  ) async {
    final note = await seedNote(tester, 'Drop-Test');
    await pumpPage(tester, note: note);
    await tester.tap(find.text('Drop-Test').first);
    await tester.pumpAndSettle();

    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    await tester.runAsync(() async {
      target.onDragDone?.call(
        DropDoneDetails(
          files: [
            DropItemFile(writeFile('photo.png', _png()).path),
            DropItemFile(
              writeFile('notes.txt', Uint8List.fromList([1, 2, 3])).path,
            ),
          ],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    final assets = await tester.runAsync(() => db.noteAssetsFor(note.id));
    expect(assets, hasLength(1), reason: 'only the image file is attached');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an image on the clipboard is pasted into the editor', (
    tester,
  ) async {
    final note = await seedNote(tester, 'Paste-Test');
    await pumpPage(tester, note: note, clipboard: () async => _png());
    await tester.tap(find.text('Paste-Test').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notes-editor-body')),
        matching: find.byType(TextField),
      ),
    );
    await tester.pump();

    final modifier = Platform.isMacOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(modifier);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    final assets = await tester.runAsync(() => db.noteAssetsFor(note.id));
    expect(assets, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('paste without an image on the clipboard attaches nothing', (
    tester,
  ) async {
    final note = await seedNote(tester, 'Kein Bild');
    await pumpPage(tester, note: note, clipboard: () async => null);
    await tester.tap(find.text('Kein Bild').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notes-editor-body')),
        matching: find.byType(TextField),
      ),
    );
    await tester.pump();

    final modifier = Platform.isMacOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(modifier);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    final assets = await tester.runAsync(() => db.noteAssetsFor(note.id));
    expect(assets, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
