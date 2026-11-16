/// #679: the period and length operators of the History search. The chips write
/// exactly these tokens, so the token logic is what is tested here: parsing,
/// producing, the periods and the database filter.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/widgets/history_range_chips.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('parsing', () {
    test('reads a period and both length bounds next to free text', () {
      final p = parseSearchQuery('invoice date:7d longer:30s shorter:2m #work');
      expect(p.freeText, 'invoice');
      expect(p.dateRange, HistoryDateRange.last7Days);
      expect(p.longerThanSec, 30);
      expect(p.shorterThanSec, 120);
      expect(p.tagNames, ['work']);
      expect(p.isEmpty, isFalse);
    });

    test('an operator alone is a query; an unknown period stays text', () {
      expect(parseSearchQuery('date:month').isEmpty, isFalse);
      final unknown = parseSearchQuery('date:someday');
      expect(unknown.dateRange, isNull);
      expect(unknown.freeText, 'date:someday');
    });
  });

  group('producing', () {
    test('a period replaces the old one and keeps the rest', () {
      expect(
        withDateOperator('hello date:today', HistoryDateRange.yesterday),
        'hello date:yesterday',
      );
      expect(withDateOperator('hello date:today', null), 'hello');
    });

    test('a chip click never removes text the parser keeps as text', () {
      expect(
        withDateOperator('date:someday', HistoryDateRange.today),
        'date:someday date:today',
      );
    });

    test('the two length bounds combine into a window', () {
      var q = withDurationOperator('', HistoryDurationBound.longer, 10);
      q = withDurationOperator(q, HistoryDurationBound.shorter, 120);
      expect(q, 'longer:10s shorter:2m');
      q = withDurationOperator(q, HistoryDurationBound.longer, 60);
      expect(q, 'shorter:2m longer:1m');
      q = withDurationOperator(q, HistoryDurationBound.shorter, null);
      expect(q, 'longer:1m');
    });

    test('what is produced parses back to the same filter', () {
      for (final range in HistoryDateRange.values) {
        expect(parseSearchQuery(withDateOperator('x', range)).dateRange, range);
      }
      for (final seconds in [10, 30, 60, 300]) {
        final q = withDurationOperator(
          '',
          HistoryDurationBound.longer,
          seconds,
        );
        expect(parseSearchQuery(q).longerThanSec, seconds);
      }
    });
  });

  group('periods', () {
    // Wednesday 2026-11-18, 15:30.
    final now = DateTime(2026, 11, 18, 15, 30);

    test('today and yesterday are whole days', () {
      final today = resolveDateRange(HistoryDateRange.today, now);
      expect(today.from, DateTime(2026, 11, 18));
      expect(today.to, DateTime(2026, 11, 19));
      final yesterday = resolveDateRange(HistoryDateRange.yesterday, now);
      expect(yesterday.from, DateTime(2026, 11, 17));
      expect(yesterday.to, DateTime(2026, 11, 18));
    });

    test('7 and 30 days include today; the month starts on the 1st', () {
      expect(
        resolveDateRange(HistoryDateRange.last7Days, now).from,
        DateTime(2026, 11, 12),
      );
      expect(
        resolveDateRange(HistoryDateRange.last30Days, now).from,
        DateTime(2026, 10, 20),
      );
      expect(
        resolveDateRange(HistoryDateRange.monthToDate, now).from,
        DateTime(2026, 11),
      );
    });
  });

  group('database filter', () {
    late HistoryDatabase db;

    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      Future<void> add(String id, DateTime at, double seconds) =>
          db.insertHistoryEntry(
            HistoryEntriesCompanion.insert(
              id: id,
              timestamp: at,
              durationSec: Value(seconds),
            ),
          );
      await add('short-old', DateTime(2026, 11, 1, 9), 5);
      await add('long-old', DateTime(2026, 11, 2, 9), 200);
      await add('short-new', DateTime(2026, 11, 18, 9), 8);
      await add('long-new', DateTime(2026, 11, 18, 10), 90);
    });

    tearDown(() => db.close());

    Future<Set<String>> ids({
      DateTime? from,
      DateTime? to,
      int? longer,
      int? shorter,
    }) async => (await db.searchEntriesAdvanced(
      from: from,
      to: to,
      longerThanSec: longer,
      shorterThanSec: shorter,
    )).map((e) => e.id).toSet();

    test('a period keeps only entries inside it', () async {
      final range = resolveDateRange(
        HistoryDateRange.today,
        DateTime(2026, 11, 18, 12),
      );
      expect(await ids(from: range.from, to: range.to), {
        'short-new',
        'long-new',
      });
    });

    test('length bounds exclude the threshold itself and combine', () async {
      expect(await ids(longer: 8), {'long-old', 'long-new'});
      expect(await ids(shorter: 90), {'short-old', 'short-new'});
      expect(await ids(longer: 5, shorter: 200), {'short-new', 'long-new'});
    });

    test('period and length narrow each other', () async {
      final range = resolveDateRange(
        HistoryDateRange.today,
        DateTime(2026, 11, 18, 12),
      );
      expect(await ids(from: range.from, to: range.to, longer: 60), {
        'long-new',
      });
    });

    test('the filter badges count the same entries as the list', () async {
      final container = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      container.read(historySearchProvider.notifier).set('longer:100s');
      final longer = await container.read(searchCountsProvider.future);
      expect(longer?[HistoryFilter.all], 1);

      container.read(historySearchProvider.notifier).set('shorter:10s');
      final shorter = await container.read(searchCountsProvider.future);
      expect(shorter?[HistoryFilter.all], 2);
    });
  });

  group('chips', () {
    testWidgets('a period chip and "any time" write and clear the operator', (
      tester,
    ) async {
      final written = <String>[];
      var query = 'invoice';
      await tester.pumpWidget(
        makeTestable(
          HistoryRangeChips(
            parsed: parseSearchQuery(query),
            query: query,
            onQueryChanged: written.add,
          ),
          locale: const Locale('en'),
        ),
      );

      await tester.tap(find.bySemanticsIdentifier('history-range-7d'));
      await tester.pump();
      expect(written.single, 'invoice date:7d');

      query = 'invoice date:7d';
      await tester.pumpWidget(
        makeTestable(
          HistoryRangeChips(
            parsed: parseSearchQuery(query),
            query: query,
            onQueryChanged: written.add,
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.ensureVisible(
        find.bySemanticsIdentifier('history-range-any'),
      );
      await tester.tap(find.bySemanticsIdentifier('history-range-any'));
      await tester.pump();
      expect(written.last, 'invoice');
    });
  });
}
