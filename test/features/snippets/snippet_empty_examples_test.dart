/// The empty snippet list teaches by example (#863): a chip only pre-fills
/// the add editor, nothing is stored until the user saves.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/features/snippets/widgets/snippet_editor.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SnippetsPage)));

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      makeTestable(const SnippetsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
  }

  // A picked example is content the user chose: like typed text it is kept
  // when the editor closes, no extra save step (#1498).
  testWidgets('a chip pre-fills the editor and closing keeps it as a snippet', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.ensureVisible(_byId('snippets-example-signature'));
    await tester.pumpAndSettle();
    await tester.tap(_byId('snippets-example-signature'));
    await tester.pumpAndSettle();

    final title = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(title.controller!.text, l10n.snippetsExampleSignatureTitle);
    expect(containerOf(tester).read(snippetsProvider).value, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final saved = containerOf(tester).read(snippetsProvider).value!.single;
    expect(saved.title, l10n.snippetsExampleSignatureTitle);
    expect(_byId('snippets-example-signature'), findsNothing);
  });

  testWidgets('the interactive example saves as a valid interactive snippet', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.ensureVisible(_byId('snippets-example-interactive'));
    await tester.pumpAndSettle();
    await tester.tap(_byId('snippets-example-interactive'));
    await tester.pumpAndSettle();
    expect(containerOf(tester).read(snippetsProvider).value, isEmpty);

    // The picked example saves itself after the autosave pause (#1498).
    await tester.pump(SnippetEditor.autosaveDelay);
    await tester.pumpAndSettle();

    final saved = containerOf(tester).read(snippetsProvider).value!.single;
    final first = l10n.snippetsExampleInteractiveField1;
    final second = l10n.snippetsExampleInteractiveField2;
    expect(saved.title, l10n.snippetsExampleInteractiveTitle);
    expect(saved.kind, 'interactive');
    expect(saved.fields, [first, second]);
    expect(saved.body, contains('{{$first}}'));
    expect(saved.body, contains('{{$second}}'));
  });

  test('every language keeps the interactive fields distinct', () async {
    for (final locale in L10n.supportedLocales) {
      final l = await L10n.delegate.load(locale);
      expect(
        l.snippetsExampleInteractiveField1.trim(),
        isNot(l.snippetsExampleInteractiveField2.trim()),
        reason: '$locale',
      );
      expect(l.snippetsExampleInteractiveField1.trim(), isNotEmpty);
      expect(l.snippetsExampleInteractiveField2.trim(), isNotEmpty);
    }
  });
}

Finder _byId(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);
