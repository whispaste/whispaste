/// #1643: a large history (10 000 recordings) is never loaded as a whole.
/// Tray, side panel and Übersicht read bounded windows, the search counts in
/// SQL and loads its matches one page at a time, and paging reaches every
/// match exactly once. #1663: the sort order and "Alle auswählen" reach every
/// match too.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/providers.dart';

const _total = 10000;
const _apps = ['Mail', 'Editor', 'Browser'];

String _id(int i) => 'e${i.toString().padLeft(5, '0')}';

/// Every 10th recording mentions "Rechnung", every 100th (from 1) is pinned,
/// every 250th (from 3) archived, every 500th (from 7) in the trash. The
/// three groups never overlap, so 1 000 active entries say "Rechnung".
HistoryEntriesCompanion _row(int i) => HistoryEntriesCompanion.insert(
  id: _id(i),
  timestamp: DateTime(2026, 1, 1).add(Duration(minutes: i)),
  title: Value('Aufnahme $i'),
  content: Value(i % 10 == 0 ? 'Rechnung Nummer $i' : 'Eintrag Nummer $i'),
  durationSec: Value((i % 400).toDouble()),
  pinned: Value(i % 100 == 1),
  archived: Value(i % 250 == 3),
  deletedAt: Value(i % 500 == 7 ? DateTime(2026, 6, 1) : null),
  targetApp: Value(_apps[i % 3]),
);

