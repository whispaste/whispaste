// Snippets follow the collection page family (#919, #1184): the shared
// landmarks, the toolbar places and a detail beside the list, each control
// reachable by its stable id.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/features/snippets/widgets/snippet_editor.dart';

import '../../fixtures/test_helpers.dart';

Finder _byId(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

/// The list row(s) of trashed snippets, addressed by their key prefix.
Finder _trashRows() => find.byWidgetPredicate((w) {
  final k = w.key;
  return k is ValueKey<String> && k.value.startsWith('snippets-trash-row-');
});

/// The list row(s) of stored snippets, addressed by their key prefix.
Finder _rows() => find.byWidgetPredicate((w) {
  final k = w.key;
  return k is ValueKey<String> &&
      (k.value.startsWith('snippets-row-') ||
          k.value.startsWith('snippets-trash-row-'));
});

Future<void> _addSnippet(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.plus));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('snippets-title-field')),
      matching: find.byType(EditableText),
    ),
    'Greeting',
  );
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('snippets-body-field')),
      matching: find.byType(EditableText),
    ),
    'Hi there',
  );
  // Snippets save themselves once the typing pauses (#1498).
  await tester.pump(SnippetEditor.autosaveDelay);
  await tester.pumpAndSettle();
}

/// A wide window: below `WpCollectionPage.inlineToolsMinWidth` the view
/// tools collapse into an overflow menu.
void _wide(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 900);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('landmarks, toolbar places and detail actions carry ids', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(
      makeTestable(const SnippetsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await _addSnippet(tester);

    for (final id in [
      'snippets-page',
      'snippets-toolbar',
      'snippets-list-area',
      'snippets-filter-menu',
      'snippets-select-toggle',
      'snippets-sort',
    ]) {
      expect(_byId(id), findsOneWidget, reason: id);
    }

    await tester.tap(_rows().first);
    await tester.pumpAndSettle();
    // A stored snippet opens straight in its editor (#1498).
    for (final id in [
      'snippets-editor',
      'snippets-detail-copy',
      'snippets-detail-favourite',
      'snippets-detail-delete',
      'snippets-detail-more',
      'snippets-editor-close',
    ]) {
      expect(_byId(id), findsOneWidget, reason: id);
    }
    await tester.tap(_byId('snippets-detail-more'));
    await tester.pumpAndSettle();
    expect(_byId('snippets-detail-duplicate'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(_byId('snippets-editor-close'));
    await tester.pumpAndSettle();
    expect(_byId('snippets-editor'), findsNothing);
  });

  testWidgets('the select toggle turns selection mode on and off', (
    tester,
  ) async {
    _wide(tester);
    await tester.pumpWidget(
      makeTestable(const SnippetsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await _addSnippet(tester);

    await tester.tap(_byId('snippets-select-toggle'));
    await tester.pumpAndSettle();
    expect(_byId('snippets-multiselect-cancel'), findsOneWidget);

    await tester.tap(_byId('snippets-select-toggle'));
    await tester.pumpAndSettle();
    expect(_byId('snippets-multiselect-cancel'), findsNothing);
  });

  testWidgets('trash: detail offers restore and delete for good, and the '
      'view-bound "Empty trash" sits in the toolbar', (tester) async {
    _wide(tester);
    await tester.pumpWidget(
      makeTestable(const SnippetsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await _addSnippet(tester);
    await tester.tap(_rows().first);
    await tester.pumpAndSettle();
    await tester.tap(_byId('snippets-detail-delete'));
    await tester.pumpAndSettle();

    await tester.tap(_byId('snippets-filter-menu'));
    await tester.pumpAndSettle();
    await tester.tap(_byId('snippets-filter-trash'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_byId('snippets-filter-mark-view'), findsOneWidget);
    expect(_byId('snippets-empty-trash'), findsOneWidget);
    expect(_byId('snippets-select-toggle'), findsNothing);

    await tester.tap(_trashRows().first);
    await tester.pumpAndSettle();
    expect(_byId('snippets-detail-restore'), findsOneWidget);
    expect(_byId('snippets-detail-delete-forever'), findsOneWidget);

    await tester.tap(_byId('snippets-detail-restore'));
    await tester.pumpAndSettle();
    expect(_byId('snippets-detail'), findsNothing);
    expect(_rows(), findsNothing);
  });
}
