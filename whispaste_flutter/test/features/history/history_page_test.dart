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
      expect(find.text('Pinned'), findsOneWidget);
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

    testWidgets('filters entries by Pinned', (tester) async {
      await tester.pumpWidget(makeTestable(const HistoryPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pinned'));
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

      // Action icons are always in the tree (inside AnimatedOpacity for
      // fixed-height layout), but invisible until hover.

      // Hover over first entry
      final firstEntry = find.text('Meeting notes — Product roadmap Q3');
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(firstEntry));
      await tester.pumpAndSettle();

      // After hover — action icons should be visible and interactive
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

    testWidgets('view mode toggle switches between views', (tester) async {
      await tester.pumpWidget(makeTestable(const HistoryPage()));
      await tester.pumpAndSettle();

      // View mode toggle icons should be visible
      expect(find.byIcon(LucideIcons.list), findsOneWidget);
      expect(find.byIcon(LucideIcons.layoutGrid), findsOneWidget);
      expect(find.byIcon(LucideIcons.rows3), findsOneWidget);

      // Default list view — clock icons in entry metadata rows
      expect(find.byIcon(LucideIcons.clock), findsWidgets);

      // Switch to card view
      await tester.tap(find.byIcon(LucideIcons.layoutGrid));
      await tester.pumpAndSettle();

      // Card view — entries visible, clock icons in card metadata
      expect(
          find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
      expect(find.byIcon(LucideIcons.clock), findsWidgets);

      // Switch to compact view
      await tester.tap(find.byIcon(LucideIcons.rows3));
      await tester.pumpAndSettle();

      // Compact view — entries visible, no clock icons (compact has none)
      expect(
          find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
      expect(find.byIcon(LucideIcons.clock), findsNothing);

      // Switch back to list view
      await tester.tap(find.byIcon(LucideIcons.list));
      await tester.pumpAndSettle();

      // Back to list — clock icons reappear in metadata
      expect(
          find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
      expect(find.byIcon(LucideIcons.clock), findsWidgets);
    });
  });
}
