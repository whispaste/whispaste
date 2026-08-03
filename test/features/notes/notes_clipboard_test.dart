/// Copy-to-clipboard + plain-text-paste guarantee (US18) tests.
///
/// Covers:
///   - Tapping the copy button in [NoteEditorPanel] puts the exact editor
///     text on the clipboard (intercepted via the platform channel mock).
///   - Selecting a note whose content has Windows line endings shows/holds
///     normalized `\n`-only text in the editor (`_setEditorText` in
///     `NotesPage`) — TextField already strips rich text formatting, so CRLF
///     normalization is the only active plain-text measure.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

Note _sampleNote({required String id, required String content}) {
  final t = DateTime(2025, 6, 1);
  return Note(
    id: id,
    content: content,
    pinned: false,
    deletedAt: null,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('copy button', () {
    String? clipboardText;

    setUp(() {
      clipboardText = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              final args = Map<String, dynamic>.from(call.arguments as Map);
              clipboardText = args['text'] as String?;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('copies the exact editor content to the clipboard', (
      tester,
    ) async {
      final controller = TextEditingController(
        text: 'Grocery list\nMilk, eggs, bread',
      );
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        makeTestable(
          NoteEditorPanel(
            note: _sampleNote(id: 'n1', content: controller.text),
            isDark: true,
            controller: controller,
            focusNode: focusNode,
            onClose: () {},
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.notesCopy));
      await tester.pump();

      expect(clipboardText, 'Grocery list\nMilk, eggs, bread');
      expect(find.text(l10n.notesCopied), findsOneWidget);

      // Drain the toast's 2s auto-dismiss timer so no Timer outlives the
      // test (see factory_reset_failed_toast_test.dart for the pattern).
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });
  });

  group('plain-text paste guarantee (CRLF normalization)', () {
    testWidgets(
      'selecting a note with CRLF content shows normalized LF-only text',
      (tester) async {
        final notes = [
          _sampleNote(id: 'n1', content: 'Line one\r\nLine two\r\nLine three'),
        ];

        await tester.pumpWidget(
          makeTestable(
            const NotesPage(),
            overrides: [
              notesProvider.overrideWith((ref) => Stream.value(notes)),
            ],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Line one'));
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, 'Line one\nLine two\nLine three');
        expect(field.controller!.text, isNot(contains('\r')));
      },
    );
  });
}
