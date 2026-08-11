/// Ticket 27 — the markdown formatting bar on the Notes editor.
///
/// Three things are pinned here, because all three were the ticket:
///   1. the bar is *permanently* present in the note editor (Notes has no
///      read mode to hide it behind),
///   2. its buttons format the selection and take the formatting back off
///      again, leaving the cursor on the text the user had selected,
///   3. the shortcuts the tooltips advertise (Ctrl/Cmd+B, +I, +Shift+L) do on
///      this surface what they do in History — they come out of the same
///      [WpMarkdownFormatting], so a regression here is a regression there.
///
/// The tooltips/semantics labels are asserted against the ARB strings rather
/// than against English literals: hard-coded English was Befund 2.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';
import 'package:whispaste/widgets/markdown_toolbar.dart';

import '../../fixtures/test_helpers.dart';

Note _note() => Note(
  id: 'n1',
  content: 'hallo welt',
  createdAt: DateTime(2026, 4, 14, 10, 30),
  updatedAt: DateTime(2026, 4, 14, 10, 30),
  pinned: false,
  deletedAt: null,
);

Widget _panel({
  required TextEditingController controller,
  required FocusNode focusNode,
}) => NoteEditorPanel(
  note: _note(),
  tags: const [],
  controller: controller,
  focusNode: focusNode,
  onClose: () {},
  onToggleFavorite: () {},
  onMoveToTrash: () {},
  onRestore: () {},
  onDeleteForever: () {},
  onAddTag: (_) {},
  onRemoveTag: (_) {},
  onExport: () {},
  onVoiceTranscript: (_) {},
);

