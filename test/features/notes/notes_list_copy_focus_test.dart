/// Regression: Ctrl/Cmd+C in the note list copies the note after a mouse
/// click on a row, wherever focus ended up.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';

import '../../fixtures/test_helpers.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('Ctrl/Cmd+C copies the note after a mouse click on its row', (
    tester,
  ) async {
    String? clip;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clip = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final t = DateTime(2025, 6, 1);
    final note = Note(
      archived: false,
      id: 'n1',
      content: 'Copy me please',
      pinned: false,
      isQuickNote: false,
      deletedAt: null,
      createdAt: t,
      updatedAt: t,
    );
    await tester.pumpWidget(
      makeTestable(
        const NotesPage(),
        overrides: [
          notesProvider.overrideWith((ref) => Stream.value([note])),
          allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
          noteTagsProvider.overrideWith((ref, id) => Stream.value(const [])),
        ],
        locale: const Locale('en'),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byType(NotesListTile));
    await _settle(tester);

    final command = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control;
    await tester.sendKeyDownEvent(command);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(command);
    await tester.pump();
    expect(clip, 'Copy me please');
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }, variant: TargetPlatformVariant.desktop());
}
