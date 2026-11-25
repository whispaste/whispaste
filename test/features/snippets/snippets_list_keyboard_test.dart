// UIA-R-SNP-019: the snippets list is managed by keyboard alone. The arrow keys
// move a row cursor, Enter shows the row in the detail beside the list, Esc
// closes the detail, and Esc in the list hands the caret back to the search
// field (page family, #1184).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/features/snippets/widgets/snippet_editor.dart';

import '../../fixtures/test_helpers.dart';

/// The add/edit editor's fields, found by their keys rather than by position
/// on the page (the page itself holds a search field only).
final _titleField = find.descendant(
  of: find.byKey(const ValueKey('snippets-title-field')),
  matching: find.byType(EditableText),
);
final _bodyField = find.descendant(
  of: find.byKey(const ValueKey('snippets-body-field')),
  matching: find.byType(EditableText),
);

Future<void> _addSnippet(
  WidgetTester tester,
  L10n l10n, {
  required String title,
  required String text,
}) async {
  await tester.tap(find.byIcon(LucideIcons.plus));
  await tester.pumpAndSettle();
  await tester.enterText(_titleField, title);
  await tester.enterText(_bodyField, text);
  await tester.pump(SnippetEditor.autosaveDelay);
  await tester.pumpAndSettle();
  // The editor stays open after its autosave (#1498); Esc leaves it.
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

/// Title of the snippet currently shown in the detail.
String _openTitle(WidgetTester tester) =>
    tester.widget<SnippetEditor>(_detail).existing!.title;

final _detail = find.byType(SnippetEditor);

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('arrow keys move the row cursor, Enter opens the row, Esc '
      'closes the detail and returns the caret to search (UIA-R-SNP-019)', (
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
    expect(_detail, findsOneWidget);
    final first = _openTitle(tester);
    expect({'Greeting', 'Signature'}, contains(first));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_detail, findsNothing);

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
    for (final id in ['snippets-editor', 'snippets-detail']) {
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.identifier == id,
        ),
        findsNothing,
        reason: id,
      );
    }
  });

  testWidgets('New puts the caret in the title field (#1845)', (tester) async {
    await tester.pumpWidget(makeTestable(const SnippetsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(_titleField).focusNode.hasFocus, isTrue);
  });
}
