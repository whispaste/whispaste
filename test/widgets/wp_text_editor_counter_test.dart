/// The editor's status line counts (#649, #1845): what is counted, how it
/// reads, that typing recounts throttled, and the shortcut that reads the
/// counts out.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_de.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_en.dart';
import 'package:whispaste/core/text/text_stats.dart';
import 'package:whispaste/widgets/wp_text_editor.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../fixtures/test_helpers.dart';

String _plain(String s) => s.replaceAll(RegExp('[  ]'), ' ');

void main() {
  group('EditorTextStats', () {
    test('counts code points, spaces and line breaks included', () {
      expect(computeCharacterCount(''), 0);
      expect(computeCharacterCount('ab c\n'), 5);
      // One emoji outside the basic plane is one character, not two halves.
      expect(computeCharacterCount('a😀b'), 3);
      // A lone surrogate still counts.
      expect(computeCharacterCount('a\uD83D'), 2);
    });

    test('counts the selection apart from the whole text', () {
      final stats = EditorTextStats.of(
        'one two three',
        selection: const TextSelection(baseOffset: 4, extentOffset: 13),
      );
      expect(stats.words, 3);
      expect(stats.characters, 13);
      expect(stats.selectionWords, 2);
      expect(stats.selectionCharacters, 9);
      expect(stats.hasSelection, isTrue);

      final collapsed = EditorTextStats.of(
        'one two',
        selection: const TextSelection.collapsed(offset: 3),
      );
      expect(collapsed.hasSelection, isFalse);
      // A selection past the end (text shortened meanwhile) is clamped.
      final stale = EditorTextStats.of(
        'one',
        selection: const TextSelection(baseOffset: 1, extentOffset: 40),
      );
      expect(stale.selectionCharacters, 2);
    });

    test('a known word count stands in for counting', () {
      final stats = EditorTextStats.of('one two', knownWords: 1234);
      expect(stats.words, 1234);
      expect(stats.characters, 7);
      expect(stats.readingMinutes, 6);
    });
  });

  group('labels', () {
    String counter(L10n l, int words, [int chars = 10]) => _plain(
      WpTextEditor.counterLabel(
        l,
        EditorTextStats(words: words, characters: chars),
      ),
    );

    test('one word and one character read in the singular', () {
      expect(counter(L10nDe(), 1, 1), startsWith('1 Wort · 1 Zeichen ·'));
      expect(counter(L10nEn(), 1, 1), startsWith('1 word · 1 character ·'));
      expect(counter(L10nDe(), 2), startsWith('2 Wörter · 10 Zeichen ·'));
    });

    test('a short text reads under one minute', () {
      expect(counter(L10nDe(), 1), endsWith('< 1 Min. Lesezeit'));
      expect(counter(L10nDe(), 99), endsWith('< 1 Min. Lesezeit'));
      expect(counter(L10nDe(), 0), endsWith('< 1 Min. Lesezeit'));
      expect(counter(L10nDe(), 200), endsWith('1 Min. Lesezeit'));
      expect(counter(L10nDe(), 200), isNot(contains('<')));
    });

    test('the selection shows only with a selected range', () {
      final l = L10nEn();
      expect(
        WpTextEditor.selectionLabel(
          l,
          const EditorTextStats(words: 3, characters: 13),
        ),
        isNull,
      );
      expect(
        _plain(
          WpTextEditor.selectionLabel(
            l,
            const EditorTextStats(
              words: 3,
              characters: 13,
              selectionWords: 2,
              selectionCharacters: 9,
            ),
          )!,
        ),
        'Selection: 2 words · 9 characters',
      );
    });

    test('the announcement names text, selection or the empty editor', () {
      final l = L10nEn();
      expect(
        WpTextEditor.statsAnnouncement(l, EditorTextStats.empty),
        l.editorStatsEmpty,
      );
      expect(
        WpTextEditor.statsAnnouncement(
          l,
          const EditorTextStats(words: 2, characters: 7),
        ),
        '2 words, 7 characters, ${l.historyReadingTimeUnder1}.',
      );
      expect(
        WpTextEditor.statsAnnouncement(
          l,
          const EditorTextStats(
            words: 2,
            characters: 7,
            selectionWords: 1,
            selectionCharacters: 3,
          ),
        ),
        endsWith(' Selection: 1 word, 3 characters.'),
      );
    });
  });

  group('status line', () {
    late TextEditingController controller;
    late FocusNode focusNode;

    setUp(() {
      controller = TextEditingController(text: 'one two')
        ..selection = const TextSelection.collapsed(offset: 7);
      focusNode = FocusNode();
    });
    tearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    Future<void> pump(WidgetTester tester, {bool editable = true}) async {
      await tester.pumpWidget(
        makeTestable(
          Material(
            child: WpTextEditor(
              testId: 'probe',
              controller: controller,
              focusNode: focusNode,
              variant: WpTextFieldVariant.form,
              editable: editable,
              readText: 'read only text here',
              minLines: 3,
              maxLines: 5,
              readView: const Text('read'),
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
    }

    String counterText(WidgetTester tester) => _plain(
      tester
          .widget<Text>(
            find.descendant(
              of: find.bySemanticsIdentifier('probe-counter'),
              matching: find.byType(Text),
            ),
          )
          .data!,
    );

    testWidgets('typing and selecting recount after the throttle', (
      tester,
    ) async {
      await pump(tester);
      expect(find.bySemanticsIdentifier('probe-status-line'), findsOneWidget);
      expect(counterText(tester), startsWith('2 words · 7 characters'));

      controller.value = const TextEditingValue(
        text: 'one two three',
        selection: TextSelection(baseOffset: 0, extentOffset: 3),
      );
      await tester.pump(
        WpTextEditor.counterThrottle - const Duration(milliseconds: 1),
      );
      expect(counterText(tester), startsWith('2 words'));
      expect(find.bySemanticsIdentifier('probe-selection-count'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      expect(counterText(tester), startsWith('3 words · 13 characters'));
      expect(
        find.bySemanticsIdentifier('probe-selection-count'),
        findsOneWidget,
      );

      controller.clear();
      await tester.pump(WpTextEditor.counterThrottle);
      expect(find.bySemanticsIdentifier('probe-counter'), findsNothing);
    });

    testWidgets('read mode counts the read text right away', (tester) async {
      await pump(tester, editable: false);
      expect(counterText(tester), startsWith('4 words · 19 characters'));
    });

    // announce() sends past SemanticsService on macOS, so only the other
    // hosts can listen in.
    testWidgets('Ctrl/Cmd+Shift+W reads the current counts out', (
      tester,
    ) async {
      await pump(tester);
      focusNode.requestFocus();
      await tester.pump();
      tester.takeAnnouncements();
      // Read out at once, not as the throttled line last drew it.
      controller.value = const TextEditingValue(
        text: 'one two three',
        selection: TextSelection(baseOffset: 4, extentOffset: 7),
      );
      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.meta
          : LogicalKeyboardKey.control;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      if (defaultTargetPlatform == TargetPlatform.macOS) return;
      final l = L10nEn();
      expect(tester.takeAnnouncements().map((a) => a.message), [
        WpTextEditor.statsAnnouncement(
          l,
          const EditorTextStats(
            words: 3,
            characters: 13,
            selectionWords: 1,
            selectionCharacters: 3,
          ),
        ),
      ]);
    });
  });
}
