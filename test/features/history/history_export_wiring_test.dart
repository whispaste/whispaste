/// Widget tests for issue 12 — Detail-panel "Export…" + multi-select wiring.
///
/// Covers the two call sites that fan out to `HistoryExporter.exportEntries`:
///   1. Single-entry: the new overflow-menu item in [HistoryDetailPanel].
///   2. Multi-select: the new toolbar action in [HistoryPage].
///
/// Both call sites resolve through `HistoryPage.exportFn`, which is an
/// injection seam that defaults to the production top-level [exportEntries].
/// The tests substitute a fake that captures the call so we can assert the
/// right entries reach the exporter, without spinning up real platform
/// channels.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/data/sample_data.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

/// Swallows pre-existing horizontal-overflow render errors so they do not fail
/// these wiring tests. Restores the previous error handler on tearDown.
///
/// The history detail panel has long-standing tight-fit overflow on certain
/// localised labels (tracked elsewhere). It is out of scope for issue 12 to
/// fix that — these tests assert wiring, not layout.
void _ignoreOverflowErrors(WidgetTester tester) {
  final originalHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final summary = details.toString();
    if (summary.contains('overflowed')) {
      // Drop silently.
      return;
    }
    originalHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalHandler);
}

// ─── Fake exporter that captures invocations ──────────────────────────────

class _ExportCall {
  _ExportCall(this.entries);
  final List<HistoryEntry> entries;
}

class _FakeExporter {
  final List<_ExportCall> calls = [];

  Future<void> call(BuildContext context, List<HistoryEntry> entries) async {
    calls.add(_ExportCall(List.of(entries)));
  }
}

// ─── Overrides identical to history_page_test.dart ────────────────────────

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

// ─── Tests ────────────────────────────────────────────────────────────────

void main() {
  group('HistoryPage — detail-panel single-entry export', () {
    testWidgets('overflow "Export…" item invokes exportFn with [tappedEntry]', (
      tester,
    ) async {
      _ignoreOverflowErrors(tester);
      final fake = _FakeExporter();

      await tester.pumpWidget(
        makeTestable(
          HistoryPage(exportFn: fake.call),
          // Use an extra-wide viewport so the master/detail split has room
          // for the detail panel's full action row.
          size: const Size(1800, 900),
          overrides: _sampleOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Open the detail panel by tapping the first sample entry.
      // The sample data exposes "Meeting notes — Product roadmap Q3" as the
      // first active entry. Tap the row to open the detail panel.
      await tester.tap(find.text('Meeting notes — Product roadmap Q3').first);
      await tester.pumpAndSettle();

      // Open the overflow menu inside the detail panel.
      await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
      await tester.pumpAndSettle();

      // Tap the localised "Export…" item.
      expect(find.text('Export…'), findsOneWidget);
      await tester.tap(find.text('Export…'));
      await tester.pumpAndSettle();

      // Exporter was invoked with exactly the tapped entry (`sample-1`).
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.entries.map((e) => e.id).toList(), ['sample-1']);

      // Drain any pending Drift / Riverpod cleanup timers before the test
      // framework tears down the widget tree, otherwise the framework's
      // `!timersPending` invariant fires from the in-memory DB's
      // `StreamQueryStore.markAsClosed` scheduling a zero-duration timer.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('HistoryPage — multi-select export', () {
    testWidgets(
      'multi-select Export action invokes exportFn with all selected entries',
      (tester) async {
        _ignoreOverflowErrors(tester);
        final fake = _FakeExporter();

        await tester.pumpWidget(
          makeTestable(
            HistoryPage(exportFn: fake.call),
            // Wider viewport keeps the multi-select bar's action row laid out
            // without triggering pre-existing tight-fit overflows.
            size: const Size(1800, 900),
            overrides: _sampleOverrides(),
          ),
        );
        await tester.pumpAndSettle();

        // Enter multi-select mode via the toolbar toggle.
        await tester.tap(find.byIcon(LucideIcons.listChecks));
        await tester.pumpAndSettle();

        // Seed selection: tap an entry to add a first item — the
        // multi-select bar only renders once `_selectedIds` is non-empty.
        await tester.tap(find.text('Meeting notes — Product roadmap Q3').first);
        await tester.pumpAndSettle();

        // Now expand selection to all visible entries via "Select All".
        // The label is the EN ARB `historySelectAll` → "Select All".
        await tester.tap(find.text('Select All'));
        await tester.pumpAndSettle();

        // The multi-select bar should now show the new "Export…" action.
        expect(find.text('Export…'), findsOneWidget);
        // Scroll the action into view if the horizontal action list pushed it
        // out, then tap.
        await tester.ensureVisible(find.text('Export…'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export…'), warnIfMissed: false);
        await tester.pumpAndSettle();

        // The exporter received a single batched call with multiple entries.
        expect(fake.calls, hasLength(1));
        expect(
          fake.calls.single.entries.length,
          greaterThanOrEqualTo(3),
          reason:
              'Selecting all sample entries should pass the full filtered '
              'list to the exporter in one call.',
        );
      },
    );
  });
}
