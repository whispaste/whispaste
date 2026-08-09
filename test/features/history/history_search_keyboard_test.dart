/// Keyboard operability of the history search autocomplete.
///
/// The dropdown painted a highlight over `_selectedIdx` but nothing ever moved
/// it — no key handler in the filter bar and none in WpSearchField — so the tag
/// and language suggestions could only be taken with the mouse. That breaks the
/// product's own litmus test ("ohne die Maus zu berühren") on the surface this
/// audience opens most often.
///
/// The language list is used here on purpose: it is served from a local const
/// list, so the test exercises the key path without standing up a database.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/data/sample_data.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

List<Object> _sampleOverrides() {
  final all = generateSampleEntries();
  final active = all.where((e) => e.deletedAt == null && !e.archived).toList();
  final archived = all.where((e) => e.archived && e.deletedAt == null).toList();
  final trash = all.where((e) => e.deletedAt != null).toList();
  return [
    historyEntriesProvider.overrideWith((ref) => Stream.value(active)),
    archivedEntriesProvider.overrideWith((ref) => Stream.value(archived)),
    trashEntriesProvider.overrideWith((ref) => Stream.value(trash)),
  ];
}

Future<TextField> _openLangSuggestions(WidgetTester tester) async {
  await tester.pumpWidget(
    makeTestable(
      const HistoryPage(),
      overrides: _sampleOverrides(),
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();

  final field = find.byType(TextField).first;
  await tester.enterText(field, 'lang:');
  await tester.pumpAndSettle();

  // First two entries of the language list, in order.
  expect(find.text('lang:de'), findsOneWidget);
  expect(find.text('lang:en'), findsOneWidget);
  return tester.widget<TextField>(field);
}

void main() {
  group('History search — autocomplete keyboard navigation', () {
    testWidgets('Enter accepts the highlighted suggestion', (tester) async {
      final field = await _openLangSuggestions(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Index 0 is highlighted from the moment the list opens, so Enter has
      // something to accept without arrowing first.
      expect(field.controller!.text, 'lang:de ');
    });

    testWidgets('arrow down moves the highlight before Enter accepts', (
      tester,
    ) async {
      final field = await _openLangSuggestions(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(field.controller!.text, 'lang:en ');
    });

    testWidgets('arrow up wraps to the end of the list', (tester) async {
      final field = await _openLangSuggestions(tester);

      // From index 0 upwards wraps to the last option rather than dead-ending,
      // so the far end of a long list is one keystroke away.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(field.controller!.text, 'lang:ro ');
    });

    testWidgets('Tab accepts too', (tester) async {
      final field = await _openLangSuggestions(tester);

      // Completing a token with Tab is what the key means in every shell this
      // audience already works in.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(field.controller!.text, 'lang:de ');
    });

    testWidgets('Escape closes the list without discarding the query', (
      tester,
    ) async {
      final field = await _openLangSuggestions(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('lang:de'), findsNothing);
      expect(field.controller!.text, 'lang:');
    });
  });
}
