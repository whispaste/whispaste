/// Tests for the 14-day log retention (security review R-10): on every
/// start, log lines older than [logMaxAge] leave the primary file and the
/// rotated backups, in addition to the size-based rotation.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/logging/app_logger.dart';

void main() {
  final now = DateTime(2026, 10, 19, 12);
  late Directory dir;
  late String base;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp_log_retention_test_');
    base = '${dir.path}${Platform.pathSeparator}whispaste.log';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String ts(int daysAgo, [int minute = 0]) => now
      .subtract(Duration(days: daysAgo))
      .add(Duration(minutes: minute))
      .toIso8601String()
      .substring(0, 23);

  File write(String path, List<String> lines, {required int touchedDaysAgo}) {
    final file = File(path)..writeAsStringSync('${lines.join('\n')}\n');
    file.setLastModifiedSync(now.subtract(Duration(days: touchedDaysAgo)));
    return file;
  }

  test('keeps 14 days', () {
    expect(logMaxAge, const Duration(days: 14));
  });

  test('a backup whose newest line is past the limit is deleted', () {
    final old = write('$base.3', [
      '${ts(20)} [INFO] Old: one',
    ], touchedDaysAgo: 20);
    final recent = write('$base.1', [
      '${ts(2)} [INFO] Recent: one',
    ], touchedDaysAgo: 2);

    pruneExpiredLogFiles(base, now: now);

    expect(old.existsSync(), isFalse);
    expect(recent.readAsStringSync(), contains('Recent: one'));
  });

  test('a file spanning the limit loses only its expired lines', () {
    final primary = write(base, [
      '--- Log session started (${now.subtract(const Duration(days: 30)).toIso8601String()}) ---',
      '${ts(30)} [INFO] Old: before',
      '${ts(15)} [SEVERE] Old: failed',
      '  Error: boom',
      '#0      main (file:///x.dart:1:1)',
      '--- Log session started (${now.subtract(const Duration(days: 3)).toIso8601String()}) ---',
      '${ts(3)} [INFO] New: kept',
      '${ts(0, -5)} [INFO] New: latest',
    ], touchedDaysAgo: 0);

    pruneExpiredLogFiles(base, now: now);

    expect(primary.readAsLinesSync(), [
      '--- Log session started (${now.subtract(const Duration(days: 3)).toIso8601String()}) ---',
      '${ts(3)} [INFO] New: kept',
      '${ts(0, -5)} [INFO] New: latest',
    ]);
  });

  test('a file without expired lines is left untouched', () {
    final primary = write(base, [
      '${ts(13)} [INFO] Fresh: one',
      '${ts(1)} [INFO] Fresh: two',
    ], touchedDaysAgo: 1);
    final before = primary.lastModifiedSync();

    pruneExpiredLogFiles(base, now: now);

    expect(primary.lastModifiedSync(), before);
    expect(primary.readAsLinesSync(), hasLength(2));
  });

  test('missing files and unparsable lines do not throw', () {
    write(base, ['no timestamp here', 'nor here'], touchedDaysAgo: 0);

    expect(() => pruneExpiredLogFiles(base, now: now), returnsNormally);
    expect(File(base).readAsLinesSync(), hasLength(2));
  });
}
