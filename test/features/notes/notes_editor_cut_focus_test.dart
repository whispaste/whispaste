/// Regression: Ctrl/Cmd+X in the note editor keeps the editor focused, so the
/// next Ctrl/Cmd+V pastes without another click.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/features/notes/data/note_clipboard_image.dart';
import 'package:whispaste/features/notes/notes_page.dart';

import '../../fixtures/test_helpers.dart';

Note _note(String content, {DateTime? updatedAt}) {
  final t = DateTime(2025, 6, 1);
  return Note(
    id: 'n1',
    content: content,
    pinned: false,
    isQuickNote: false,
    deletedAt: null,
    createdAt: t,
    updatedAt: updatedAt ?? t,
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('Cut keeps focus in the editor; Paste works right after', (
    tester,
  ) async {
    String? clip;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clip = (call.arguments as Map)['text'] as String?;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': clip};
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final feed = StreamController<List<Note>>();
    addTearDown(feed.close);
    await tester.pumpWidget(
      makeTestable(
        const NotesPage(),
        overrides: [
          notesProvider.overrideWith((ref) async* {
            yield [_note('one two three')];
            yield* feed.stream;
          }),
          noteClipboardImageReaderProvider.overrideWithValue(() async => null),
          allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
          noteTagsProvider.overrideWith((ref, id) => Stream.value(const [])),
        ],
        locale: const Locale('en'),
      ),
    );
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);

    final fieldFinder = find.descendant(
      of: find.byKey(const ValueKey('notes-editor-body')),
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.focusNode!.hasPrimaryFocus, isTrue);
    field.controller!.selection = const TextSelection(
      baseOffset: 4,
      extentOffset: 7,
    );
    await tester.pump();

    Future<void> chord(LogicalKeyboardKey k) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(k);
      await tester.sendKeyUpEvent(k);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
    }

    await chord(LogicalKeyboardKey.keyX);
    expect(clip, 'two');
    expect(field.controller!.text, 'one  three');
    // The store echoes the saved text back through the notes stream.
    feed.add([_note('one  three', updatedAt: DateTime(2025, 6, 2))]);
    // Past the autosave debounce and the rebuild it causes.
    await _settle(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(field.focusNode!.hasPrimaryFocus, isTrue);

    await chord(LogicalKeyboardKey.keyV);
    expect(field.controller!.text, 'one two three');
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
