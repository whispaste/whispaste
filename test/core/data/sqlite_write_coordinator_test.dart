import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/sqlite_write_coordinator.dart';
import 'package:whispaste/core/logging/crash_fingerprints.dart';

class _CaptureRecord {
  _CaptureRecord({
    required this.message,
    required this.fingerprint,
    required this.error,
  });

  final String message;
  final List<String> fingerprint;
  final Object? error;
}

void main() {
  group('SqliteWriteCoordinator.write', () {
    // AC3: SqliteException(5) retried with backoff, recovers within budget.
    test(
      'retries SqliteException(5) and returns the value once it succeeds',
      () async {
        final captured = <_CaptureRecord>[];
        final coord = SqliteWriteCoordinator.test(
          backoffs: const [Duration.zero, Duration.zero, Duration.zero],
          capture:
              ({
                required String message,
                required List<String> fingerprint,
                Object? error,
                StackTrace? stackTrace,
              }) {
                captured.add(
                  _CaptureRecord(
                    message: message,
                    fingerprint: fingerprint,
                    error: error,
                  ),
                );
              },
        );

        var calls = 0;
        final result = await coord.write<String>(() async {
          calls++;
          if (calls < 3) {
            throw SqliteException(
              extendedResultCode: 5,
              message: 'database is locked',
            );
          }
          return 'ok';
        });

        expect(result, 'ok');
        expect(calls, 3, reason: 'action runs once then is retried twice');
        expect(
          captured,
          isEmpty,
          reason: 'no capture on recoverable busy outcomes',
        );
      },
    );

    // AC4: After all retries exhausted, captures once with historyWriteFailed
    // and rethrows.
    test(
      'after exhausting retries, captures once with historyWriteFailed and rethrows',
      () async {
        final captured = <_CaptureRecord>[];
        final coord = SqliteWriteCoordinator.test(
          backoffs: const [Duration.zero, Duration.zero, Duration.zero],
          capture:
              ({
                required String message,
                required List<String> fingerprint,
                Object? error,
                StackTrace? stackTrace,
              }) {
                captured.add(
                  _CaptureRecord(
                    message: message,
                    fingerprint: fingerprint,
                    error: error,
                  ),
                );
              },
        );

        var calls = 0;
        await expectLater(
          coord.write<void>(() async {
            calls++;
            throw SqliteException(
              extendedResultCode: 5,
              message: 'database is locked',
            );
          }),
          throwsA(isA<SqliteException>()),
        );

        expect(
          calls,
          4,
          reason: '1 initial attempt + 3 retries from the backoff schedule',
        );
        expect(captured, hasLength(1));
        expect(captured.single.fingerprint, equals(const [historyWriteFailed]));
        expect(captured.single.error, isA<SqliteException>());
      },
    );

    // AC5: Non-busy SqliteException → no retries, capture with historyWriteOther.
    test(
      'non-busy SqliteException is not retried and uses historyWriteOther fingerprint',
      () async {
        final captured = <_CaptureRecord>[];
        final coord = SqliteWriteCoordinator.test(
          backoffs: const [Duration.zero, Duration.zero, Duration.zero],
          capture:
              ({
                required String message,
                required List<String> fingerprint,
                Object? error,
                StackTrace? stackTrace,
              }) {
                captured.add(
                  _CaptureRecord(
                    message: message,
                    fingerprint: fingerprint,
                    error: error,
                  ),
                );
              },
        );

        var calls = 0;
        await expectLater(
          coord.write<void>(() async {
            calls++;
            // 19 = SQLITE_CONSTRAINT
            throw SqliteException(
              extendedResultCode: 19,
              message: 'constraint violation',
            );
          }),
          throwsA(isA<SqliteException>()),
        );

        expect(calls, 1, reason: 'constraint errors are not retried');
        expect(captured, hasLength(1));
        expect(captured.single.fingerprint, equals(const [historyWriteOther]));
      },
    );

    test('serialises actions — only one runs at a time', () async {
      final coord = SqliteWriteCoordinator.test(backoffs: const []);
      int active = 0;
      int maxActive = 0;

      Future<void> task() => coord.write<void>(() async {
        active++;
        if (active > maxActive) maxActive = active;
        // Yield several times so a parallel attempt could interleave
        // if the lock were not in place.
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        active--;
      });

      await Future.wait<void>([task(), task(), task(), task()]);

      expect(maxActive, 1, reason: 'lock guarantees single-writer');
    });
  });

  // AC6: Real HistoryDatabase with the coordinator — concurrent saveEntry +
  // purgeTrash on an in-memory DB must terminate cleanly within 2 s.
  group('SqliteWriteCoordinator integration', () {
    test(
      'parallel saveEntry + purgeTrash on in-memory DB terminate within 2 s',
      () async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        try {
          // Seed: 5 trashed entries old enough for purgeTrash.
          final old = DateTime.now().subtract(const Duration(days: 60));
          for (var i = 0; i < 5; i++) {
            await db.upsertEntry(
              HistoryEntriesCompanion.insert(
                id: 'trashed-$i',
                timestamp: old,
                deletedAt: Value(old),
              ),
            );
          }

          final stopwatch = Stopwatch()..start();
          await Future.wait<void>([
            for (var i = 0; i < 20; i++)
              db.upsertEntry(
                HistoryEntriesCompanion.insert(
                  id: 'fresh-$i',
                  timestamp: DateTime.now(),
                ),
              ),
            db.purgeTrash(days: 30),
            db.purgeTrash(days: 30),
            db.purgeTrash(days: 30),
          ]).timeout(const Duration(seconds: 2));
          stopwatch.stop();

          expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
        } finally {
          await db.close();
        }
      },
    );
  });
}
