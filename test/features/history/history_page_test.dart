import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/data/sample_data.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

/// Provider overrides that supply sample data via stream providers,
/// matching the previous behaviour where the page loaded sample entries.
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

void main() {
  // Resolve English copy once so chip / placeholder / empty-state labels
  // are looked up via the ARB key — keeps the suite stable across wording
  // tweaks in the ARB. Pure test data (sample-entry titles, language codes)
  // stays as literals because it never flows through localisation.
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('HistoryPage', () {
    testWidgets('renders search bar and filter chips', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _sampleOverrides(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.historySearchTranscriptions), findsOneWidget);
      expect(find.text(l10n.historyAll), findsOneWidget);
      // "Today" appears as filter chip AND date group header
      expect(find.text(l10n.historyToday), findsWidgets);
      expect(find.text(l10n.historyThisWeek), findsWidgets);
      expect(find.text(l10n.historyPinned), findsOneWidget);
    });

    testWidgets('shows sample entries on load', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _sampleOverrides(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Should show date group headers
      expect(
        find.text(l10n.historyToday),
        findsWidgets,
      ); // filter chip + date header
      // Should show at least one entry title
      expect(find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
    });

    testWidgets('filters entries by Today', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _sampleOverrides(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Find the "Today" filter chip (there are two — chip + date header)
      // The filter chip is inside a GestureDetector
      final todayChips = find.text(l10n.historyToday);
      // Tap the first one (filter chip)
      await tester.tap(todayChips.first);
      await tester.pumpAndSettle();

      // Should NOT show "Older" entries
      expect(find.text('Project brief — Website redesign'), findsNothing);
      // Should still show today's entries
      expect(find.text('Quick reminder'), findsOneWidget);
    });

    testWidgets('filters entries by Favorites', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _sampleOverrides(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.historyPinned));
      await tester.pumpAndSettle();

      // Should show favorited entries (e.g. "Meeting notes")
      expect(find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
      // Non-favorited entry should be gone
      expect(find.text('Quick reminder'), findsNothing);
    });

    testWidgets('search filters entries by text', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _sampleOverrides(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Type a search query
      await tester.enterText(find.byType(TextField), 'pasta');
      await tester.pumpAndSettle();

      // Should show matching entry (case-insensitive match in content)
      expect(find.text('Rezeptidee — Pasta al limone'), findsOneWidget);
      // Should show result count — "pasta" hits two sample entries (the
      // recipe title and a separate note that mentions a pasta sauce).
      expect(find.text(l10n.historyResultCount(2)), findsOneWidget);
    });

    testWidgets('search with no matches shows empty state', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _sampleOverrides(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzznonexistent');
      await tester.pumpAndSettle();

      expect(find.text(l10n.historyNoResults), findsOneWidget);
    });

    testWidgets('entry rows show metadata', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _sampleOverrides(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Clock icon for duration in entry rows
      expect(find.byIcon(LucideIcons.clock), findsWidgets);
      // Language codes shown as text (e.g. "EN", "DE")
      expect(find.text('EN'), findsWidgets);
    });

    testWidgets('hover shows action buttons', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _sampleOverrides(),
          locale: const Locale('en'),
        ),
      );
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
        makeTestable(
          const HistoryPage(),
          brightness: Brightness.light,
          overrides: _sampleOverrides(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.historySearchTranscriptions), findsOneWidget);
      expect(find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
    });

    testWidgets('view mode toggle switches between views', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _sampleOverrides(),
          locale: const Locale('en'),
        ),
      );
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
      expect(find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
      expect(find.byIcon(LucideIcons.clock), findsWidgets);

      // Switch to compact view
      await tester.tap(find.byIcon(LucideIcons.rows3));
      await tester.pumpAndSettle();

      // Compact view — entries visible, no clock icons (compact has none)
      expect(find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
      expect(find.byIcon(LucideIcons.clock), findsNothing);

      // Switch back to list view
      await tester.tap(find.byIcon(LucideIcons.list));
      await tester.pumpAndSettle();

      // Back to list — clock icons reappear in metadata
      expect(find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
      expect(find.byIcon(LucideIcons.clock), findsWidgets);
    });

    group('filter-specific empty states', () {
      testWidgets('pinned filter shows specific empty state when no favorites', (
        tester,
      ) async {
        final all = generateSampleEntries();
        // Use only non-pinned active entries so the Favorites filter is empty.
        final noPinned = all
            .where((e) => e.deletedAt == null && !e.archived && !e.pinned)
            .toList();
        await tester.pumpWidget(
          makeTestable(
            const HistoryPage(),
            overrides: [
              historyEntriesProvider.overrideWith(
                (ref) => Stream.value(noPinned),
              ),
              archivedEntriesProvider.overrideWith((ref) => Stream.value([])),
              trashEntriesProvider.overrideWith((ref) => Stream.value([])),
            ],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(l10n.historyPinned));
        await tester.pumpAndSettle();

        expect(find.text(l10n.historyNoPinned), findsOneWidget);
        expect(find.text(l10n.historyNoPinnedHint), findsOneWidget);
        expect(find.text(l10n.historyEmpty), findsNothing);
      });

      testWidgets(
        'today filter shows specific empty state when no entries today',
        (tester) async {
          final all = generateSampleEntries();
          // Use only entries older than 7 days so the Today filter is empty.
          final oldEntries = all
              .where(
                (e) =>
                    e.deletedAt == null &&
                    !e.archived &&
                    e.timestamp.isBefore(
                      DateTime.now().subtract(const Duration(days: 7)),
                    ),
              )
              .toList();
          await tester.pumpWidget(
            makeTestable(
              const HistoryPage(),
              overrides: [
                historyEntriesProvider.overrideWith(
                  (ref) => Stream.value(oldEntries),
                ),
                archivedEntriesProvider.overrideWith((ref) => Stream.value([])),
                trashEntriesProvider.overrideWith((ref) => Stream.value([])),
              ],
              locale: const Locale('en'),
            ),
          );
          await tester.pumpAndSettle();

          // "Today" appears only as filter chip (no today entries in list).
          await tester.tap(find.text(l10n.historyToday).first);
          await tester.pumpAndSettle();

          expect(find.text(l10n.historyNoToday), findsOneWidget);
          expect(find.text(l10n.historyNoTodayHint), findsOneWidget);
          expect(find.text(l10n.historyEmpty), findsNothing);
        },
      );

      testWidgets(
        'week filter shows specific empty state when no entries this week',
        (tester) async {
          final all = generateSampleEntries();
          // Use only entries older than 7 days so the This Week filter is empty.
          final oldEntries = all
              .where(
                (e) =>
                    e.deletedAt == null &&
                    !e.archived &&
                    e.timestamp.isBefore(
                      DateTime.now().subtract(const Duration(days: 7)),
                    ),
              )
              .toList();
          await tester.pumpWidget(
            makeTestable(
              const HistoryPage(),
              overrides: [
                historyEntriesProvider.overrideWith(
                  (ref) => Stream.value(oldEntries),
                ),
                archivedEntriesProvider.overrideWith((ref) => Stream.value([])),
                trashEntriesProvider.overrideWith((ref) => Stream.value([])),
              ],
              locale: const Locale('en'),
            ),
          );
          await tester.pumpAndSettle();

          // "This Week" appears only as filter chip (no this-week entries in list).
          await tester.tap(find.text(l10n.historyThisWeek).first);
          await tester.pumpAndSettle();

          expect(find.text(l10n.historyNoThisWeek), findsOneWidget);
          expect(find.text(l10n.historyNoThisWeekHint), findsOneWidget);
          expect(find.text(l10n.historyEmpty), findsNothing);
        },
      );
    });

    // -------------------------------------------------------------------------
    // AC4: Loading skeleton state
    // -------------------------------------------------------------------------

    testWidgets(
      'shows skeleton (no CircularProgressIndicator) when stream is loading',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const HistoryPage(),
            overrides: [
              // Empty stream → StreamProvider stays in AsyncLoading
              historyEntriesProvider.overrideWith(
                (ref) => const Stream.empty(),
              ),
              archivedEntriesProvider.overrideWith((ref) => Stream.value([])),
              trashEntriesProvider.overrideWith((ref) => Stream.value([])),
            ],
            locale: const Locale('en'),
          ),
        );
        // Single pump — do not settle so the loading state is captured.
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        // Skeleton renders at least one ListView (the skeleton rows).
        // The page may also have a horizontal ListView for the filter bar.
        expect(find.byType(ListView), findsWidgets);
      },
    );

    // -------------------------------------------------------------------------
    // AC5: Error state
    // -------------------------------------------------------------------------

    testWidgets('shows WpEmptyState with error icon when stream errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: [
            historyEntriesProvider.overrideWith(
              // Riverpod 2.x retries Exception errors (stays loading).
              // Use StateError (an Error subclass) to skip retry and reach
              // AsyncError immediately.
              (ref) => Stream.error(StateError('db failure'), StackTrace.empty),
            ),
            archivedEntriesProvider.overrideWith((ref) => Stream.value([])),
            trashEntriesProvider.overrideWith((ref) => Stream.value([])),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
      expect(find.text(l10n.errorGeneric), findsOneWidget);
      expect(find.text(l10n.actionRetry), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
