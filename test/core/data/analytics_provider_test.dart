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
      'reflects the average of locally persisted hotkey-latency samples',
      () async {
        await db.recordHotkeyLatency(
          recordedAt: DateTime.now(),
          latencyMs: 1000,
        );
        await db.recordHotkeyLatency(
          recordedAt: DateTime.now(),
          latencyMs: 2000,
        );

        final data = await container.read(analyticsProvider.future);

        expect(data.averageHotkeyLatencyMs, 1500.0);
      },
    );

    test('is null when no hotkey-latency samples have been recorded', () async {
      final data = await container.read(analyticsProvider.future);

      expect(data.averageHotkeyLatencyMs, isNull);
    });
  });
}
