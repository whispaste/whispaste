// UIA-DIC-03: a replacement that fails to save keeps the dialog open with the
// typed input and tells the user, instead of closing as if it were stored.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

import '../../fixtures/test_helpers.dart';

class _FailingReplacementsNotifier extends ReplacementsNotifier {
  @override
  Future<void> add(
    List<String> triggers,
    String replacement, {
    TextReplacementMatchMode matchMode = TextReplacementMatchMode.exact,
    double? fuzzyThreshold,
    String origin = 'manual',
  }) async {
    throw StateError('database is locked');
  }
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('a replacement that fails to save keeps the dialog open and '
      'reports the error (UIA-DIC-03)', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        const ReplacementsPage(),
        locale: const Locale('en'),
        overrides: [
          replacementsProvider.overrideWith(
            () => _FailingReplacementsNotifier(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
    // TextFields: [0] page search, [1] trigger, [2] replacement.
    await tester.enterText(find.byType(TextField).at(1), 'omw');
    await tester.enterText(find.byType(TextField).at(2), 'on my way');
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.replacementsAdd).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.replacementsAdd), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'omw',
    );
    expect(find.text(l10n.errorGeneric), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
