// #864, #1498: a snippet is written in place in the detail, not in a modal
// dialog. A valid state saves itself; an invalid one never goes away by
// closing the editor — it stays a draft until it is valid or reverted.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/features/snippets/snippet_draft.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/features/snippets/widgets/snippet_editor.dart';

import '../../fixtures/test_helpers.dart';

/// A widget keyed with [id] or carrying it as its semantics identifier
/// (testId of the shared buttons); the key a button puts on its inner KeyedSubtree is skipped.
Finder _byId(String id) => find.byWidgetPredicate(
  (w) =>
      (w.key == ValueKey<String>(id) && w is! KeyedSubtree) ||
      (w is Semantics && w.properties.identifier == id),
);

Finder _field(String id) =>
    find.descendant(of: _byId(id), matching: find.byType(EditableText));

String _text(WidgetTester tester, String id) =>
    tester.widget<EditableText>(_field(id)).controller.text;

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SnippetsPage)));

void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestable(const SnippetsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a closed invalid new snippet keeps its draft as a list row, '
      'reopens with the text, and saves once it is valid', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
    expect(_byId('snippets-editor'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing, reason: 'no modal dialog');

    // A title without text is no valid snippet: closing keeps it as draft.
    await tester.enterText(_field('snippets-title-field'), 'Signature');
    await tester.pumpAndSettle();
    await tester.tap(_byId('snippets-editor-close'));
    await tester.pumpAndSettle();
    expect(_byId('snippets-editor'), findsNothing);
    expect(_byId('snippets-draft-row'), findsOneWidget);
    expect(_container(tester).read(snippetsProvider).value, isEmpty);

    await tester.tap(_byId('snippets-draft-row'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'snippets-title-field'), 'Signature');
    expect(
      find.byKey(const ValueKey('snippets-editor-invalid')),
      findsOneWidget,
    );

    await tester.enterText(_field('snippets-body-field'), 'Best,\nSilvio');
    await tester.pump(SnippetEditor.autosaveDelay);
    await tester.pumpAndSettle();

    final container = _container(tester);
    expect(container.read(snippetDraftsProvider), isEmpty);
    final stored = container.read(snippetsProvider).value!;
    expect(stored.map((s) => (s.title, s.body)), [
      ('Signature', 'Best,\nSilvio'),
    ]);
    expect(_byId('snippets-draft-row'), findsNothing);
    expect(_byId('snippets-editor'), findsOneWidget, reason: 'stays open');
  });

  testWidgets('an invalid edit of a stored snippet stays a draft with a '
      'marked row; reverting restores the stored text', (tester) async {
    await pumpPage(tester);
    final notifier = _container(tester).read(snippetsProvider.notifier);
    final id = await tester.runAsync(() => notifier.add('Greeting', 'Hi'));
    await tester.pumpAndSettle();

    // A stored snippet opens straight in its editor (#1498).
    await tester.tap(_byId('snippets-row-$id'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('snippets-body-field'), '');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_byId('snippets-editor'), findsNothing);
    expect(_byId('snippets-draft-badge-$id'), findsOneWidget);
    expect(_container(tester).read(snippetDraftsProvider)[id!]?.body, '');
    expect(_container(tester).read(snippetsProvider).value!.single.body, 'Hi');

    await tester.tap(_byId('snippets-row-$id'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'snippets-body-field'), '');
    expect(
      find.byKey(const ValueKey('snippets-editor-invalid')),
      findsOneWidget,
    );

    await tester.tap(_byId('snippets-editor-revert'));
    await tester.pumpAndSettle();

    final container = _container(tester);
    expect(_text(tester, 'snippets-body-field'), 'Hi');
    expect(container.read(snippetDraftsProvider), isEmpty);
    expect(_byId('snippets-draft-badge-$id'), findsNothing);
    expect(container.read(snippetsProvider).value!.single.body, 'Hi');
  });
}
