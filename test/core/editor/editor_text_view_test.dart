/// The editors' shared text view (#648): fixed text size steps, line length
/// and spacing, stored once for recordings, notes and snippets.
library;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/editor/editor_text_view.dart';
import 'package:whispaste/widgets/editor_text_view_scope.dart';
import 'package:whispaste/widgets/wp_text_editor.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../../fixtures/test_helpers.dart';

Future<void> _pressCommand(WidgetTester tester, LogicalKeyboardKey key) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  group('EditorTextView', () {
    test('text size walks the fixed steps and holds at the ends', () {
      var view = EditorTextView.standard;
      expect(view.textSize, 100);
      view = view.stepTextSize(1);
      expect(view.textSize, 110);
      view = view.stepTextSize(-1).stepTextSize(-1).stepTextSize(-1);
      expect(view.textSize, EditorTextView.textSizes.first);
      expect(view.canShrink, isFalse);
      for (var i = 0; i < 20; i++) {
        view = view.stepTextSize(1);
      }
      expect(view.textSize, 300);
      expect(view.canGrow, isFalse);
      expect(EditorTextView.textSizes, contains(200));
    });

    test('encode and decode round-trip, bad parts fall back alone', () {
      for (final size in EditorTextView.textSizes) {
        for (final length in EditorLineLength.values) {
          for (final spacing in EditorLineSpacing.values) {
            final view = EditorTextView(
              textSize: size,
              lineLength: length,
              lineSpacing: spacing,
            );
            expect(EditorTextView.decode(view.encode()), view);
          }
        }
      }
      expect(EditorTextView.decode(null), EditorTextView.standard);
      expect(EditorTextView.decode(''), EditorTextView.standard);
      // A size off the steps (an old or edited value) is not taken over.
      expect(
        EditorTextView.decode('133:wide:bogus'),
        const EditorTextView(lineLength: EditorLineLength.wide),
      );
      expect(
        EditorTextView.decode('150:bogus:relaxed'),
        const EditorTextView(
          textSize: 150,
          lineSpacing: EditorLineSpacing.relaxed,
        ),
      );
    });

    test('the standard keeps today\'s full width; caps grow with size', () {
      expect(EditorTextView.standard.maxWidthFor(16), isNull);
      const medium = EditorTextView(lineLength: EditorLineLength.medium);
      expect(medium.maxWidthFor(16), closeTo(720, 1));
      expect(medium.maxWidthFor(32), closeTo(1440, 2));
    });

    test('the chosen view is stored and read back', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      ProviderContainer container() => ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWithValue(db)],
      );

      final first = container();
      await first.read(editorTextViewProvider.future);
      const chosen = EditorTextView(
        textSize: 200,
        lineLength: EditorLineLength.narrow,
        lineSpacing: EditorLineSpacing.compact,
      );
      await first.read(editorTextViewProvider.notifier).choose(chosen);
      first.dispose();

      final second = container();
      addTearDown(second.dispose);
      expect(await second.read(editorTextViewProvider.future), chosen);
    });
  });

  group('editor block', () {
    late TextEditingController controller;
    late FocusNode focusNode;

    setUp(() {
      controller = TextEditingController(text: 'hello');
      focusNode = FocusNode();
    });
    tearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        makeTestable(
          Material(
            child: WpTextEditor(
              testId: 'probe',
              controller: controller,
              focusNode: focusNode,
              variant: WpTextFieldVariant.bare,
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
    }

    double bodyScale(WidgetTester tester) =>
        MediaQuery.textScalerOf(
          tester.element(find.byType(EditableText)),
        ).scale(10) /
        10;

    testWidgets(
      'shortcuts step the shared size; only the body scales',
      (tester) async {
        await pump(tester);
        focusNode.requestFocus();
        await tester.pump();
        final base = bodyScale(tester);
        final originalEditor = tester.state(find.byType(EditableText));
        controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 4,
        );

        await _pressCommand(tester, LogicalKeyboardKey.equal);
        await _pressCommand(tester, LogicalKeyboardKey.equal);
        await tester.pumpAndSettle();
        expect(bodyScale(tester), closeTo(base * 1.25, 0.001));
        expect(find.text('125% – reset'), findsOneWidget);
        // The toolbar keeps its size.
        final toolbar = tester.element(
          find.bySemanticsIdentifier('probe-toolbar-text-view'),
        );
        expect(
          MediaQuery.textScalerOf(toolbar).scale(10) / 10,
          closeTo(base, 0.001),
        );

        // At 200% the body grows while tools remain reachable and unscaled.
        for (var i = 0; i < 3; i++) {
          await _pressCommand(tester, LogicalKeyboardKey.equal);
        }
        await tester.pumpAndSettle();
        expect(bodyScale(tester), closeTo(base * 2, 0.001));
        expect(
          find.bySemanticsIdentifier('probe-toolbar-text-view').hitTestable(),
          findsOneWidget,
        );
        expect(MediaQuery.textScalerOf(toolbar).scale(10) / 10, base);
        expect(controller.text, 'hello');
        expect(tester.state(find.byType(EditableText)), same(originalEditor));
        expect(focusNode.hasFocus, isTrue);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );

        await _pressCommand(tester, LogicalKeyboardKey.digit0);
        await tester.pumpAndSettle();
        expect(bodyScale(tester), closeTo(base, 0.001));
        expect(find.text('125% – reset'), findsNothing);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }),
    );

    testWidgets('width and spacing changes preserve the active editor', (
      tester,
    ) async {
      await pump(tester);
      focusNode.requestFocus();
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      final original = tester.state(find.byType(EditableText));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(EditableText)),
      );
      for (final length in [EditorLineLength.narrow, EditorLineLength.full]) {
        container
            .read(editorTextViewProvider.notifier)
            .choose(
              EditorTextView(
                lineLength: length,
                lineSpacing: EditorLineSpacing.relaxed,
              ),
            );
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(EditableText)), same(original));
        expect(focusNode.hasFocus, isTrue);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );
      }
    });

    testWidgets('all editor bodies share the size on top of system scaling', (
      tester,
    ) async {
      final secondController = TextEditingController(text: 'another entry');
      final secondFocus = FocusNode();
      addTearDown(secondController.dispose);
      addTearDown(secondFocus.dispose);
      await tester.pumpWidget(
        makeTestable(
          MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.5),
              disableAnimations: true,
            ),
            child: Material(
              child: Row(
                children: [
                  Expanded(
                    child: WpTextEditor(
                      testId: 'first',
                      controller: controller,
                      focusNode: focusNode,
                      variant: WpTextFieldVariant.bare,
                    ),
                  ),
                  Expanded(
                    child: WpTextEditor(
                      testId: 'second',
                      controller: secondController,
                      focusNode: secondFocus,
                      variant: WpTextFieldVariant.bare,
                    ),
                  ),
                ],
              ),
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(EditableText).first),
      );
      container
          .read(editorTextViewProvider.notifier)
          .choose(const EditorTextView(textSize: 200));
      await tester.pumpAndSettle();
      for (final element in find.byType(EditableText).evaluate()) {
        expect(MediaQuery.textScalerOf(element).scale(10), 30);
        expect(MediaQuery.disableAnimationsOf(element), isTrue);
      }
      for (final id in ['first', 'second']) {
        // In a narrow half the last buttons sit under "More" (#1845); the
        // bar's end stays reachable and unscaled either way.
        final textView = find.bySemanticsIdentifier('$id-toolbar-text-view');
        final toolbar = textView.evaluate().isNotEmpty
            ? textView
            : find.bySemanticsIdentifier('$id-toolbar-more');
        expect(toolbar.hitTestable(), findsOneWidget);
        expect(MediaQuery.textScalerOf(tester.element(toolbar)).scale(10), 15);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the toolbar menu sets size, line length and spacing', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.bySemanticsIdentifier('probe-toolbar-text-view'));
      await tester.pumpAndSettle();
      for (final id in [
        'editor-text-view-larger',
        'editor-text-view-smaller',
        'editor-text-view-reset',
        'editor-text-view-line-narrow',
        'editor-text-view-spacing-relaxed',
      ]) {
        expect(find.byKey(ValueKey(id)), findsOneWidget, reason: id);
      }
      await tester.tap(
        find.byKey(const ValueKey('editor-text-view-spacing-relaxed')),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(EditableText));
      final view = WpEditorText.maybeOf(context)!;
      expect(view.lineSpacing, EditorLineSpacing.relaxed);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.style.height, EditorLineSpacing.relaxed.factor);
    });
  });
}
