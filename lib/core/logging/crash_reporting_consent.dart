/// File mirror of the `errorReporting` opt-out, readable before Sentry starts.
///
/// The setting itself lives in the SQLite settings table, which is only
/// opened after the Sentry zone is up. Native crash, app-hang and session
/// reporting cannot be gated from Dart once `SentryFlutter.init` has run, so
/// [AppMonitoring] checks this marker first and skips Sentry entirely.
/// Opt-outs stored before the marker existed are read once straight from
/// the settings table and migrated into it.
library;

import 'dart:developer' as dev;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show appDataDir;

class CrashReportingConsentMarker {
  /// [directory] defaults to the app data directory.
  CrashReportingConsentMarker({this.directory});

  final String? directory;

  static const fileName = 'crash_reporting_off';

  /// Drift database holding the `app_settings` key-value table.
  static const settingsDatabaseName = 'history.db';

  String get _directory => directory ?? appDataDir();

  File get _file => File(p.join(_directory, fileName));

  /// Whether the user opted out of error reporting. Fails open (`false`) when
  /// the location cannot be read; the settings sync right after startup then
  /// still closes Sentry.
  bool get optedOut {
    try {
      return _file.existsSync();
    } on FileSystemException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  /// [optedOut], falling back to the stored `error_reporting` setting when
  /// there is no marker yet. A stored opt-out is migrated into the marker.
  /// Costs one existence check, plus one single-row query while opted in.
  bool resolveOptedOut() {
    if (optedOut) return true;
    if (!_storedSettingOptedOut()) return false;
    record(granted: false);
    return true;
  }

  /// Fails open: a missing or unreadable database means "not opted out";
  /// the settings sync in main.dart still closes Sentry in that case.
  bool _storedSettingOptedOut() {
    final path = p.join(_directory, settingsDatabaseName);
    try {
      if (!File(path).existsSync()) return false;
      // readWrite without create: never makes a database appear, and works
      // on WAL databases whose -shm file is absent.
      final db = sqlite3.open(path, mode: OpenMode.readWrite);
      try {
        final rows = db.select(
          "SELECT value FROM app_settings WHERE key = 'error_reporting'",
        );
        return rows.isNotEmpty && rows.first['value'] == 'false';
      } finally {
        db.close();
      }
    } on SqliteException catch (e) {
      dev.log('Stored consent not readable: $e', name: 'CrashReporter');
      return false;
    } on FileSystemException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  /// Persists the current consent. Best effort: failures are swallowed so a
  /// read-only profile can never break the settings toggle.
  void record({required bool granted}) {
    try {
      final file = _file;
      if (granted) {
        if (file.existsSync()) file.deleteSync();
      } else {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('');
      }
    } on FileSystemException catch (e) {
      // Next start falls back to the settings sync in main.dart.
      dev.log('Consent marker not written: $e', name: 'CrashReporter');
    } on ArgumentError catch (e) {
      dev.log('Consent marker path invalid: $e', name: 'CrashReporter');
    }
  }
}
