import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/snippets/snippet_item.dart';
import 'package:whispaste/features/snippets/widgets/snippet_insert_dialog.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  final items = [
    for (var i = 0; i < 20; i++)
      SnippetItem(
        id: '$i',
        title: 'Snippet $i',
        body: 'Body\n$i',
        createdAt: DateTime(2026),
      ),
  ];
  const platforms = TargetPlatformVariant({
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  });

  for (final locale in L10n.supportedLocales) {
    testWidgets('chooser keyboard and semantics in $locale', (tester) async {
      final semantics = tester.ensureSemantics();
      SnippetItem? picked;
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await pickSnippetForInsert(context, items);
              },
              child: const Text('open'),
            ),
          ),
          locale: locale,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.bySemanticsIdentifier('snippet-insert-search'),
        matching: find.byType(EditableText),
      );
      // Focus stays in search; the highlighted result is announced, because
      // Flutter drops an invisible live region before it reaches AT-SPI,
      // UIA or NSAccessibility (#664, checked with another app on Ubuntu).
      // announce() sends macOS announcements past SemanticsService (see
      // lib/core/accessibility/announce.dart), so only Windows and Linux
      // reach takeAnnouncements; macOS checks keyboard and focus.
      void expectSpoken(List<String> messages) {
        final spoken = tester.takeAnnouncements().map((a) => a.message);
        if (defaultTargetPlatform != TargetPlatform.macOS) {
          expect(spoken.toList(), messages);
        }
        expect(tester.widget<EditableText>(search).focusNode.hasFocus, isTrue);
      }

      tester.takeAnnouncements();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expectSpoken(['Snippet 19, Body 19']);
      expect(
        find.byKey(const ValueKey('snippet-insert-item-19')).hitTestable(),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expectSpoken(['Snippet 0, Body 0']);
      await tester.enterText(search, 'no match');
      await tester.pumpAndSettle();
      final l10n = L10n.of(tester.element(search));
      expectSpoken([l10n.snippetInsertNoMatch]);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(search, findsOneWidget);
      await tester.enterText(search, 'Snippet 12');
      await tester.pumpAndSettle();
      expectSpoken(['Snippet 12, Body 12']);
      // Typing that keeps the same highlight stays quiet.
      await tester.enterText(search, 'Snippet 12 ');
      await tester.pumpAndSettle();
      expectSpoken([]);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(picked?.id, '12');
      expect(search, findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(picked, isNull);
      expect(search, findsNothing);
      semantics.dispose();
    }, variant: platforms);
  }
}
