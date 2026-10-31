/// Single-writer coordinator for SQLite mutations on the history DB.
///
/// All write paths in [HistoryDatabase] route through [write], which:
///   1. Serialises mutations through a `package:synchronized` [Lock] so two
///      concurrent flows (e.g. saving an Aufnahme-Vorgang while restoring a
///      trashed entry) can never race on the same connection.
///   2. Retries `SqliteException` with primary `resultCode == 5`
///      (`SQLITE_BUSY` — "database is locked") with the
///      `[50ms, 100ms, 200ms]` backoff schedule from the reliability-sprint
///      PRD, Modul 5. Only the final, non-recoverable failure is reported
///      to Sentry — bundled under the `history-write-failed` fingerprint so
///      Sentry duplicates like the WP-7B…7M cluster collapse to one issue.
///   3. Reports all other `SqliteException` instances under the
///      `history-write-other` fingerprint and rethrows immediately —
///      constraint violations etc. are not retriable.
///
/// Design notes:
/// - The coordinator owns no DB connection. It is a pure orchestration
///   layer above `Future<T> Function()` work items.
/// - The lock is process-wide per [SqliteWriteCoordinator] instance. The
///   default instance is held by [HistoryDatabase].
/// - The lock must be taken **before** any inner Drift `transaction(...)`
///   call so that two coordinator-routed mutations never both hold the
///   lock and the Drift transaction lock in opposite order — see PRD
///   §Risiken ("Vorbestehende Drift-Transaktionen").
/// - To keep the retry/backoff/capture logic testable, both the backoff
///   schedule and the capture sink are injected via private named
///   constructor parameters with production defaults.
library;

import 'dart:async';

import 'package:drift/native.dart' show SqliteException;
import 'package:synchronized/synchronized.dart';

import '../logging/crash_fingerprints.dart';
import '../logging/crash_reporter.dart';

/// Signature for the capture sink injected into [SqliteWriteCoordinator].
///
/// Production default routes to `CrashReporter.instance?.captureError(...)`.
/// Tests pass a spy that records each invocation.
typedef CrashCaptureSink =
    void Function({
      required String message,
      required List<String> fingerprint,
      Object? error,
      StackTrace? stackTrace,
    });

/// SQLite extended/primary result code for `SQLITE_BUSY` — "database is
/// locked". See https://sqlite.org/rescode.html#busy.
const int _sqliteBusyResultCode = 5;

/// Production default backoff schedule. Three retries, escalating sleeps
/// between attempts. Total worst-case added latency: 50 + 100 + 200 ms = 350 ms.
const List<Duration> _defaultBackoffs = <Duration>[
  Duration(milliseconds: 50),
  Duration(milliseconds: 100),
  Duration(milliseconds: 200),
];

/// Serialises and retries history-DB write actions.
class SqliteWriteCoordinator {
  /// Construct with production defaults.
  SqliteWriteCoordinator()
    : _backoffs = _defaultBackoffs,
      _capture = _defaultCaptureSink;

  /// Test-only constructor: injectable backoff schedule and capture sink.
  ///
  /// Pass an empty list for [backoffs] to disable retries entirely; pass
  /// `[Duration.zero, Duration.zero, Duration.zero]` to verify retry count
  /// without slowing down tests. Visible for testing only — production
  /// code constructs the coordinator via the default constructor.
  SqliteWriteCoordinator.test({
    List<Duration>? backoffs,
    CrashCaptureSink? capture,
  }) : _backoffs = backoffs ?? _defaultBackoffs,
       _capture = capture ?? _defaultCaptureSink;

  final List<Duration> _backoffs;
  final CrashCaptureSink _capture;
  final Lock _lock = Lock();

  /// Runs [action] under the single-writer lock, retrying on
  /// `SqliteException(SQLITE_BUSY)`.
  ///
  /// On exhausted retries, captures one Sentry event under
  /// `historyWriteFailed` and rethrows.
  /// On non-busy `SqliteException`, captures one event under
  /// `historyWriteOther` and rethrows (no retry).
  /// Non-Sqlite exceptions propagate unchanged.
  Future<T> write<T>(Future<T> Function() action) {
    return _lock.synchronized<T>(() => _runWithRetry<T>(action));
  }

  Future<T> _runWithRetry<T>(Future<T> Function() action) async {
    // Attempt budget: 1 initial + N retries, one retry per backoff entry.
    final int maxAttempts = _backoffs.length + 1;
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return await action();
      } on SqliteException catch (e, st) {
        final bool isBusy = e.resultCode == _sqliteBusyResultCode;
        if (!isBusy) {
          _capture(
            message: 'history-write non-busy SqliteException',
            fingerprint: const <String>[historyWriteOther],
            error: e,
            stackTrace: st,
          );
          rethrow;
        }
        // Busy — retry if budget remains.
        if (attempt >= maxAttempts) {
          _capture(
            message:
                'history-write SQLITE_BUSY persisted after $attempt attempts',
            fingerprint: const <String>[historyWriteFailed],
            error: e,
            stackTrace: st,
          );
          rethrow;
        }
        // attempt is 1-based; the i-th backoff is _backoffs[attempt - 1].
        final delay = _backoffs[attempt - 1];
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
      }
    }
  }
}

/// Default capture sink — forwards to the live [CrashReporter] singleton.
/// Safe no-op when `CrashReporter.instance` is null (e.g. test bootstrap
/// without `CrashReporter.init()`).
void _defaultCaptureSink({
  required String message,
  required List<String> fingerprint,
  Object? error,
  StackTrace? stackTrace,
}) {
  CrashReporter.instance?.captureError(
    message: message,
    fingerprint: fingerprint,
    error: error,
    stackTrace: stackTrace,
  );
}
