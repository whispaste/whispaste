/// Find-and-replace inside one text field — the engine and the bar.
///
/// Split the way the feature is: [WpFindReplace] is pure string work and is
/// asserted directly, while the widget group pins the four promises the bar
/// makes to a user (typing highlights, "replace" takes exactly one, "replace
/// all" takes the lot, an empty query does nothing at all).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/find_replace.dart';
import 'package:whispaste/widgets/markdown_toolbar.dart';

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
      await tester.tap(find.bySemanticsLabel(l10n.findReplaceToggle));
      await tester.pumpAndSettle();
    }

    Finder findField() =>
        find.bySemanticsLabel(l10n.findReplaceFindLabel).first;
    Finder replaceField() =>
        find.bySemanticsLabel(l10n.findReplaceReplaceLabel).first;

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
      expect(find.bySemanticsLabel(l10n.findReplaceFindLabel), findsNothing);

      await tester.tap(find.bySemanticsLabel(l10n.findReplaceToggle));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(l10n.findReplaceFindLabel), findsOneWidget);
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

      await tester.tap(find.bySemanticsLabel(l10n.findReplaceNext));
      await tester.pumpAndSettle();
      expect(controller.activeFindIndex, 1);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 11),
      );

      await tester.tap(find.bySemanticsLabel(l10n.findReplacePrevious));
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

    testWidgets('Escape closes the bar', (tester) async {
      await pumpBar(tester);
      expect(find.bySemanticsLabel(l10n.findReplaceFindLabel), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(l10n.findReplaceFindLabel), findsNothing);
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
      expect(find.text(l10n.findReplaceNoMatches), findsOneWidget);
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
