/// Logger-side regression for DEV-121: an interpolated SqliteException must
/// reach the breadcrumb ring (the Sentry breadcrumb context) and the log file
/// without its bound parameters.
///
/// `configureLogging()` may run only once per process, so this scenario lives
/// alone in its own test file.
library;

import 'dart:io';

import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/logging/app_logger.dart';
import 'package:whispaste/core/logging/breadcrumbs.dart';
import 'package:whispaste/services/path_service.dart' as paths;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('interpolated SqliteException loses its parameters in breadcrumbs and '
      'the log file', () async {
    final tempDir = Directory.systemTemp.createTempSync('wp_sqlite_log_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    paths.appDataDirOverride = tempDir.path;
    addTearDown(() => paths.appDataDirOverride = null);
    addTearDown(closeLogFileSinkForTest);

    await configureLogging();
    final log = AppLogger('HistoryWrite');

    const transcript = 'Diktattext mit Geheimnis';
    final error = SqliteException(
      extendedResultCode: 1555,
      message: 'UNIQUE constraint failed: history_entries.id',
      operation: 'executing',
      causingStatement:
          'INSERT INTO history_entries (id, content) VALUES (?, ?)',
      parametersToStatement: const ['entry-1', transcript],
    );

    // Interpolation, the pattern used by ~180 log calls in the app.
    log.warning('Save to history failed: $error');
    // Error passed as the separate error argument.
    log.error('Save to history failed', error);

    final ring = breadcrumbRing.recent.join('\n');
    expect(ring, contains('Save to history failed'));
    expect(ring, contains('INSERT INTO history_entries'));
    expect(ring, isNot(contains(transcript)));
    expect(ring, isNot(contains('entry-1')));

    await closeLogFileSinkForTest();
    final logFile = File(
      '${tempDir.path}${Platform.pathSeparator}logs'
      '${Platform.pathSeparator}whispaste.log',
    );
    final written = logFile.readAsStringSync();
    expect(written, contains('Save to history failed'));
    expect(written, isNot(contains(transcript)));
  });
}
