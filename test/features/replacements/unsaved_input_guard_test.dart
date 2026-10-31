// UIA-CMP-03: a form dialog with typed input asks before a dismiss throws it
// away; an untouched dialog closes at once.
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

  Future<void> openAddDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestable(const ReplacementsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
  }

  testWidgets('dismissing a dialog with typed input asks first and keeps it '
      'when the user keeps editing (UIA-CMP-03)', (tester) async {
    await openAddDialog(tester);
    await tester.enterText(find.byType(TextField).at(1), 'omw');
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(l10n.unsavedInputTitle), findsOneWidget);

    await tester.tap(find.text(l10n.actionCancel).last);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(l10n.unsavedInputTitle), findsNothing);
    expect(find.text(l10n.replacementsNewShortcut), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'omw',
    );
  });

  testWidgets('dismissing an untouched dialog closes without asking', (
    tester,
  ) async {
    await openAddDialog(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(l10n.unsavedInputTitle), findsNothing);
    expect(find.text(l10n.replacementsNewShortcut), findsNothing);
  });
}
