// UIA-DIC-05: a "Similar" entry whose trigger shrinks below the fuzzy minimum
// is not saved as exact silently. The save stops, the match mode visibly
// switches to exact, and the user is told why.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('shrinking a Similar trigger below the minimum stops the save', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const ReplacementsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'gruesse');
    await tester.enterText(find.byType(TextField).at(2), 'greetings');
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.replacementsMatchModeFuzzy));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'ok');
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.replacementsAdd).last);
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.replacementsFuzzyTooShortWarning(fuzzyMinTriggerLength)),
      findsWidgets,
      reason: 'the reason must be visible, not only inline',
    );
    expect(
      find.text(l10n.replacementsAdd),
      findsWidgets,
      reason: 'the dialog must stay open so the user can correct the trigger',
    );

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