void main() {
  late HistoryDatabase db;

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.batch(
      (b) => b.insertAll(db.historyEntries, [
        for (var i = 0; i < _total; i++) _row(i),
      ]),
    );
  });

  tearDown(() => db.close());

  group('bounded reads for tray, side panel and Übersicht', () {
    test('the head of the list holds only its limit, pins first', () async {
      final head = await db.watchEntries(limit: 5).first;
      expect(head.map((e) => e.id), [
        _id(9901),
        _id(9801),
        _id(9701),
        _id(9601),
        _id(9501),
      ]);
    });

    test(
      'the newest recordings ignore pins and hold only their limit',
      () async {
        final latest = await db.watchLatestEntries(limit: 5).first;
        expect(latest.map((e) => e.id), [
          for (var i = _total - 1; i >= _total - 5; i--) _id(i),
        ]);
      },
    );

    test('target apps come grouped, one row per app', () async {
      final apps = await db.watchTargetAppUsage().first;
      expect(apps, hasLength(_apps.length));
      final mail = apps.singleWhere((a) => a.targetApp == 'Mail');
      expect(
        mail.timestamp,
        DateTime(2026, 1, 1).add(const Duration(minutes: 9999)),
      );
    });
  });

  group('database search', () {
    const spec = HistorySearchSpec(
      freeText: 'Rechnung',
      archived: false,
      deleted: false,
    );

    test('counts in SQL and pages through every match once', () async {
      expect(await db.countHistory(spec), 1000);

      final seen = <String>[];
      for (var offset = 0; ; offset += 50) {
        final page = await db.searchHistory(spec, limit: 50, offset: offset);
        expect(page.length, lessThanOrEqualTo(50));
        seen.addAll(page.map((e) => e.id));
        if (page.length < 50) break;
      }
      expect(seen, hasLength(1000));
      expect(seen.toSet(), hasLength(1000));
      // Newest first, as the list shows them.
      expect(seen.first, _id(9990));
      expect(seen.last, _id(0));
    });

    test('a pinned filter and a duration bound narrow in SQL', () async {
      const pinned = HistorySearchSpec(pinnedOnly: true);
      expect(await db.countHistory(pinned), 100);
      final short = await db
          .watchEntries(
            limit: 1000,
            duration: const HistoryDurationBounds(below: 60),
          )
          .first;
      expect(short, isNotEmpty);
      expect(short.every((e) => e.durationSec < 60), isTrue);
    });
  });

  group('Aufnahmen page providers', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWithValue(db)],
      );
      container
        ..listen(filteredHistoryProvider, (_, _) {})
        ..listen(historyHasMoreProvider, (_, _) {})
        ..listen(historySearchPageProvider, (_, _) {})
        ..listen(pagedHistoryProvider, (_, _) {});
    });

    tearDown(() => container.dispose());

    List<HistoryEntry> shown() =>
        container.read(filteredHistoryProvider).requireValue;

    test('the unfiltered list loads one page and grows on demand', () async {
      expect(await container.read(pagedHistoryProvider.future), hasLength(51));
      expect(shown(), hasLength(historyPageSize));
      expect(container.read(historyHasMoreProvider), isTrue);

      container.read(historyPageLimitProvider.notifier).loadMore();
      await container.read(pagedHistoryProvider.future);
      expect(shown(), hasLength(2 * historyPageSize));
    });

    test('the pinned filter pages in SQL instead of loading all', () async {
      container.read(historyFilterProvider.notifier).set(HistoryFilter.pinned);
      await container.read(pagedHistoryProvider.future);
      expect(shown(), hasLength(historyPageSize));
      expect(shown().every((e) => e.pinned), isTrue);
      expect(container.read(historyHasMoreProvider), isTrue);
    });

    test('a search loads one page, counts all and loads more', () async {
      container.read(historySearchProvider.notifier).set('Rechnung');
      await container.read(historySearchPageProvider.future);
      expect(shown(), hasLength(historyPageSize));
      expect(shown().first.id, _id(9990));
      expect(container.read(historyHasMoreProvider), isTrue);

      final counts = await container.read(searchCountsProvider.future);
      expect(counts?[HistoryFilter.all], 1000);
      expect(counts?[HistoryFilter.pinned], 0);

      container.read(historyPageLimitProvider.notifier).loadMore();
      await container.read(historySearchPageProvider.future);
      expect(shown(), hasLength(2 * historyPageSize));
      expect(shown().map((e) => e.id).toSet(), hasLength(2 * historyPageSize));
    });

    test('a word part from the middle of a word is still found', () async {
      container.read(historySearchProvider.notifier).set('ntrag');
      await container.read(historySearchPageProvider.future);
      expect(shown(), hasLength(historyPageSize));
      expect(shown().every((e) => e.content.contains('Eintrag')), isTrue);
      expect(container.read(historyHasMoreProvider), isTrue);
    });
  });

  // #1663: the order is part of the query, and "Alle auswählen" reaches every
  // match, so neither stops at the loaded page.
  group('sort order and select all over the whole history', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWithValue(db)],
      );
      container
        ..listen(filteredHistoryProvider, (_, _) {})
        ..listen(groupedHistoryProvider, (_, _) {})
        ..listen(historyHasMoreProvider, (_, _) {})
        ..listen(historySearchPageProvider, (_, _) {})
        ..listen(historyListSpecProvider, (_, _) {})
        ..listen(pagedHistoryProvider, (_, _) {});
    });

    tearDown(() => container.dispose());

    List<HistoryEntry> shown() =>
        container.read(filteredHistoryProvider).requireValue;

    void sortBy(HistorySortOrder order) =>
        container.read(historySortOrderProvider.notifier).set(order);

    Future<void> nextPage() async {
      container.read(historyPageLimitProvider.notifier).loadMore();
      await container.read(pagedHistoryProvider.future);
    }

    test('"Älteste" shows the oldest first and pages on in order', () async {
      sortBy(HistorySortOrder.oldest);
      await container.read(pagedHistoryProvider.future);
      expect(shown().first.id, _id(0));
      expect(
        container.read(groupedHistoryProvider).requireValue.first.labelKey,
        'older',
      );

      await nextPage();
      final rows = shown();
      expect(rows, hasLength(2 * historyPageSize));
      for (var i = 1; i < rows.length; i++) {
        expect(rows[i].timestamp.isAfter(rows[i - 1].timestamp), isTrue);
      }
    });

    test('"Längste" shows the longest first and pages on in order', () async {
      sortBy(HistorySortOrder.longest);
      await container.read(pagedHistoryProvider.future);
      // 399 s is the longest length; of those the newest comes first.
      expect(shown().first.id, _id(9999));

      await nextPage();
      final rows = shown();
      expect(rows, hasLength(2 * historyPageSize));
      expect(rows.map((e) => e.id).toSet(), hasLength(rows.length));
      for (var i = 1; i < rows.length; i++) {
        expect(rows[i].durationSec, lessThanOrEqualTo(rows[i - 1].durationSec));
      }
    });

    test('a search sorts in SQL as well', () async {
      container.read(historySearchProvider.notifier).set('Rechnung');
      sortBy(HistorySortOrder.oldest);
      await container.read(historySearchPageProvider.future);
      expect(shown().first.id, _id(0));

      sortBy(HistorySortOrder.longest);
      await container.read(historySearchPageProvider.future);
      expect(shown().first.durationSec, 390);
      expect(shown().first.id, _id(9990));
    });

    test('"Alle auswählen" reads every match, not only the page', () async {
      sortBy(HistorySortOrder.longest);
      await container.read(pagedHistoryProvider.future);
      final spec = container.read(historyListSpecProvider)!;
      final ids = await db.historyIds(
        spec,
        sort: HistorySortOrder.longest,
        limit: historySelectAllLimit,
      );
      // 10 000 minus 40 archived and 20 trashed recordings.
      expect(ids, hasLength(9940));
      expect(ids.toSet(), hasLength(9940));
      expect(await container.read(historyListCountProvider.future), 9940);
      // The first ids are the loaded page, in the same order.
      expect(ids.take(historyPageSize), shown().map((e) => e.id));

      // Bulk copy and export read the rows that are not loaded and put them
      // in the same order as the list.
      final rest = ids.skip(historyPageSize).take(500).toList();
      final rows = await db.entriesByIds(rest)
        ..sort((a, b) => compareHistoryEntries(HistorySortOrder.longest, a, b));
      expect(rows.map((e) => e.id), rest);

      // A selection keeps the matches of the list and drops the rest.
      expect(await db.historyIdsAmong(spec, [_id(0), _id(3), _id(7)]), {
        _id(0),
      });
    });

    test('"Alle auswählen" in a search reads every match', () async {
      container.read(historySearchProvider.notifier).set('Rechnung');
      await container.read(historySearchPageProvider.future);
      final spec = container.read(historyListSpecProvider)!;
      final ids = await db.historyIds(spec, limit: historySelectAllLimit);
      expect(ids, hasLength(1000));
      expect(ids.take(historyPageSize), shown().map((e) => e.id));
    });
  });
}
