/// Semantic logging wrapper — all application logging goes through this.
///
/// In **debug** mode every level is printed to both Dart DevTools
/// (`dev.log`) AND the terminal stdout (`debugPrint`) so errors are
/// visible in the `flutter run` console.
/// In **release** mode only `info`, `warning`, `error`, and `fatal` are
/// forwarded — and only to DevTools (no stdout).
///
/// Modeled after REDACTED-OTHER-PROJECT's `AppLogger` pattern but extended with
/// breadcrumb ring buffer for crash context.
library;

import 'dart:collection';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

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

  void trace(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.finest(message, error, stackTrace);

  void debug(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.fine(message, error, stackTrace);

  void info(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.info(message, error, stackTrace);

  void warning(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.warning(message, error, stackTrace);

  void error(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.severe(message, error, stackTrace);

  void fatal(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _logger.shout(message, error, stackTrace);
}

// ---------------------------------------------------------------------------
// Global logging configuration
// ---------------------------------------------------------------------------

/// Breadcrumb ring buffer — last N log lines kept for crash context.
class _BreadcrumbRing {
  _BreadcrumbRing(this._capacity);
  final int _capacity;
  final _buf = Queue<String>();

  void add(String line) {
    if (_buf.length >= _capacity) _buf.removeFirst();
    _buf.add(line);
  }

  List<String> get recent => _buf.toList();
}

final _breadcrumbs = _BreadcrumbRing(30);

/// Returns the most recent log lines for crash report context.
List<String> getRecentBreadcrumbs() => _breadcrumbs.recent;

/// Call once during app bootstrap (before `runApp`).
///
/// Wires `package:logging` → `developer.log` + `debugPrint` (debug only)
/// + breadcrumb ring + crash reporter auto-capture (warning/error/fatal).
void configureLogging() {
  // In release mode, filter out trace/debug.
  Logger.root.level = kReleaseMode ? Level.INFO : Level.ALL;

  Logger.root.onRecord.listen((record) {
    // Format: "[LEVEL] LoggerName: message"
    final line =
        '[${record.level.name}] ${record.loggerName}: ${record.message}';

    // Always feed breadcrumb ring.
    _breadcrumbs.add(line);

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

    // Auto-escalate warnings/errors/fatals to crash reporter.
    if (record.level >= Level.WARNING) {
      final severity = switch (record.level) {
        Level.WARNING => 'warning',
        Level.SEVERE => 'error',
        Level.SHOUT => 'critical',
        _ => 'info',
      };

      CrashReporter.instance?.captureError(
        message: record.message,
        error: record.error,
        stackTrace: record.stackTrace,
        severity: severity,
        type: record.level == Level.SHOUT ? 'fatal' : 'error',
      );
    }
  });
}
