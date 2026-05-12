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
/// The file is rotated when it exceeds 2 MB.
library;

import 'dart:collection';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../services/path_service.dart' as paths;
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

// ---------------------------------------------------------------------------
// Persistent file logging
// ---------------------------------------------------------------------------

/// Manages a log file with rotation (max 2 MB).
class _LogFileSink {
  _LogFileSink._();

  static const int _maxBytes = 2 * 1024 * 1024; // 2 MB
  File? _file;
  IOSink? _sink;
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
      _sink = _file!.openWrite(mode: FileMode.append);
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
    if (_file == null || _bytesWritten < _maxBytes) return;
    try {
      final oldFile = File('${_file!.path}.old');
      if (oldFile.existsSync()) oldFile.deleteSync();
      _file!.renameSync(oldFile.path);
      _file = File(_file!.path.replaceAll('.old', ''));
      _bytesWritten = 0;
    } catch (e) {
      debugPrint('LogFileSink: rotate failed: $e');
    }
  }

  void _writeLine(String line) {
    if (_sink == null) return;
    try {
      _sink!.writeln(line);
      _bytesWritten += line.length + 1;
      if (_bytesWritten >= _maxBytes) {
        _sink!.flush();
        _sink!.close();
        _rotateIfNeeded();
        _sink = _file!.openWrite(mode: FileMode.append);
      }
    } catch (_) {
      // Best-effort — don't propagate file I/O errors to logging callers.
    }
  }

  void write(LogRecord record) {
    final ts = record.time.toIso8601String().substring(0, 23);
    final buf = StringBuffer(
      '$ts [${record.level.name}] ${record.loggerName}: ${record.message}',
    );
    if (record.error != null) buf.write('\n  Error: ${record.error}');
    if (record.stackTrace != null) buf.write('\n${record.stackTrace}');
    _writeLine(buf.toString());
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}

/// The global file sink instance (initialized in [configureLogging]).
_LogFileSink? _fileSink;

/// Returns the path to the current log file, or null if not initialized.
String? get logFilePath => _fileSink?._file?.path;

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
      );
    }
  });
}
