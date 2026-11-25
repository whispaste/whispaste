/// Find-and-replace inside one text field — the engine and the bar.
///
/// Split the way the feature is: [WpFindReplace] is pure string work and is
/// asserted directly, while the widget group pins the four promises the bar
/// makes to a user (typing highlights, "replace" takes exactly one, "replace
/// all" takes the lot, an empty query does nothing at all).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/find_replace.dart';
import 'package:whispaste/core/data/content_metadata.dart';
import 'package:whispaste/widgets/find_replace_bar.dart';
import 'package:whispaste/widgets/find_reveal.dart';
import 'package:whispaste/widgets/markdown_toolbar.dart';
import 'package:whispaste/widgets/wp_text_editor.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../fixtures/test_helpers.dart';

void main() {
  group('WpFindReplace — string engine', () {
    test('locate finds every non-overlapping hit, case-insensitively', () {
      final m = WpFindReplace.locate('Foo foo FOO', 'foo');
      expect(m.starts, [0, 4, 8]);
      expect(m.length, 3);
    });

    test('locate does not overlap', () {
      // "aa" in "aaa" is one hit at 0, not two — otherwise replace-all would
      // depend on iteration order.
      expect(WpFindReplace.locate('aaa', 'aa').starts, [0]);
    });

    test('locate treats the query literally, not as a regex', () {
      final m = WpFindReplace.locate('a (b) c', '(b)');
      expect(m.starts, [2]);
    });

    test('locate on an empty query finds nothing', () {
      expect(WpFindReplace.locate('anything', '').isEmpty, isTrue);
    });

    test('replaceOne swaps exactly the addressed match', () {
      final m = WpFindReplace.locate('a a a', 'a');
      expect(WpFindReplace.replaceOne('a a a', m, 1, 'X'), 'a X a');
    });

    test('replaceOne ignores an out-of-range index', () {
      final m = WpFindReplace.locate('a a', 'a');
      expect(WpFindReplace.replaceOne('a a', m, 5, 'X'), 'a a');
    });

    test('replaceAll swaps every match in one pass', () {
      final m = WpFindReplace.locate('a a a', 'a');
      expect(WpFindReplace.replaceAll('a a a', m, 'X'), 'X X X');
    });

    test('replaceAll terminates when the replacement contains the query', () {
      final m = WpFindReplace.locate('aa', 'a');
      expect(WpFindReplace.replaceAll('aa', m, 'aa'), 'aaaa');
    });

    test('replaceAll refuses stale offsets rather than cutting the text', () {
      final m = WpFindReplace.locate('hello hello', 'hello');
      expect(WpFindReplace.replaceAll('hi', m, 'X'), 'hi');
    });

    test('clampIndex answers -1 when nothing is left', () {
      expect(WpFindReplace.clampIndex(3, 0), -1);
      expect(WpFindReplace.clampIndex(9, 2), 1);
      expect(WpFindReplace.clampIndex(-4, 2), 0);
    });
  });

  group('WpFindHighlightController', () {
    test('paints one span per match, the active one apart', () {
      final c = WpFindHighlightController(text: 'foo bar foo');
      addTearDown(c.dispose);
      c.setFindHighlight(WpFindReplace.locate('foo bar foo', 'foo'), 1);

      final tinted = <TextSpan>[];
      void collect(InlineSpan span) {
        if (span is TextSpan) {
          if (span.style?.backgroundColor != null) tinted.add(span);
          span.children?.forEach(collect);
        }
      }

      collect(
        c.buildTextSpan(
          context: _NullContext(),
          style: const TextStyle(),
          withComposing: false,
        ),
      );

      expect(tinted.map((s) => s.text), ['foo', 'foo']);
      expect(
        tinted[1].style!.backgroundColor!.a,
        greaterThan(tinted[0].style!.backgroundColor!.a),
        reason: 'the active match must be the stronger tint',
      );
    });

    test('an identical push does not notify (no recompute loop)', () {
      final c = WpFindHighlightController(text: 'foo foo');
      addTearDown(c.dispose);
      final matches = WpFindReplace.locate('foo foo', 'foo');
      c.setFindHighlight(matches, 0);

      var notifications = 0;
      c.addListener(() => notifications++);
      c.setFindHighlight(WpFindReplace.locate('foo foo', 'foo'), 0);
      expect(notifications, 0);

      c.setFindHighlight(matches, 1);
      expect(notifications, 1);
    });
  });

  group('WpFindReplaceBar — via the toolbar that hosts it', () {
    late WpFindHighlightController controller;
    late FocusNode focusNode;
    late L10n l10n;

    setUpAll(() async {
      l10n = await L10n.delegate.load(const Locale('en'));
    });

    setUp(() {
      controller = WpFindHighlightController(text: 'one two one two one');
      focusNode = FocusNode();
    });

    tearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    Future<void> pumpBar(WidgetTester tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpMarkdownToolbar(controller: controller, focusNode: focusNode),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel(
          l10n.findReplaceToggle(WpFindReplaceBar.openShortcutLabel(l10n)),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder findField() => findByFieldLabel(l10n.findReplaceFindLabel).first;
    Finder replaceField() =>
        findByFieldLabel(l10n.findReplaceReplaceLabel).first;

    testWidgets('the bar is closed until the toolbar toggle is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          WpMarkdownToolbar(controller: controller, focusNode: focusNode),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(findByFieldLabel(l10n.findReplaceFindLabel), findsNothing);

      await tester.tap(
        find.bySemanticsLabel(
          l10n.findReplaceToggle(WpFindReplaceBar.openShortcutLabel(l10n)),
        ),
      );
      await tester.pumpAndSettle();
      expect(findByFieldLabel(l10n.findReplaceFindLabel), findsOneWidget);
    });

    testWidgets('typing a query highlights the matches and counts them', (
      tester,
    ) async {
      await pumpBar(tester);
      await tester.enterText(findField(), 'one');
      await tester.pumpAndSettle();

      expect(controller.findMatches.starts, [0, 8, 16]);
      expect(controller.activeFindIndex, 0);
      expect(find.text(l10n.findReplaceMatchCount(1, 3)), findsOneWidget);
    });

    testWidgets('a query with no hits reports so and highlights nothing', (
      tester,
    ) async {
      await pumpBar(tester);
      await tester.enterText(findField(), 'zzz');
      await tester.pumpAndSettle();

      expect(controller.findMatches.isEmpty, isTrue);
      expect(controller.activeFindIndex, -1);
      expect(find.text(l10n.findReplaceNoMatches), findsOneWidget);
    });

    testWidgets('next / previous cycle through the matches', (tester) async {
      await pumpBar(tester);
      await tester.enterText(findField(), 'one');
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsLabel(
          l10n.findReplaceNext(WpFindReplaceBar.nextShortcutLabel),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.activeFindIndex, 1);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 11),
      );

      await tester.tap(
        find.bySemanticsLabel(
          l10n.findReplacePrevious(
            WpFindReplaceBar.previousShortcutLabel(l10n),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.activeFindIndex, 0);
    });

    testWidgets('Enter steps forward, Shift+Enter steps back', (tester) async {
      await pumpBar(tester);
      await tester.enterText(findField(), 'one');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.activeFindIndex, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(controller.activeFindIndex, 0);
    });

    // #1372: `autofocus` alone left the focus on the toggle (keyboard) or in
    // the text (mouse), so typed letters never reached the find field.
    bool findFieldFocused(WidgetTester tester) => tester
        .widget<EditableText>(
          find.descendant(of: findField(), matching: find.byType(EditableText)),
        )
        .focusNode
        .hasFocus;

    testWidgets('a tap on the toggle moves the caret from the text', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          Column(
            children: [
              WpMarkdownToolbar(controller: controller, focusNode: focusNode),
              TextField(controller: controller, focusNode: focusNode),
            ],
          ),
          locale: const Locale('en'),
        ),
      );
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel(
          l10n.findReplaceToggle(WpFindReplaceBar.openShortcutLabel(l10n)),
        ),
      );
      await tester.pumpAndSettle();
      expect(findFieldFocused(tester), isTrue);
    });

    testWidgets('Enter on the toggle puts the caret into the find field', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          WpMarkdownToolbar(controller: controller, focusNode: focusNode),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.bySemanticsIdentifier('editor-toolbar-find'),
              matching: find.byType(InkWell),
            ),
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(findFieldFocused(tester), isTrue);
    });

    // #1372: the counter as a live region reached no screen reader on macOS;
    // it is announced instead, once per change. announce() sends past
    // SemanticsService on macOS, so only the other hosts can listen in.
    testWidgets('the counter is read out once per change', (tester) async {
      await pumpBar(tester);
      tester.takeAnnouncements();
      List<String> spoken() =>
          tester.takeAnnouncements().map((a) => a.message).toList();
      final listens = defaultTargetPlatform != TargetPlatform.macOS;

      await tester.enterText(findField(), 'one');
      await tester.pumpAndSettle();
      if (listens) expect(spoken(), [l10n.findReplaceMatchCount(1, 3)]);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      if (listens) expect(spoken(), [l10n.findReplaceMatchCount(2, 3)]);

      // Editing the text elsewhere without changing the count stays silent.
      controller.text = '${controller.text} ';
      await tester.pumpAndSettle();
      if (listens) expect(spoken(), isEmpty);

      await tester.enterText(findField(), 'zzz');
      await tester.pumpAndSettle();
      if (listens) expect(spoken(), [l10n.findReplaceNoMatches]);
    });

    testWidgets('Escape closes the bar', (tester) async {
      await pumpBar(tester);
      expect(findByFieldLabel(l10n.findReplaceFindLabel), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(findByFieldLabel(l10n.findReplaceFindLabel), findsNothing);
      expect(
        controller.findMatches.isEmpty,
        isTrue,
        reason: 'a closed bar must leave no highlight behind',
      );
    });

    testWidgets('Replace swaps exactly one occurrence', (tester) async {
      await pumpBar(tester);
      await tester.enterText(findField(), 'one');
      await tester.enterText(replaceField(), 'uno');
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel(l10n.findReplaceReplaceAction));
      await tester.pumpAndSettle();

      expect(controller.text, 'uno two one two one');
      expect(
        find.text(l10n.findReplaceMatchCount(1, 2)),
        findsOneWidget,
        reason: 'two hits left, sitting on the first of them',
      );
    });

    testWidgets('Replace all swaps every occurrence', (tester) async {
      await pumpBar(tester);
      await tester.enterText(findField(), 'one');
      await tester.enterText(replaceField(), 'uno');
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel(l10n.findReplaceReplaceAllAction));
      await tester.pumpAndSettle();

      expect(controller.text, 'uno two uno two uno');
      // Right after replace all the counter says how many it swapped (#647).
      expect(find.text(l10n.findReplaceReplacedCount(3)), findsOneWidget);
    });

    testWidgets('an empty find field leaves the text alone', (tester) async {
      await pumpBar(tester);
      await tester.enterText(replaceField(), 'uno');
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsLabel(l10n.findReplaceReplaceAllAction),
        warnIfMissed: false,
      );
      await tester.tap(
        find.bySemanticsLabel(l10n.findReplaceReplaceAction),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(controller.text, 'one two one two one');
      expect(controller.findMatches.isEmpty, isTrue);
    });

    testWidgets('editing the body under an open bar re-locates the hits', (
      tester,
    ) async {
      await pumpBar(tester);
      await tester.enterText(findField(), 'one');
      await tester.pumpAndSettle();
      expect(controller.findMatches.count, 3);

      controller.text = 'one';
      await tester.pumpAndSettle();
      expect(controller.findMatches.starts, [0]);
      expect(controller.activeFindIndex, 0);
    });
  });

  group('seedFrom — the selection as a query (#647)', () {
    String? seed(String text, int start, int end) => WpFindReplaceBar.seedFrom(
      TextEditingController(text: text)
        ..selection = TextSelection(baseOffset: start, extentOffset: end),
    );

    test('takes a one-line selection, trimmed', () {
      expect(seed('say  teh  word', 4, 9), 'teh');
    });

    test('refuses collapsed, blank, multi-line and overlong selections', () {
      expect(seed('one two', 3, 3), isNull);
      expect(seed('one   two', 3, 6), isNull);
      expect(seed('one\ntwo', 0, 7), isNull);
      final long = 'x' * (WpFindReplaceBar.maxSeedLength + 1);
      expect(seed(long, 0, long.length), isNull);
    });
  });

  group('find shortcuts in the editor (#647)', () {
    late WpFindHighlightController controller;
    late FocusNode focusNode;
    late L10n l10n;

    setUpAll(() async {
      l10n = await L10n.delegate.load(const Locale('en'));
    });

    setUp(() {
      controller = WpFindHighlightController(text: 'teh one teh two teh');
      focusNode = FocusNode();
    });

    tearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    Future<void> pumpEditor(WidgetTester tester) async {
      await tester.pumpWidget(
        makeTestable(
          Material(
            child: WpTextEditor(
              testId: 'probe',
              controller: controller,
              focusNode: focusNode,
              variant: WpTextFieldVariant.form,
              minLines: 3,
              maxLines: 8,
              readView: const Text('read'),
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      focusNode.requestFocus();
      await tester.pumpAndSettle();
    }

    Future<void> chord(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      bool command = false,
      bool shift = false,
    }) async {
      if (command) await tester.sendKeyDownEvent(primaryShortcutModifier);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      if (command) await tester.sendKeyUpEvent(primaryShortcutModifier);
      await tester.pumpAndSettle();
    }

    Finder findField() => findByFieldLabel(l10n.findReplaceFindLabel);
    String query(WidgetTester tester) => tester
        .widget<EditableText>(
          find.descendant(
            of: findField().first,
            matching: find.byType(EditableText),
          ),
        )
        .controller
        .text;

    testWidgets('Ctrl/Cmd+Shift+F opens the bar with the selection as query', (
      tester,
    ) async {
      await pumpEditor(tester);
      controller.selection = const TextSelection(
        baseOffset: 8,
        extentOffset: 11,
      );
      await tester.pump();

      await chord(tester, LogicalKeyboardKey.keyF, command: true, shift: true);

      expect(findField(), findsOneWidget);
      expect(query(tester), 'teh');
      expect(controller.findMatches.starts, [0, 8, 16]);
      expect(
        controller.activeFindIndex,
        1,
        reason: 'the hit at the selection, not the first one in the text',
      );
    });

    testWidgets('Ctrl/Cmd+F is left to the list search', (tester) async {
      await pumpEditor(tester);
      await chord(tester, LogicalKeyboardKey.keyF, command: true);
      expect(findField(), findsNothing);
    });

    testWidgets('F3 opens a closed bar, then F3 / Shift+F3 step', (
      tester,
    ) async {
      await pumpEditor(tester);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      await tester.pump();

      await chord(tester, LogicalKeyboardKey.f3);
      expect(findField(), findsOneWidget);
      expect(controller.activeFindIndex, 0);

      // From the find field …
      await chord(tester, LogicalKeyboardKey.f3);
      expect(controller.activeFindIndex, 1);
      // … and from the text alike.
      focusNode.requestFocus();
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.f3);
      expect(controller.activeFindIndex, 2);
      await chord(tester, LogicalKeyboardKey.f3, shift: true);
      expect(controller.activeFindIndex, 1);
    });

    testWidgets('replace all names the count and undoes in one step', (
      tester,
    ) async {
      await pumpEditor(tester);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      await chord(tester, LogicalKeyboardKey.keyF, command: true, shift: true);
      tester.takeAnnouncements();
      await tester.enterText(
        findByFieldLabel(l10n.findReplaceReplaceLabel).first,
        'the',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel(l10n.findReplaceReplaceAllAction));
      await tester.pumpAndSettle();

      expect(controller.text, 'the one the two the');
      expect(find.text(l10n.findReplaceReplacedCount(3)), findsOneWidget);
      if (defaultTargetPlatform != TargetPlatform.macOS) {
        expect(
          tester.takeAnnouncements().map((a) => a.message),
          contains(l10n.findReplaceReplacedCount(3)),
        );
      }

      focusNode.requestFocus();
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.keyZ, command: true);
      expect(controller.text, 'teh one teh two teh');
    });
  });

  group('a search hit opens at its matches (#653)', () {
    const note = (kind: ContentKind.note, id: 'n1');
    final t0 = DateTime(2026, 11, 23, 12);

    tearDown(WpFindReveal.clear);

    test('the request goes to its own entry, once, and expires', () {
      WpFindReveal.request(note, 'teh', anchor: 8, now: t0);
      expect(
        WpFindReveal.take((kind: ContentKind.note, id: 'n2'), now: t0),
        isNull,
      );
      expect(
        WpFindReveal.take((kind: ContentKind.snippet, id: 'n1'), now: t0),
        isNull,
      );
      expect(WpFindReveal.take(note, now: t0), (query: 'teh', anchor: 8));
      expect(WpFindReveal.take(note, now: t0), isNull, reason: 'taken once');

      WpFindReveal.request(note, 'teh', now: t0);
      expect(
        WpFindReveal.take(note, now: t0.add(const Duration(seconds: 6))),
        isNull,
        reason: 'a stale search never comes back',
      );
      expect(WpFindReveal.take(note, now: t0), isNull);

      // A recording matches in either version; a blank match asks nothing.
      const recording = (kind: ContentKind.recording, id: 'r1');
      WpFindReveal.request(recording, 'x', now: t0);
      expect(
        WpFindReveal.take((
          kind: ContentKind.recordingEdited,
          id: 'r1',
        ), now: t0),
        isNotNull,
      );
      WpFindReveal.request(recording, '  ', now: t0);
      expect(WpFindReveal.take(recording, now: t0), isNull);
    });

    testWidgets('the editor of the entry tints every match, selects the one '
        'at the anchor and keeps the caret in the text', (tester) async {
      final controller = WpFindHighlightController(text: 'teh one teh two teh');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      final l10n = await L10n.delegate.load(const Locale('en'));

      WpFindReveal.request(note, 'teh', anchor: 8);
      await tester.pumpWidget(
        makeTestable(
          Material(
            child: WpTextEditor(
              testId: 'probe',
              controller: controller,
              focusNode: focusNode,
              variant: WpTextFieldVariant.form,
              minLines: 3,
              maxLines: 8,
              readView: const Text('read'),
              viewMemory: note,
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(findByFieldLabel(l10n.findReplaceFindLabel), findsOneWidget);
      expect(controller.findMatches.starts, [0, 8, 16]);
      expect(controller.activeFindIndex, 1);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 11),
      );
      expect(focusNode.hasFocus, isTrue, reason: 'typing goes on at the hit');

      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(controller.activeFindIndex, 2);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 16, extentOffset: 19),
        reason: 'stepping from the text moves the caret along',
      );
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('a request for another entry leaves the bar closed', (
      tester,
    ) async {
      final controller = WpFindHighlightController(text: 'teh one');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      final l10n = await L10n.delegate.load(const Locale('en'));

      WpFindReveal.request((kind: ContentKind.note, id: 'other'), 'teh');
      await tester.pumpWidget(
        makeTestable(
          Material(
            child: WpTextEditor(
              testId: 'probe',
              controller: controller,
              focusNode: focusNode,
              variant: WpTextFieldVariant.form,
              minLines: 3,
              maxLines: 8,
              readView: const Text('read'),
              viewMemory: note,
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(findByFieldLabel(l10n.findReplaceFindLabel), findsNothing);
    });
  });
}

/// Minimal stand-in for the [BuildContext] `buildTextSpan` is handed — the
/// highlight path never touches it (only `super` would, for the composing
/// range, which this test does not exercise).
class _NullContext extends StatelessElement {
  _NullContext() : super(const _NullWidget());
}

class _NullWidget extends StatelessWidget {
  const _NullWidget();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