/// Presses the modifier combo the current platform binds the shortcut to.
Future<void> _pressShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  final modifier = Platform.isMacOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController(text: 'hallo welt');
    focusNode = FocusNode();
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> pumpPanel(WidgetTester tester, {Locale? locale}) async {
    await tester.pumpWidget(
      makeTestable(
        _panel(controller: controller, focusNode: focusNode),
        size: const Size(720, 600),
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('presence', () {
    testWidgets('the bar is there without any edit mode to switch on', (
      tester,
    ) async {
      await pumpPanel(tester);
      expect(find.byType(WpMarkdownToolbar), findsOneWidget);
    });
  });

  group('buttons', () {
    testWidgets('bold wraps the selection and a second tap takes it off', (
      tester,
    ) async {
      await pumpPanel(tester);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );

      await tester.tap(find.bySemanticsLabel(RegExp('^Bold')));
      await tester.pump();

      expect(controller.text, '**hallo** welt');
      // The wrapped word stays selected — the user can keep formatting it.
      expect(controller.selection.start, 0);
      expect(controller.selection.end, 9);

      await tester.tap(find.bySemanticsLabel(RegExp('^Bold')));
      await tester.pump();

      expect(controller.text, 'hallo welt');
      expect(controller.selection.start, 0);
      expect(controller.selection.end, 5);
    });

    testWidgets('italic wraps the selection and a second tap takes it off', (
      tester,
    ) async {
      await pumpPanel(tester);
      controller.selection = const TextSelection(
        baseOffset: 6,
        extentOffset: 10,
      );

      await tester.tap(find.bySemanticsLabel(RegExp('^Italic')));
      await tester.pump();

      expect(controller.text, 'hallo _welt_');
      expect(controller.selection.start, 6);
      expect(controller.selection.end, 12);

      await tester.tap(find.bySemanticsLabel(RegExp('^Italic')));
      await tester.pump();

      expect(controller.text, 'hallo welt');
      expect(controller.selection.start, 6);
      expect(controller.selection.end, 10);
    });

    testWidgets('formatting keeps firing the autosave listener', (
      tester,
    ) async {
      // The bar assigns `controller.value` wholesale. Anything listening for
      // note changes (the autosave debounce in _NotesPageState) has to keep
      // hearing them.
      var changes = 0;
      controller.addListener(() => changes++);

      await pumpPanel(tester);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      changes = 0;

      await tester.tap(find.bySemanticsLabel(RegExp('^Bold')));
      await tester.pump();

      expect(changes, greaterThan(0));
      expect(controller.text, '**hallo** welt');
    });
  });

  group('shortcuts', () {
    testWidgets('Ctrl/Cmd+B formats while the editor has focus', (
      tester,
    ) async {
      await pumpPanel(tester);
      focusNode.requestFocus();
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );

      await _pressShortcut(tester, LogicalKeyboardKey.keyB);

      expect(controller.text, '**hallo** welt');
    });

    testWidgets('Ctrl/Cmd+I formats while the editor has focus', (
      tester,
    ) async {
      await pumpPanel(tester);
      focusNode.requestFocus();
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );

      await _pressShortcut(tester, LogicalKeyboardKey.keyI);

      expect(controller.text, '_hallo_ welt');
    });

    testWidgets('Ctrl/Cmd+Shift+L toggles the bullet prefix', (tester) async {
      await pumpPanel(tester);
      focusNode.requestFocus();
      await tester.pump();
      controller.selection = const TextSelection.collapsed(offset: 3);

      await _pressShortcut(tester, LogicalKeyboardKey.keyL, shift: true);
      expect(controller.text, '- hallo welt');

      await _pressShortcut(tester, LogicalKeyboardKey.keyL, shift: true);
      expect(controller.text, 'hallo welt');
    });

    testWidgets('they are scoped to the editor, not to the whole panel', (
      tester,
    ) async {
      // The bindings live around the text field, so a key pressed anywhere
      // else in the panel — the tag input, say — never reaches them and the
      // note body is not reformatted out of nowhere.
      await pumpPanel(tester);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );

      await _pressShortcut(tester, LogicalKeyboardKey.keyB);

      expect(controller.text, 'hallo welt');
    });
  });

  group('localisation', () {
    testWidgets('tooltips and semantics come from the ARB files', (
      tester,
    ) async {
      final de = await L10n.delegate.load(const Locale('de'));
      await pumpPanel(tester, locale: const Locale('de'));

      final boldLabel = de.markdownToolbarBold(
        WpMarkdownFormatting.boldShortcutLabel,
      );
      expect(boldLabel, startsWith('Fett ('));
      expect(find.bySemanticsLabel(boldLabel), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == boldLabel),
        findsOneWidget,
      );

      // The four unshortcutted ones are translated too.
      expect(find.bySemanticsLabel(de.markdownToolbarHeading), findsOneWidget);
      expect(
        find.bySemanticsLabel(de.markdownToolbarNumberedList),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(de.markdownToolbarQuote), findsOneWidget);
      expect(find.bySemanticsLabel(de.markdownToolbarCode), findsOneWidget);

      // ...and no English literal survived.
      expect(find.bySemanticsLabel(RegExp('^Bold')), findsNothing);
      expect(find.bySemanticsLabel('Numbered list'), findsNothing);
    });

    testWidgets('the Hebrew labels render with the shortcut inlined', (
      tester,
    ) async {
      // `{shortcut}` injects an LTR key cap into an RTL string; the label has
      // to survive that intact, parentheses and all.
      final he = await L10n.delegate.load(const Locale('he'));
      await pumpPanel(tester, locale: const Locale('he'));

      final boldLabel = he.markdownToolbarBold(
        WpMarkdownFormatting.boldShortcutLabel,
      );
      expect(boldLabel, startsWith('מודגש ('));
      expect(boldLabel, endsWith(')'));
      expect(boldLabel, contains(WpMarkdownFormatting.boldShortcutLabel));
      expect(find.bySemanticsLabel(boldLabel), findsOneWidget);
      expect(find.bySemanticsLabel(he.markdownToolbarQuote), findsOneWidget);
    });

    testWidgets('the shortcut in the tooltip is the one that is bound', (
      tester,
    ) async {
      final en = await L10n.delegate.load(const Locale('en'));
      await pumpPanel(tester, locale: const Locale('en'));
      focusNode.requestFocus();
      await tester.pump();

      final promised = en.markdownToolbarBulletList(
        WpMarkdownFormatting.bulletListShortcutLabel,
      );
      expect(find.bySemanticsLabel(promised), findsOneWidget);

      controller.selection = const TextSelection.collapsed(offset: 0);
      await _pressShortcut(tester, LogicalKeyboardKey.keyL, shift: true);
      expect(controller.text, '- hallo welt');
    });
  });
}
