/// #879: the duration chips of the History list. Tested are the bucket
/// bounds (60 s and 300 s), the combination with search and filter, and one
/// click flow addressed only by testID.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

HistoryEntry _entry(String id, double seconds, {bool pinned = false}) =>
    HistoryEntry(
      id: id,
      content: '$id note',
      title: '$id note',
      timestamp: DateTime(2026, 1, 1, 9),
      durationSec: seconds,
      processingDurationSec: 0.5,
      language: 'en',
      languageHint: '',
      tags: '[]',
      pinned: pinned,
      source: 'microphone',
      model: 'whisper-small',
      isLocal: true,
      costUsd: 0.0,
      archived: false,
      deletedAt: null,
      titleEdited: false,
      colorSlot: 0,
    );

final _entries = [
  _entry('s59', 59.9),
  _entry('m60', 60, pinned: true),
  _entry('m300', 300),
  _entry('l301', 300.1, pinned: true),
];

List _overrides() => [
  pagedHistoryProvider.overrideWith((ref) => Stream.value(_entries)),
  archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
  trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
];

void main() {
  group('bucket bounds', () {
    test('60 s and 300 s belong to 1–5 min, every length to one bucket', () {
      Set<HistoryDurationBucket> of(double s) => {
        for (final b in HistoryDurationBucket.values)
          if (b != HistoryDurationBucket.all && b.matches(s)) b,
      };
      expect(of(0), {HistoryDurationBucket.short});
      expect(of(59.9), {HistoryDurationBucket.short});
      expect(of(60), {HistoryDurationBucket.medium});
      expect(of(300), {HistoryDurationBucket.medium});
      expect(of(300.1), {HistoryDurationBucket.long});
      expect(HistoryDurationBucket.all.matches(5000), isTrue);
    });
  });

  group('list provider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(overrides: [..._overrides()]);
      // Keep the auto-dispose sources alive between reads; a bare read of
      // their future would dispose them before the stream delivers.
      container
        ..listen(filteredHistoryProvider, (_, _) {})
        ..listen(pagedHistoryProvider, (_, _) {});
    });
    tearDown(() => container.dispose());

    Future<Set<String>> ids() async {
      // Let the overridden streams deliver before reading.
      await container.read(pagedHistoryProvider.future);
      return container
          .read(filteredHistoryProvider)
          .requireValue
          .map((e) => e.id)
          .toSet();
    }

    test('each chip narrows the list to its bucket', () async {
      final bucket = container.read(historyDurationBucketProvider.notifier);
      expect(await ids(), {'s59', 'm60', 'm300', 'l301'});
      bucket.set(HistoryDurationBucket.short);
      expect(await ids(), {'s59'});
      bucket.set(HistoryDurationBucket.medium);
      expect(await ids(), {'m60', 'm300'});
      bucket.set(HistoryDurationBucket.long);
      expect(await ids(), {'l301'});
    });

    test('the chip combines with the pinned filter and the search', () async {
      container
          .read(historyDurationBucketProvider.notifier)
          .set(HistoryDurationBucket.medium);
      container.read(historyFilterProvider.notifier).set(HistoryFilter.pinned);
      expect(await ids(), {'m60'});

      container.read(historyFilterProvider.notifier).set(HistoryFilter.all);
      container.read(historySearchProvider.notifier).set('m300');
      expect(await ids(), {'m300'});
    });
  });

  testWidgets('click flow: a chip filters, the empty state resets it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      makeTestable(
        const HistoryPage(),
        locale: const Locale('en'),
        overrides: _overrides(),
      ),
    );
    await tester.pumpAndSettle();

    // The duration chips live in the filter popover (#1201).
    Future<void> openFilters() async {
      if (find
          .bySemanticsIdentifier('history-filter-panel')
          .evaluate()
          .isEmpty) {
        await tester.tap(find.bySemanticsIdentifier('history-filter-menu'));
        await tester.pumpAndSettle();
      }
    }

    bool selected(String id) => isSemantics(
      isSelected: true,
    ).matches(tester.getSemantics(find.bySemanticsIdentifier(id)), {});

    await openFilters();
    expect(selected('history-duration-all'), isTrue);
    expect(find.text('s59 note'), findsWidgets);

    await tester.tap(find.bySemanticsIdentifier('history-duration-long'));
    await tester.pumpAndSettle();
    expect(selected('history-duration-long'), isTrue);
    expect(selected('history-duration-all'), isFalse);
    expect(find.text('s59 note'), findsNothing);
    expect(find.text('l301 note'), findsWidgets);
    // The active length shows as a removable mark next to the search.
    expect(
      find.bySemanticsIdentifier('history-filter-mark-duration'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Search plus chip leave nothing: the empty state offers the reset.
    await tester.enterText(find.byType(TextField).first, 's59');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('history-duration-reset'));
    await tester.pumpAndSettle();
    await openFilters();
    expect(selected('history-duration-all'), isTrue);
    expect(find.text('s59 note'), findsWidgets);

    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
