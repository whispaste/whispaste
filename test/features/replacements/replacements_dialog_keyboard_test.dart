// UIA-R-DIC-012 and UIA-R-DIC-020: the replacement dialog is operable by
// keyboard alone. Esc closes an untouched dialog and asks before it discards
// typed input, the safe button holds focus while that question is open, and
// Enter in a field saves a complete entry but never a half-filled one.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';

import '../../fixtures/test_helpers.dart';

final _triggerField = find.descendant(
  of: find.byKey(const ValueKey('replacements-trigger-field-0')),
  matching: find.byType(EditableText),
);

final _replacementField = find.descendant(
  of: find.byKey(const ValueKey('replacements-replacement-field')),
  matching: find.byType(EditableText),
);

Future<void> _openAddDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    makeTestable(const ReplacementsPage(), locale: const Locale('en')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(LucideIcons.plus));
  await tester.pumpAndSettle();
}

void main() {
  group('replacement dialog keyboard (UIA-R-DIC-012, UIA-R-DIC-020)', () {
    testWidgets('Esc closes an untouched dialog at once (UIA-R-DIC-012)', (
      tester,
    ) async {
      await _openAddDialog(tester);
      expect(find.byKey(const ValueKey('replacements-save')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('replacements-save')), findsNothing);
      expect(
        find.byKey(const ValueKey('confirm-dialog-confirm')),
        findsNothing,
      );
    });

    testWidgets(
      'Esc with typed input asks first and a reflexive Enter never discards '
      'it (UIA-R-DIC-012)',
      (tester) async {
        await _openAddDialog(tester);
        await tester.enterText(_triggerField, 'omw');
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('confirm-dialog-confirm')),
          findsOneWidget,
        );

        // Destructive confirm: Enter does not answer it, so a reflexive Enter
        // keeps the typed text; Esc then returns to the form.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('confirm-dialog-confirm')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('replacements-save')), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('confirm-dialog-confirm')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('replacements-save')), findsOneWidget);
      },
    );

    testWidgets('Enter in a field saves a complete entry and closes the dialog '
        '(UIA-R-DIC-020)', (tester) async {
      await _openAddDialog(tester);
      await tester.enterText(_triggerField, 'omw');
      await tester.enterText(_replacementField, 'on my way');
      await tester.pumpAndSettle();

      // A physical Enter in a text field reaches the field as its text-input
      // action; sendKeyEvent alone does not trigger onSubmitted in tests.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('replacements-save')), findsNothing);
      // The new row may sit outside the viewport, so filter down to it. Only
      // Text widgets count: the search field's own text would match too.
      await tester.enterText(find.byType(TextField).first, 'omw');
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').contains('omw'),
        ),
        findsWidgets,
      );
    });

    testWidgets('Enter with an incomplete entry keeps the dialog open '
        '(UIA-R-DIC-020)', (tester) async {
      await _openAddDialog(tester);
      await tester.enterText(_triggerField, 'omw');
      await tester.pumpAndSettle();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('replacements-save')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('confirm-dialog-confirm')),
        findsNothing,
      );
    });
  });

  // Consistency 133: the form's scroll body is the only scroller around the
  // trigger rows, so a long trigger list never nests a second scroll box.
  testWidgets('trigger rows scroll with the form, exactly one scroller', (
    tester,
  ) async {
    await _openAddDialog(tester);
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const ValueKey('replacements-trigger-add')));
      await tester.pumpAndSettle();
    }

    final last = find.byKey(const ValueKey('replacements-trigger-field-6'));
    expect(
      find.ancestor(of: last, matching: find.byType(Scrollable)),
      findsOneWidget,
    );
    // The added field took focus, and the one scroller brought it into view.
    final editable = find.descendant(
      of: last,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    expect(last.hitTestable(), findsOneWidget);
  });
}
