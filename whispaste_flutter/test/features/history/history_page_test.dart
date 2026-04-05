import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('HistoryPage', () {
    testWidgets('renders search bar and filter chips', (tester) async {
      await tester.pumpWidget(makeTestable(const HistoryPage()));
      await tester.pumpAndSettle();

      expect(find.text('Search transcriptions…'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      // "Today" appears as filter chip AND date group header
      expect(find.text('Today'), findsWidgets);
      expect(find.text('This Week'), findsWidgets);
      expect(find.text('Favorites'), findsOneWidget);
    });

    testWidgets('shows sample entries on load', (tester) async {
      await tester.pumpWidget(makeTestable(const HistoryPage()));
      await tester.pumpAndSettle();

      // Should show date group headers
      expect(find.text('Today'), findsWidgets); // filter chip + date header
      // Should show at least one entry title
      expect(
          find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
    });

    testWidgets('filters entries by Today', (tester) async {
      await tester.pumpWidget(makeTestable(const HistoryPage()));
      await tester.pumpAndSettle();

      // Find the "Today" filter chip (there are two — chip + date header)
      // The filter chip is inside a GestureDetector
      final todayChips = find.text('Today');
      // Tap the first one (filter chip)
      await tester.tap(todayChips.first);
      await tester.pumpAndSettle();

      // Should NOT show "Older" entries
      expect(find.text('Project brief — Website redesign'), findsNothing);
      // Should still show today's entries
      expect(find.text('Quick reminder'), findsOneWidget);
    });

    testWidgets('filters entries by Favorites', (tester) async {
      await tester.pumpWidget(makeTestable(const HistoryPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();

      // Should show pinned entries (e.g. "Meeting notes")
      expect(find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
      // Non-pinned entry should be gone
      expect(find.text('Quick reminder'), findsNothing);
    });

    testWidgets('search filters entries by text', (tester) async {
      await tester.pumpWidget(makeTestable(const HistoryPage()));
      await tester.pumpAndSettle();

      // Type a search query
      await tester.enterText(find.byType(TextField), 'pasta');
      await tester.pumpAndSettle();

      // Should show matching entry (case-insensitive match in content)
      expect(find.text('Rezeptidee — Pasta al limone'), findsOneWidget);
      // Should show result count
      expect(find.textContaining('result'), findsOneWidget);
    });

    testWidgets('search with no matches shows empty state', (tester) async {
      await tester.pumpWidget(makeTestable(const HistoryPage()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzznonexistent');
      await tester.pumpAndSettle();

      expect(find.text('No results'), findsOneWidget);
    });

    testWidgets('entry rows show metadata', (tester) async {
      await tester.pumpWidget(makeTestable(const HistoryPage()));
      await tester.pumpAndSettle();

      // Clock icon for duration in entry rows
      expect(find.byIcon(LucideIcons.clock), findsWidgets);
      // Language codes shown as text (e.g. "EN", "DE")
      expect(find.text('EN'), findsWidgets);
    });

    testWidgets('hover shows action buttons', (tester) async {
      await tester.pumpWidget(makeTestable(const HistoryPage()));
      await tester.pumpAndSettle();

      // Before hover — no copy icons visible (they're hover-only)
      expect(find.byIcon(LucideIcons.copy), findsNothing);

      // Hover over first entry
      final firstEntry = find.text('Meeting notes — Product roadmap Q3');
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(firstEntry));
      await tester.pumpAndSettle();

      // Now should show action icons
      expect(find.byIcon(LucideIcons.copy), findsWidgets);
    });

    testWidgets('works in light theme', (tester) async {
      await tester.pumpWidget(
          makeTestable(const HistoryPage(), brightness: Brightness.light));
      await tester.pumpAndSettle();

      expect(find.text('Search transcriptions…'), findsOneWidget);
      expect(
          find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
    });
  });
}
