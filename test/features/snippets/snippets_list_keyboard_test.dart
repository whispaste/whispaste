// UIA-R-SNP-019: the snippets list is managed by keyboard alone. The arrow keys
// move a row cursor, Enter opens the row, Esc closes the dialog without a
// change, and Esc in the list hands the caret back to the search field.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';

import '../../fixtures/test_helpers.dart';

/// The picker-trigger field precedes the search field where the picker
/// exists on this platform, as in `snippets_page_test.dart`.
final _fieldOffset = snippetPickerAvailableOnPlatform ? 1 : 0;

Future<void> _addSnippet(
  WidgetTester tester,
  L10n l10n, {
  required String title,
  required String text,
}) async {
  await tester.tap(find.byIcon(LucideIcons.plus));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(_fieldOffset + 1), title);
  await tester.enterText(find.byType(TextField).at(_fieldOffset + 2), text);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.snippetsAdd).last);
  await tester.pumpAndSettle();
}

/// Title of the snippet currently open in the edit dialog: the first field
/// after the page's own fields, as in the add-dialog tests.
String _openTitle(WidgetTester tester) => tester
    .widget<TextField>(find.byType(TextField).at(_fieldOffset + 1))
    .controller!
    .text;

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('arrow keys move the row cursor, Enter opens the row, Esc '
      'closes the dialog and returns the caret to search (UIA-R-SNP-019)', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const SnippetsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await _addSnippet(tester, l10n, title: 'Greeting', text: 'Hi there');
    await _addSnippet(tester, l10n, title: 'Signature', text: 'Best regards');

    // ArrowDown takes the caret out of search and onto the first row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(l10n.snippetsEditSnippet), findsOneWidget);
    final first = _openTitle(tester);
    expect({'Greeting', 'Signature'}, contains(first));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(l10n.snippetsEditSnippet), findsNothing);

    // The second ArrowDown moves to the other row, not the same one.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final second = _openTitle(tester);
    expect(second, isNot(first));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Esc with the cursor live hands the caret back to the search field.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused?.findAncestorWidgetOfExactType<TextField>(), isNotNull);
  });

  testWidgets('Esc in the search field, unlike Esc in the list, does not '
      'open anything (UIA-R-SNP-019)', (tester) async {
    await tester.pumpWidget(
      makeTestable(const SnippetsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(l10n.snippetsEditSnippet), findsNothing);
    expect(find.text(l10n.snippetsNewSnippet), findsNothing);
  });
}
