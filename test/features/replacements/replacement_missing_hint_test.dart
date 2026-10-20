/// UIA-DIC-07: the disabled save button of the replacement dialog says which
/// field is still missing, as visible text.
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

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestable(const ReplacementsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty dialog asks for the trigger phrase first', (
    tester,
  ) async {
    await openDialog(tester);

    expect(find.text(l10n.replacementsMissingTrigger), findsOneWidget);
    expect(find.text(l10n.replacementsMissingReplacement), findsNothing);
  });

  testWidgets('after a trigger, the hint asks for the replacement text', (
    tester,
  ) async {
    await openDialog(tester);

    // TextFields in tree order: [0] page search, [1] trigger, [2] replacement
    await tester.enterText(find.byType(TextField).at(1), 'hallo');
    await tester.pumpAndSettle();

    expect(find.text(l10n.replacementsMissingTrigger), findsNothing);
    expect(find.text(l10n.replacementsMissingReplacement), findsOneWidget);
  });
}
