/// Snippets are written in place and save themselves (#1498): only a valid
/// state is stored, an invalid one stays unsaved with a hint at the pane
/// (UIA-SNP-04/05), and keyboard focus puts the caret at the end of the text
/// instead of inside it. Behaviour only: addressed by id, no UI-text checks.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/features/snippets/widgets/snippet_editor.dart';
import 'package:whispaste/widgets/wp_segmented_selector.dart';

import '../../fixtures/test_helpers.dart';

Finder _k(String key) => find.byKey(ValueKey(key));

Finder _editable(String key) =>
    find.descendant(of: _k(key), matching: find.byType(EditableText));

List<SnippetItem> _stored(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(SnippetsPage)),
    ).read(snippetsProvider).value ??
    const [];

void main() {
  Future<void> openNew(WidgetTester tester, {bool interactive = false}) async {
    await tester.pumpWidget(
      makeTestable(const SnippetsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
    if (interactive) {
      tester
          .widget<WpSegmentedChoice<String>>(_k('snippets-kind-choice'))
          .onChanged('interactive');
      await tester.pumpAndSettle();
    }
  }

  Future<void> pause(WidgetTester tester) async {
    await tester.pump(SnippetEditor.autosaveDelay);
    await tester.pumpAndSettle();
  }

  testWidgets('a valid snippet saves itself, an invalid one does not', (
    tester,
  ) async {
    await openNew(tester);

    await tester.enterText(_editable('snippets-title-field'), 'Signature');
    await pause(tester);
    expect(_stored(tester), isEmpty);
    expect(_k('snippets-editor-invalid'), findsOneWidget);
    expect(_k('snippets-body-save-status-invalid'), findsOneWidget);

    await tester.enterText(_editable('snippets-body-field'), 'Best, Silvio');
    await pause(tester);
    expect(_stored(tester).map((s) => s.body), ['Best, Silvio']);
    expect(_k('snippets-editor-invalid'), findsNothing);
    expect(_k('snippets-body-save-status-saved'), findsOneWidget);

    // Clearing the title again is no valid state: the stored one stays.
    await tester.enterText(_editable('snippets-title-field'), '  ');
    await pause(tester);
    expect(_stored(tester).map((s) => s.title), ['Signature']);
    expect(_k('snippets-editor-invalid'), findsOneWidget);
    expect(_k('snippets-editor-revert'), findsOneWidget);
  });

  testWidgets('Cmd/Ctrl+S saves at once and the status says saved', (
    tester,
  ) async {
    await openNew(tester);
    await tester.enterText(_editable('snippets-title-field'), 'Signature');
    await tester.enterText(_editable('snippets-body-field'), 'Best, Silvio');
    await tester.pump();
    expect(_stored(tester), isEmpty);

    await tester.sendKeyDownEvent(primaryShortcutModifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(primaryShortcutModifier);
    // No pause: the shortcut writes without waiting for the quiet time.
    await tester.pumpAndSettle();

    expect(_stored(tester).map((s) => s.body), ['Best, Silvio']);
    expect(_k('snippets-body-save-status-saved'), findsOneWidget);
  });

  testWidgets('two interactive fields with the same name are not saved', (
    tester,
  ) async {
    await openNew(tester, interactive: true);

    await tester.enterText(_editable('snippets-title-field'), 'Bug Report');
    await tester.enterText(_editable('snippets-field-name-0'), 'Titel');
    await tester.pumpAndSettle();
    await tester.ensureVisible(_k('snippets-field-add'));
    await tester.pumpAndSettle();
    await tester.tap(_k('snippets-field-add'));
    await tester.pumpAndSettle();
    await tester.enterText(_editable('snippets-field-name-1'), 'Titel');
    await pause(tester);

    expect(_stored(tester), isEmpty);
    expect(_k('snippets-editor-invalid'), findsOneWidget);
  });

  testWidgets('keyboard focus puts the caret at the end of the text', (
    tester,
  ) async {
    await openNew(tester);
    await tester.enterText(_editable('snippets-title-field'), 'Greeting');
    await tester.enterText(_editable('snippets-body-field'), 'Many greetings');
    await pause(tester);

    // Leave the body, then come back by keyboard focus (no pointer).
    final body = tester.widget<EditableText>(_editable('snippets-body-field'));
    body.controller.selection = const TextSelection.collapsed(offset: 4);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    body.focusNode.requestFocus();
    await tester.pumpAndSettle();

    expect(
      body.controller.selection,
      TextSelection.collapsed(offset: body.controller.text.length),
    );
  });

  testWidgets('"+" after creating a snippet opens an empty draft (#1680)', (
    tester,
  ) async {
    await openNew(tester);
    await tester.enterText(_editable('snippets-title-field'), 'Signature');
    await tester.enterText(_editable('snippets-body-field'), 'Best, Silvio');
    await pause(tester);
    expect(_stored(tester).map((s) => s.title), ['Signature']);

    // The editor of the just-created snippet is still open; "+" again.
    await tester.tap(find.byIcon(LucideIcons.plus).first);
    await tester.pumpAndSettle();

    String text(String key) =>
        tester.widget<EditableText>(_editable(key)).controller.text;
    expect(text('snippets-title-field'), isEmpty);
    expect(text('snippets-body-field'), isEmpty);

    // Typing there creates a second snippet and leaves the first unchanged.
    await tester.enterText(_editable('snippets-title-field'), 'Greeting');
    await tester.enterText(_editable('snippets-body-field'), 'Hello');
    await pause(tester);
    expect(
      {for (final s in _stored(tester)) s.title: s.body},
      {'Signature': 'Best, Silvio', 'Greeting': 'Hello'},
    );
  });
}
