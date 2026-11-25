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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';
import 'package:whispaste/widgets/markdown_toolbar.dart';

import '../../fixtures/test_helpers.dart';

Note _note() => Note(
  archived: false,
  id: 'n1',
  content: 'hallo welt',
  createdAt: DateTime(2026, 4, 14, 10, 30),
  updatedAt: DateTime(2026, 4, 14, 10, 30),
  pinned: false,
  isQuickNote: false,
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
  onQuickNoteSet: () {},
  onQuickNoteClear: () {},
  onMoveToTrash: () {},
  onRestore: () {},
  onDeleteForever: () {},
  onAddTag: (_) {},
  onRemoveTag: (_) {},
  onDuplicate: () {},
  onExport: () {},
  onVoiceTranscript: (_) {},
  // A title field and a "more" menu, for the keyboard-order tests (#652).
  extras: NoteEditorExtras(onSaveTitle: (_, _) {}, onGoToParagraph: () {}),
);

/// Presses the modifier combo the current platform binds the shortcut to.
Future<void> _pressShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
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
        // Wide enough for the whole bar on one line (no "More", #1845).
        size: const Size(1200, 600),
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

  group('paragraph style shortcuts (#652)', () {
    // Every paragraph style has a key, not only the bullet list: a user who
    // cannot aim at the bar (tremor, screen reader) reaches all of them.
    final cases = <(String, LogicalKeyboardKey, String)>[
      ('heading', LogicalKeyboardKey.keyH, '## hallo welt'),
      ('numbered list', LogicalKeyboardKey.digit7, '1. hallo welt'),
      ('checklist', LogicalKeyboardKey.keyT, '- [ ] hallo welt'),
      ('quote', LogicalKeyboardKey.digit9, '> hallo welt'),
    ];
    for (final (name, key, expected) in cases) {
      testWidgets('Ctrl/Cmd+Shift sets and clears the $name', (tester) async {
        await pumpPanel(tester);
        focusNode.requestFocus();
        await tester.pump();
        controller.selection = const TextSelection.collapsed(offset: 0);

        await _pressShortcut(tester, key, shift: true);
        expect(controller.text, expected);

        await _pressShortcut(tester, key, shift: true);
        expect(controller.text, 'hallo welt');
      });
    }

    testWidgets('Ctrl/Cmd+Shift+E marks the selection as code', (tester) async {
      await pumpPanel(tester);
      focusNode.requestFocus();
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );

      await _pressShortcut(tester, LogicalKeyboardKey.keyC, shift: true);
      expect(controller.text, '`hallo` welt');
    });
  });

  test('every editor key is its own and leaves the snippet picker free', () {
    final keys = [
      WpMarkdownFormatting.boldActivator,
      WpMarkdownFormatting.italicActivator,
      WpMarkdownFormatting.bulletListActivator,
      WpMarkdownFormatting.headingActivator,
      WpMarkdownFormatting.numberedListActivator,
      WpMarkdownFormatting.checklistActivator,
      WpMarkdownFormatting.quoteActivator,
      WpMarkdownFormatting.codeActivator,
      WpMarkdownFormatting.insertSnippetActivator,
    ];
    String sig(SingleActivator a) =>
        '${a.trigger.keyId}-${a.control}-${a.meta}-${a.shift}-${a.alt}';
    expect(keys.map(sig).toSet(), hasLength(keys.length));
    // Cmd/Ctrl+Shift+E is the systemwide snippet picker's default (#664): a
    // global hotkey on it would swallow an editor key before the app sees it.
    expect(
      keys.where((a) => a.trigger == LogicalKeyboardKey.keyE && a.shift),
      isEmpty,
    );
  });

  group('keyboard order (#652)', () {
    Finder byId(String id) => find.bySemanticsIdentifier(id);
    // Whether keyboard focus sits on (or inside) the widget [f] finds.
    bool focusOn(WidgetTester tester, Finder f) {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return false;
      final target = tester.element(f);
      if (ctx == target) return true;
      var hit = false;
      ctx.visitAncestorElements((e) {
        hit = e == target;
        return !hit;
      });
      return hit;
    }

    testWidgets('Tab runs title, text, then the bar as one stop', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(byId('notes-editor-title'));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusNode.hasFocus, isTrue, reason: 'text follows the title');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusOn(tester, byId('notes-editor-toolbar-bold')), isTrue);

      // One Tab leaves the whole bar: it is a single stop.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusOn(tester, byId('notes-editor-toolbar')), isFalse);
    });

    testWidgets('arrows, Home and End move inside the bar', (tester) async {
      await pumpPanel(tester);
      focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusOn(tester, byId('notes-editor-toolbar-bold')), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focusOn(tester, byId('notes-editor-toolbar-italic')), isTrue);

      // The text view menu (#648) is the last button of the bar.
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(focusOn(tester, byId('notes-editor-toolbar-text-view')), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        focusOn(tester, byId('notes-editor-toolbar-text-view')),
        isTrue,
        reason: 'the last button does not wrap',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(focusOn(tester, byId('notes-editor-toolbar-bold')), isTrue);

      // Enter on the focused button formats the text.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.text, '_hallo_ welt');
    });

    testWidgets('Esc closes the more menu and focus goes back', (tester) async {
      await pumpPanel(tester);
      focusNode.requestFocus();
      await tester.pump();

      await tester.tap(byId('notes-editor-more'));
      await tester.pumpAndSettle();
      expect(byId('notes-editor-menu-goto'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(byId('notes-editor-menu-goto'), findsNothing);
      expect(focusNode.hasFocus, isTrue, reason: 'back in the text');
    });
  });

  group('localisation', () {
    testWidgets('tooltips and semantics come from the ARB files', (
      tester,
    ) async {
      final de = await L10n.delegate.load(const Locale('de'));
      await pumpPanel(tester, locale: const Locale('de'));

      final boldLabel = de.markdownToolbarBold(
        WpMarkdownFormatting.boldShortcutLabel(de),
      );
      expect(boldLabel, startsWith('Fett ('));
      expect(find.bySemanticsLabel(boldLabel), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == boldLabel),
        findsOneWidget,
      );

      // The paragraph styles carry their shortcut too (#652).
      for (final label in [
        de.markdownToolbarHeading(
          WpMarkdownFormatting.headingShortcutLabel(de),
        ),
        de.markdownToolbarNumberedList(
          WpMarkdownFormatting.numberedListShortcutLabel(de),
        ),
        de.markdownToolbarChecklist(
          WpMarkdownFormatting.checklistShortcutLabel(de),
        ),
        de.markdownToolbarQuote(WpMarkdownFormatting.quoteShortcutLabel(de)),
        de.markdownToolbarCode(WpMarkdownFormatting.codeShortcutLabel(de)),
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }

      // ...and no English literal survived.
      expect(find.bySemanticsLabel(RegExp('^Bold')), findsNothing);
      expect(find.bySemanticsLabel('Numbered list'), findsNothing);
    });

    testWidgets('the shortcut in the tooltip is the one that is bound', (
      tester,
    ) async {
      final en = await L10n.delegate.load(const Locale('en'));
      await pumpPanel(tester, locale: const Locale('en'));
      focusNode.requestFocus();
      await tester.pump();

      final promised = en.markdownToolbarBulletList(
        WpMarkdownFormatting.bulletListShortcutLabel(en),
      );
      expect(find.bySemanticsLabel(promised), findsOneWidget);

      controller.selection = const TextSelection.collapsed(offset: 0);
      await _pressShortcut(tester, LogicalKeyboardKey.keyL, shift: true);
      expect(controller.text, '- hallo welt');
    });
  });
}
