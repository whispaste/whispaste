/// The snippet dialog says why Save is disabled (UIA-SNP-04) and refuses two
/// interactive fields with the same name (UIA-SNP-05).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  Future<void> openDialog(
    WidgetTester tester, {
    required bool interactive,
  }) async {
    await tester.pumpWidget(
      makeTestable(const SnippetsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(
        interactive ? l10n.snippetsKindInteractive : l10n.snippetsKindStatic,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The editable inside the [WpTextField] that shows [hint].
  Finder fieldByHint(String hint) => find.descendant(
    of: find.byWidgetPredicate((w) => w is WpTextField && w.hintText == hint),
    matching: find.byType(TextField),
  );

  bool saveDisabled(WidgetTester tester) => tester
      .widgetList<WpButton>(find.byType(WpButton))
      .any((b) => b.label == l10n.snippetsAdd && b.onPressed == null);

  testWidgets('an empty title shows why Save is disabled', (tester) async {
    final handle = tester.ensureSemantics();
    await openDialog(tester, interactive: false);

    expect(saveDisabled(tester), isTrue);
    expect(find.text(l10n.snippetsSaveMissingTitle), findsOneWidget);
    handle.dispose();
    await tester.pumpAndSettle(const Duration(seconds: 11));
  });

  testWidgets('a title without text shows the missing-text reason', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await openDialog(tester, interactive: false);

    await tester.enterText(
      fieldByHint(l10n.snippetsTitleHint),
      'Email signature',
    );
    await tester.pumpAndSettle();

    expect(saveDisabled(tester), isTrue);
    expect(find.text(l10n.snippetsSaveMissingBody), findsOneWidget);
    expect(find.text(l10n.snippetsSaveMissingTitle), findsNothing);
    handle.dispose();
    await tester.pumpAndSettle(const Duration(seconds: 11));
  });

  testWidgets('two interactive fields with the same name block Save', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await openDialog(tester, interactive: true);

    await tester.enterText(fieldByHint(l10n.snippetsTitleHint), 'Bug Report');
    await tester.enterText(fieldByHint(l10n.snippetsFieldNameHint(1)), 'Titel');
    await tester.tap(find.text(l10n.snippetsFieldAdd));
    await tester.pumpAndSettle();
    await tester.enterText(fieldByHint(l10n.snippetsFieldNameHint(2)), 'Titel');
    await tester.pumpAndSettle();

    expect(find.text(l10n.snippetsFieldsDuplicateWarning), findsOneWidget);
    expect(saveDisabled(tester), isTrue);
    handle.dispose();
    await tester.pumpAndSettle(const Duration(seconds: 11));
  });
}
