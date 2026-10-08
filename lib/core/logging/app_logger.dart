/// Semantic logging wrapper — all application logging goes through this.
///
/// In **debug** mode every level is printed to both Dart DevTools
/// (`dev.log`) AND the terminal stdout (`debugPrint`) so errors are
/// visible in the `flutter run` console.
/// In **release** mode only `info`, `warning`, `error`, and `fatal` are
/// forwarded — and only to DevTools (no stdout).
///
/// **Persistent log file**: All info+ messages are written to
/// `%LOCALAPPDATA%/Whispaste/logs/whispaste.log` (or platform equivalent).
/// The file is rotated when it exceeds 2 MB, keeping up to 5 numbered
/// backups (`whispaste.log.1` … `.5`, oldest deleted) — bounded at ~12 MB
/// total. Lines are redacted for known secret patterns before hitting disk
/// and single-lined to prevent log injection via attacker-controlled text.
library;

import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart' as diag;
import '../../services/path_service.dart' as paths;
import 'breadcrumbs.dart';
import 'crash_fingerprints.dart';
import 'crash_reporter.dart';

/// Simple semantic logger wrapping [package:logging].
///
/// Usage:
/// ```dart
/// final _log = AppLogger('FeatureName');
/// _log.info('Recording started');
/// _log.error('Pipeline failed', error, stackTrace);
/// ```
class AppLogger {
  AppLogger(String name) : _logger = Logger(name);

  final Logger _logger;

