/// Micro-benchmark for the per-save history trim (`trimToMaxEntries`).
///
/// Every dictation saves one history entry, and the save runs before the
/// paste, so the trim cost is on the Hotkey -> text path. Skipped in the
/// default sweep. Run with:
///
/// ```sh
/// flutter test test/benchmark/history_trim_bench_test.dart \
///   --dart-define=WP_BENCH=1 --dart-define=ENTRIES=1000 --dart-define=REPEAT=50
/// ```
library;

// ignore_for_file: avoid_print — a manual measurement tool; stdout is the
// deliverable.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

const _enabled = bool.fromEnvironment('WP_BENCH');
const _entries = int.fromEnvironment('ENTRIES', defaultValue: 1000);
const _repeat = int.fromEnvironment('REPEAT', defaultValue: 50);

void main() {
  test(
    'trimToMaxEntries per-save cost at steady state',
    skip: _enabled ? false : 'set --dart-define=WP_BENCH=1 to run',
    () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final base = DateTime(2026, 1, 1);
      await db.batch((b) {
        b.insertAll(db.historyEntries, [
          for (var i = 0; i < _entries; i++)
            HistoryEntriesCompanion.insert(
              id: 'seed-$i',
              timestamp: base.add(Duration(seconds: i)),
            ),
        ]);
      });

      final timesUs = <int>[];
      for (var i = 0; i < _repeat; i++) {
        // One new dictation, then the trim that runs in the same save.
        await db.insertHistoryEntry(
          HistoryEntriesCompanion.insert(
            id: 'new-$i',
            timestamp: base.add(Duration(seconds: _entries + i)),
          ),
        );
        final sw = Stopwatch()..start();
        final trimmed = await db.trimToMaxEntries(_entries);
        sw.stop();
        expect(trimmed, 1, reason: 'exactly one excess entry per save');
        timesUs.add(sw.elapsedMicroseconds);
      }

      timesUs.sort();
      final median = timesUs[timesUs.length ~/ 2];
      final p90 =
          timesUs[(timesUs.length * 0.9).floor().clamp(0, timesUs.length - 1)];
      print(
        'history_trim entries=$_entries repeat=$_repeat '
        'median_us=$median p90_us=$p90 '
        'dart=${Platform.version.split(' ').first}',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
