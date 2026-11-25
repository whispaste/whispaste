/// Escape in a page search empties the query on every list (#1845).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

void main() {
  Future<(TextEditingController, List<String>)> pump(
    WidgetTester tester, {
    required bool clearOnEscape,
  }) async {
    final controller = TextEditingController(text: 'zzz');
    addTearDown(controller.dispose);
    final reached = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent) reached.add(event.logicalKey.keyLabel);
              return KeyEventResult.ignored;
            },
            child: WpSearchField(
              controller: controller,
              hintText: 'Suchen',
              variant: WpSearchFieldVariant.outlined,
              clearOnEscape: clearOnEscape,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (controller, reached);
  }

  testWidgets('Escape empties a query, then passes on to the page', (
    tester,
  ) async {
    final (controller, reached) = await pump(tester, clearOnEscape: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(reached, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(reached, ['Escape']);
  });

  testWidgets('without the opt-in Escape keeps the query (pickers)', (
    tester,
  ) async {
    final (controller, _) = await pump(tester, clearOnEscape: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.text, 'zzz');
  });

  test('Aufnahmen and Textbausteine opt in like Notizen clears', () {
    for (final path in [
      'lib/features/history/widgets/history_search_filter_bar.dart',
      'lib/features/snippets/snippets_page.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('clearOnEscape: true'),
        reason: path,
      );
    }
  });
}
