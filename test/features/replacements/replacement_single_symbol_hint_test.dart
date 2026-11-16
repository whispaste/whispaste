// A trigger that is one punctuation mark (such as `?`) never fires. The
// dialog says so while the user types, but it never blocks the save.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';
import 'package:whispaste/widgets/wp_segmented_selector.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  final hintKey = find.byKey(const ValueKey('replacements-single-symbol-hint'));

  Future<void> openNewDialog(WidgetTester tester, {Locale? locale}) async {
    await tester.pumpWidget(
      makeTestable(
        const ReplacementsPage(),
        locale: locale ?? const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
  }

  testWidgets('a single punctuation trigger shows the hint', (tester) async {
    await openNewDialog(tester);

    await tester.enterText(find.byType(TextField).at(1), '?');
    await tester.pumpAndSettle();

    expect(hintKey, findsOneWidget);
  });

  testWidgets('a symbol trigger of two characters shows no hint', (
    tester,
  ) async {
    await openNewDialog(tester);

    await tester.enterText(find.byType(TextField).at(1), '->');
    await tester.pumpAndSettle();
    expect(hintKey, findsNothing);

    await tester.enterText(find.byType(TextField).at(1), '...');
    await tester.pumpAndSettle();
    expect(hintKey, findsNothing);
  });

  testWidgets('a trigger with letters or digits shows no hint', (tester) async {
    await openNewDialog(tester);

    await tester.enterText(find.byType(TextField).at(1), 'a');
    await tester.pumpAndSettle();
    expect(hintKey, findsNothing);

    await tester.enterText(find.byType(TextField).at(1), '7?');
    await tester.pumpAndSettle();
    expect(hintKey, findsNothing);
  });

  testWidgets('the hint appears once in Similar mode', (tester) async {
    await openNewDialog(tester);

    await tester.enterText(find.byType(TextField).at(1), 'gruesse');
    await tester.tap(find.byKey(const ValueKey('replacements-trigger-add')));
    await tester.pumpAndSettle();
    // [1] trigger 1, [2] trigger 2, [3] replacement
    await tester.enterText(find.byType(TextField).at(2), '?');
    await tester.enterText(find.byType(TextField).at(3), 'greetings');
    await tester.pumpAndSettle();
    tester
        .widget<WpSegmentedChoice<TextReplacementMatchMode>>(
          find.byKey(const ValueKey('replacements-match-mode-choice')),
        )
        .onChanged(TextReplacementMatchMode.fuzzy);
    await tester.pumpAndSettle();

    expect(hintKey, findsOneWidget);
  });

  testWidgets('the hint does not block saving', (tester) async {
    await openNewDialog(tester);

    await tester.enterText(find.byType(TextField).at(1), '?');
    await tester.enterText(find.byType(TextField).at(2), 'question mark');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('replacements-save')));
    await tester.pumpAndSettle();

    expect(hintKey, findsNothing, reason: 'the dialog must have closed');
    expect(
      find.byKey(const ValueKey('replacements-dialog-problem-fuzzy-too-short')),
      findsNothing,
    );
  });
}
