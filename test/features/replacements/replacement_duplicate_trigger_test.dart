// UIA-DIC-06: a new entry that reuses an existing trigger is refused with a
// message that names the entry already holding it, instead of being stored
// as a silent second owner of the same phrase.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('a duplicate trigger is refused and the dialog stays open', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const ReplacementsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
    // The first-start samples include "lg" -> "Liebe Grüße".
    await tester.enterText(find.byType(TextField).at(1), 'LG');
    await tester.enterText(find.byType(TextField).at(2), 'love, x');
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.replacementsAdd).last);
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.replacementsDuplicateTrigger('lg', 'Liebe Grüße')),
      findsOneWidget,
    );
    expect(find.text(l10n.replacementsAdd), findsWidgets);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
