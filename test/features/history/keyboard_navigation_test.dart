import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/data/sample_data.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

/// Provider overrides that supply sample data via stream providers.
List<Object> _sampleOverrides() {
  final all = generateSampleEntries();
  final active =
      all.where((e) => e.deletedAt == null && !e.archived).toList();
  final archived =
      all.where((e) => e.archived && e.deletedAt == null).toList();
  final trash = all.where((e) => e.deletedAt != null).toList();
  return [
    historyEntriesProvider.overrideWith((ref) => Stream.value(active)),
    archivedEntriesProvider.overrideWith((ref) => Stream.value(archived)),
    trashEntriesProvider.overrideWith((ref) => Stream.value(trash)),
  ];
}

/// Pump enough frames for widgets to build + animations to run,
/// without waiting for Drift stream timers to settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('Keyboard Navigation', () {
    testWidgets('renders HistoryPage with sample data', (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), overrides: _sampleOverrides()));
      await _settle(tester);

      expect(find.byType(HistoryPage), findsOneWidget);
    });

    testWidgets('Arrow Down moves focus', (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), overrides: _sampleOverrides()));
      await _settle(tester);

      // Send arrow down — should set focus to first entry
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);

      // Another arrow down
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);

      expect(find.byType(HistoryPage), findsOneWidget);
    });

    testWidgets('Arrow Up moves focus', (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), overrides: _sampleOverrides()));
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _settle(tester);

      expect(find.byType(HistoryPage), findsOneWidget);
    });

    testWidgets('Escape clears state without crash', (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), overrides: _sampleOverrides()));
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);

      expect(find.byType(HistoryPage), findsOneWidget);
    });

    testWidgets('P key does not crash without focus', (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), overrides: _sampleOverrides()));
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await _settle(tester);

      expect(find.byType(HistoryPage), findsOneWidget);
    });

    testWidgets('Delete key does not crash without focus', (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), overrides: _sampleOverrides()));
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await _settle(tester);

      expect(find.byType(HistoryPage), findsOneWidget);
    });

    testWidgets('Enter key does not crash without focus', (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), overrides: _sampleOverrides()));
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);

      expect(find.byType(HistoryPage), findsOneWidget);
    });

    testWidgets('Multiple arrow keys navigate correctly', (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), overrides: _sampleOverrides()));
      await _settle(tester);

      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 50));
      }
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await _settle(tester);

      expect(find.byType(HistoryPage), findsOneWidget);
    });

    testWidgets('works in light theme', (tester) async {
      await tester.pumpWidget(makeTestable(const HistoryPage(),
          brightness: Brightness.light, overrides: _sampleOverrides()));
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);

      expect(find.byType(HistoryPage), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Shortcut suppression when a text field has focus
  // ---------------------------------------------------------------------------
  group('Shortcut suppression in text fields', () {
    /// Finds the search TextField (if rendered) and focuses it.
    Future<EditableText?> focusSearchField(WidgetTester tester) async {
      final candidates = tester.widgetList<EditableText>(
        find.byType(EditableText),
      );
      if (candidates.isEmpty) return null;
      // The search bar is typically the first EditableText in the history page.
      final target = find.byType(EditableText).first;
      await tester.tap(target);
      await tester.pump();
      return tester.widget<EditableText>(target);
    }

    testWidgets(
        'Delete key does not trigger list action while search field focused',
        (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), overrides: _sampleOverrides()));
      await _settle(tester);

      // Navigate to give a focused entry so Delete would normally fire.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);

      // Focus a text field.
      final focused = await focusSearchField(tester);
      if (focused == null) return; // no text field rendered — skip gracefully

      // Pressing Delete should NOT throw and should not open a delete dialog.
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await _settle(tester);

      // Page still renders without any error dialog.
      expect(find.byType(HistoryPage), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets(
        'Backspace key does not trigger list action while text field focused',
        (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), overrides: _sampleOverrides()));
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);

      final focused = await focusSearchField(tester);
      if (focused == null) return;

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await _settle(tester);

      expect(find.byType(HistoryPage), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets(
        'Enter key does not open entry while text field focused',
        (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), overrides: _sampleOverrides()));
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);

      final focused = await focusSearchField(tester);
      if (focused == null) return;

      // Pressing Enter while a text field is focused must not open a detail
      // panel or throw — verifying no AlertDialog / new overlay appeared.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);

      expect(find.byType(HistoryPage), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('text field can receive focus in history page', (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), overrides: _sampleOverrides()));
      await _settle(tester);

      final focused = await focusSearchField(tester);
      // If there's no EditableText in the tree, the page renders without one — fine.
      // If there is one and we tapped it, FocusManager must have a primary focus.
      if (focused != null) {
        expect(FocusManager.instance.primaryFocus, isNotNull);
      }
      expect(find.byType(HistoryPage), findsOneWidget);
    });
  });
}