  void debug(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.fine(message, error, stackTrace);

  void info(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.info(message, error, stackTrace);

  void warning(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.warning(message, error, stackTrace);

  void error(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.severe(message, error, stackTrace);
}

// ---------------------------------------------------------------------------
// Global logging configuration
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Persistent file logging
// ---------------------------------------------------------------------------

/// Shifts numbered rotated log files up by one slot and moves the primary
/// file (at [basePath]) into slot `.1`, dropping whatever previously sat in
/// the oldest slot (`.$maxRotations`).
///
/// Pure file-system side effect, extracted from [_LogFileSink] so the
/// rotation scheme (which [diag.rotatedLogPaths] / the diagnostics reader
/// must match) can be exercised directly in tests.
@visibleForTesting
void shiftRotatedLogFiles(String basePath, {int maxRotations = 5}) {
  final oldest = File('$basePath.$maxRotations');
  if (oldest.existsSync()) oldest.deleteSync();
  for (var i = maxRotations - 1; i >= 1; i--) {
    final src = File('$basePath.$i');
    if (src.existsSync()) src.renameSync('$basePath.${i + 1}');
  }
  final primary = File(basePath);
  if (primary.existsSync()) primary.renameSync('$basePath.1');
}

/// Prevents log injection (forged fake log lines) and keeps a single
/// physical line per record: control characters and newlines in
/// caller-supplied content are escaped rather than written verbatim.
@visibleForTesting
String sanitizeLogLineForInjection(String s) {
  return s
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\n')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
}

/// Manages a log file with rotation (max 2 MB) and bounded retention.
///
/// Rotation scheme: `whispaste.log` → `whispaste.log.1` → … →
/// `whispaste.log.$_maxRotations` (oldest, deleted on next rotation).
/// This matches [diag.rotatedLogPaths], which the diagnostics reader and
/// the standalone WhisPaste-Diagnose CLI use to find rotated siblings —
/// keep both in sync when changing `_maxRotations`.
/// Worst-case disk usage is bounded at `_maxBytes * (_maxRotations + 1)`.
class _LogFileSink {
  _LogFileSink._();

  static const int _maxBytes = 2 * 1024 * 1024; // 2 MB
  static const int _maxRotations = 5;
  File? _file;

  // Deliberately synchronous file I/O (RandomAccessFile), not an async
  // IOSink: log calls arrive back-to-back from a broadcast StreamController
  // (package:logging), so a rotation triggered by one write must be fully
  // visible (new file handle, reset byte counter) before the very next
  // write — an unawaited `IOSink.close()` racing a fresh `openWrite()` on
  // the same path caused writes to land on an already-closed sink under
  // load (`Bad state: StreamSink is bound to a stream`), silently breaking
  // logging for the rest of the process. Synchronous writes are cheap
  // enough at our volume (single short lines, not high-throughput
  // streaming) and make the rotation boundary atomic from the caller's
  // point of view.
  RandomAccessFile? _raf;
  int _bytesWritten = 0;

  /// Initializes the file sink. Safe to call from main isolate only.
  Future<void> init() async {
    try {
      final appDir = paths.appDataDir();
      final logDir = Directory('$appDir${Platform.pathSeparator}logs');
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }
      _file = File('${logDir.path}${Platform.pathSeparator}whispaste.log');
      _bytesWritten = _file!.existsSync() ? _file!.lengthSync() : 0;
      _rotateIfNeeded();
      _raf = _file!.openSync(mode: FileMode.append);
      _writeLine(
        '--- Log session started '
        '(${DateTime.now().toIso8601String()}) ---',
      );
    } catch (e) {
      // File logging is best-effort — don't crash the app.
      debugPrint('LogFileSink: init failed: $e');
    }
  }

  void _rotateIfNeeded() {
    final file = _file;
    if (file == null || _bytesWritten < _maxBytes) return;
    try {
      _raf?.closeSync();
      _raf = null;
      shiftRotatedLogFiles(file.path, maxRotations: _maxRotations);
      _file = File(file.path);
      _bytesWritten = 0;
      _raf = _file!.openSync(mode: FileMode.append);
    } catch (e) {
      debugPrint('LogFileSink: rotate failed: $e');
    }
  }

  void _writeLine(String line) {
    if (_raf == null) return;
    try {
      final redacted = diag.redactSensitive(line);
      final bytes = utf8.encode('$redacted\n');
      _raf!.writeFromSync(bytes);
      _bytesWritten += bytes.length;
      if (_bytesWritten >= _maxBytes) {
        _rotateIfNeeded();
      }
    } catch (e) {
      // Best-effort — don't propagate file I/O errors to logging callers.
      // debugPrint is used deliberately here to avoid recursive logger calls.
      debugPrint('LogFileSink: writeLine failed: $e');
    }
  }

  void write(LogRecord record) {
    final ts = record.time.toIso8601String().substring(0, 23);
    final message = sanitizeLogLineForInjection(record.message);
    final buf = StringBuffer(
      '$ts [${record.level.name}] ${record.loggerName}: $message',
    );
    if (record.error != null) {
      buf.write('\n  Error: ${sanitizeLogLineForInjection('${record.error}')}');
    }
    if (record.stackTrace != null) buf.write('\n${record.stackTrace}');
    _writeLine(buf.toString());
  }

  Future<void> close() async {
    try {
      _raf?.flushSync();
      _raf?.closeSync();
    } catch (e) {
      debugPrint('LogFileSink: close failed: $e');
    }
    _raf = null;
  }
}

/// The global file sink instance (initialized in [configureLogging]).
_LogFileSink? _fileSink;

/// Returns the path to the current log file, or null if not initialized.
String? get logFilePath => _fileSink?._file?.path;

/// Runs [body] with the persistent log file closed and reopens it
/// afterwards. Deleting the logs directory (factory reset) while our own
/// handle is open fails on Windows with a sharing violation (errno 32,
/// Sentry 123406956). Lines logged meanwhile are not written to the file.
Future<void> withLogFileReleased(Future<void> Function() body) async {
  final sink = _fileSink;
  if (sink == null) return body();
  await sink.close();
  try {
    await body();
  } finally {
    await sink.init();
  }
}

/// Closes the open file handle so a temp directory used via
/// [paths.appDataDirOverride] can be deleted afterwards — on Windows,
/// deleting a directory while one of its files is still open throws.
@visibleForTesting
Future<void> closeLogFileSinkForTest() async {
  await _fileSink?.close();
  _fileSink = null;
}

/// Call once during app bootstrap (before `runApp`).
///
/// Wires `package:logging` → `developer.log` + `debugPrint` (debug only)
/// + breadcrumb ring + persistent log file + crash reporter auto-capture.
Future<void> configureLogging() async {
  // In release mode, filter out trace/debug.
  Logger.root.level = kReleaseMode ? Level.INFO : Level.ALL;

  // Initialize persistent file logging.
  _fileSink = _LogFileSink._();
  await _fileSink!.init();

  final path = logFilePath;
  if (path != null) {
    debugPrint('Log file: $path');
  }

  Logger.root.onRecord.listen((record) {
    // Format: "[LEVEL] LoggerName: message"
    final line =
        '[${record.level.name}] ${record.loggerName}: ${record.message}';

    // Always feed breadcrumb ring.
    breadcrumbRing.add(line);

    // Print to Dart DevTools (visible in DevTools log tab).
    dev.log(
      record.message,
      name: record.loggerName,
      level: record.level.value,
      error: record.error,
      stackTrace: record.stackTrace,
    );

    // --- DEBUG MODE: also print to terminal stdout -------------------------
    // This makes all app-level logs visible in the `flutter run` console.
    // info+ in debug mode covers toast messages, recording state, etc.
    if (!kReleaseMode && record.level >= Level.INFO) {
      final buf = StringBuffer(line);
      if (record.error != null) buf.write('\n  Error: ${record.error}');
      if (record.stackTrace != null) {
        buf.write('\n${record.stackTrace}');
      }
      // debugPrint is rate-limited and safe for terminal output.
      debugPrint(buf.toString());
    }

    // Persistent file: write debug+ in debug mode, info+ in release.
    const fileThreshold = kReleaseMode ? Level.INFO : Level.FINE;
    if (record.level >= fileThreshold) {
      _fileSink?.write(record);
    }

    // Feed Sentry breadcrumbs for all INFO+ messages.
    if (record.level >= Level.INFO) {
      final sentryLevel = switch (record.level) {
        Level.WARNING => SentryLevel.warning,
        Level.SEVERE => SentryLevel.error,
        Level.SHOUT => SentryLevel.fatal,
        _ => SentryLevel.info,
      };
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: '${record.loggerName}: ${record.message}',
          level: sentryLevel,
          category: record.loggerName,
          timestamp: record.time,
        ),
      );
    }

    // Auto-escalate errors/fatals to Sentry via crash reporter.
    // Warnings are breadcrumbs only (above) to avoid noise in Sentry quota.
    if (record.level >= Level.SEVERE) {
      final severity = switch (record.level) {
        Level.SEVERE => 'error',
        Level.SHOUT => 'critical',
        _ => 'error',
      };

      CrashReporter.instance?.captureError(
        message: record.message,
        error: record.error,
        stackTrace: record.stackTrace,
        severity: severity,
        type: record.level == Level.SHOUT ? 'fatal' : 'error',
        // Catch-all fingerprint for un-categorized auto-escalations.
        // Call sites that want their own grouping must use
        // CrashReporter.instance.captureError directly with a constant
        // from crash_fingerprints.dart.
        fingerprint: const [appLoggerAutoEscalated],
      );
    }
  });
}
