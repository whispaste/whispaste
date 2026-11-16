// UIA-SNP-02: a snippet that fails to save keeps the editor open with the
// typed input and tells the user, instead of closing as if it were stored.
// The editor sits in the detail since #864.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/features/snippets/widgets/snippet_editor.dart';

import '../../fixtures/test_helpers.dart';

class _FailingSnippetsNotifier extends SnippetsNotifier {
  @override
  Future<String> add(
    String title,
    String body, {
    String kind = 'static',
    List<String> fields = const [],
  }) async {
    throw StateError('database is locked');
  }
}

void main() {
  testWidgets('a snippet that fails to save keeps the editor open and reports '
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

    // The autosave pause runs into the failing write (#1498).
    await tester.pump(SnippetEditor.autosaveDelay);
    await tester.pumpAndSettle();

    expect(find.byType(SnippetEditor), findsOneWidget);
    expect(
      tester.widget<EditableText>(titleField).controller.text,
      'Signature',
    );
    expect(
      find.byKey(const ValueKey('snippets-editor-save-failed')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
