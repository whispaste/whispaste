// UIA-SNP-02: a snippet that fails to save keeps the dialog open with the
// typed input and tells the user, instead of closing as if it were stored.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';

import '../../fixtures/test_helpers.dart';

class _FailingSnippetsNotifier extends SnippetsNotifier {
  @override
  Future<void> add(
    String title,
    String body, {
    String kind = 'static',
    List<String> fields = const [],
  }) async {
    throw StateError('database is locked');
  }
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('a snippet that fails to save keeps the dialog open and reports '
      'the error (UIA-SNP-02)', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        const SnippetsPage(),
        locale: const Locale('en'),
        overrides: [
          snippetsProvider.overrideWith(() => _FailingSnippetsNotifier()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
    final titleField = find.descendant(
      of: find.byKey(const ValueKey('snippets-title-field')),
      matching: find.byType(EditableText),
    );
    final bodyField = find.descendant(
      of: find.byKey(const ValueKey('snippets-body-field')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(titleField, 'Signature');
    await tester.enterText(bodyField, 'Best,\nSilvio');
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.snippetsAdd).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.snippetsAdd), findsWidgets);
    expect(
      tester.widget<EditableText>(titleField).controller.text,
      'Signature',
    );
    expect(find.text(l10n.errorGeneric), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
