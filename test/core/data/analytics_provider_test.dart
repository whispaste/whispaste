/// Tests for [analyticsProvider]'s hotkey→text latency wiring (issue 08).
///
/// Confirms the provider reads the average purely from the local
/// [HistoryDatabase] aggregation added in issue 07 — no other source.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  group('time saved', () {
    test('typing at 50 words a minute minus the time spoken', () {
      // 500 words: 10 min typing, 2 min speaking.
      expect(
        analyticsTimeSavedMinutes(totalWords: 500, totalDurationSec: 120),
        8,
      );
    });

    test('never negative', () {
      expect(
        analyticsTimeSavedMinutes(totalWords: 10, totalDurationSec: 600),
        0,
      );
      expect(analyticsTimeSavedMinutes(totalWords: 0, totalDurationSec: 0), 0);
    });
  });

  group('dictation days', () {
    late HistoryDatabase db;

    setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> dictate(DateTime at, {int words = 5, String model = 'a'}) =>
        db.recordDailyStat(
          timestamp: at,
          model: model,
          isLocal: true,
          durationSec: 3,
          processingDurationSec: 1,
          wordCount: words,
          costUsd: 0,
        );

    test(
      'count distinct days with words since the start, reset clears',
      () async {
        await dictate(DateTime(2026, 10, 26, 8));
        await dictate(DateTime(2026, 10, 26, 18), model: 'b'); // same day
        await dictate(DateTime(2026, 10, 27, 9), words: 0); // no text
        await dictate(DateTime(2026, 10, 28, 9));
        await dictate(DateTime(2026, 10, 20, 9)); // week before

        expect(await db.analyticsActiveDays(), 3);
        expect(await db.analyticsActiveDays(since: DateTime(2026, 10, 26)), 2);

        await db.resetDailyStats();
        expect(await db.analyticsActiveDays(), 0);
      },
    );
  });

  group('analyticsProvider — hotkey latency KPI', () {
    late HistoryDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test(
      'reflects the average stop-to-text time of persisted samples',
      () async {
        await db.recordHotkeyLatency(
          recordedAt: DateTime.now(),
          latencyMs: 9000,
        );
        await db.recordHotkeyLatency(
          recordedAt: DateTime.now(),
          latencyMs: 4000,
          stopToTextMs: 1000,
        );
        await db.recordHotkeyLatency(
          recordedAt: DateTime.now(),
          latencyMs: 5000,
          stopToTextMs: 2000,
        );

        final data = await container.read(analyticsProvider.future);

        // Samples from before XP-6-09 carry no stop time and are skipped.
        expect(data.averageStopToTextMs, 1500.0);
      },
    );

    test('is null when no hotkey-latency samples have been recorded', () async {
      final data = await container.read(analyticsProvider.future);

      expect(data.averageStopToTextMs, isNull);
    });
  });
}
