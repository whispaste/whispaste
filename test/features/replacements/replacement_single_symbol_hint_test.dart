// A trigger that is one punctuation mark (such as `?`) never fires. The
// dialog says so while the user types, but it never blocks the save.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/ltr_isolate.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

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
    expect(
      find.text(
        l10n.replacementsSingleSymbolTriggerHint(
          ltrIsolate(':)'),
          ltrIsolate('...'),
        ),
      ),
      findsOneWidget,
    );
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
    await tester.tap(find.text(l10n.replacementsMatchModeFuzzy));
    await tester.pumpAndSettle();

    expect(hintKey, findsOneWidget);
  });

  testWidgets('the hint does not block saving', (tester) async {
    await openNewDialog(tester);

    await tester.enterText(find.byType(TextField).at(1), '?');
    await tester.enterText(find.byType(TextField).at(2), 'question mark');
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.replacementsAdd).last);
    await tester.pumpAndSettle();

    expect(hintKey, findsNothing, reason: 'the dialog must have closed');
    expect(find.text(l10n.replacementsFuzzyTooShortWarning(4)), findsNothing);
  });
}
