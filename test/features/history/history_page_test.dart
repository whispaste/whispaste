import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/data/sample_data.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';
import 'package:whispaste/widgets/wp_copy_feedback.dart';

late L10n l10n;

/// Provider overrides that supply sample data via stream providers,
/// matching the previous behaviour where the page loaded sample entries.
List<Object> _sampleOverrides() {
  final all = generateSampleEntries();
  final active = all.where((e) => e.deletedAt == null && !e.archived).toList();
  final archived = all.where((e) => e.archived && e.deletedAt == null).toList();
  final trash = all.where((e) => e.deletedAt != null).toList();
  return [
    pagedHistoryProvider.overrideWith((ref) => Stream.value(active)),
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
    testWidgets('filters entries by Favorites', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _sampleOverrides(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // The view chips live in the filter popover.
      await tester.tap(find.bySemanticsIdentifier('history-filter-menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('history-filter-pinned'));
      await tester.pumpAndSettle();

      // Should show favorited entries (e.g. "Meeting notes")
      expect(find.text('Meeting notes — Product roadmap Q3'), findsOneWidget);
      // Non-favorited entry should be gone
      expect(find.text('Quick reminder'), findsNothing);
    });

    testWidgets('a search without matches hides every entry', (tester) async {
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

      expect(find.text('Meeting notes — Product roadmap Q3'), findsNothing);
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
    });

    testWidgets('copying a recording answers at its row, not with a toast', (
      tester,
    ) async {
      final written = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            written.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        makeTestable(const HistoryPage(), overrides: _sampleOverrides()),
      );
      await tester.pumpAndSettle();

      final firstEntry = find.text('Meeting notes — Product roadmap Q3');
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(firstEntry));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.copy).first);
      await tester.pump();
      await tester.pump();

      expect(written, hasLength(1));
      expect(
        find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('copy-note-history-');
        }),
        findsWidgets,
      );
      await tester.pumpAndSettle(WpCopyMarkNotifier.copiedFor);
    });

    // Removed 2026-08-11 (dark-only build): 'works in light theme' pumped the
    // page with Brightness.light and asserted it still rendered. The app now
    // ships a single dark theme only, so there is no light theme left to
    // build.
  });
}
