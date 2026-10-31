/// Unit tests for the log-file rotation and log-injection hardening in
/// `app_logger.dart`. These exercise the extracted pure/file-system helpers
/// directly — the private `_LogFileSink` itself is not testable from here.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/logging/app_logger.dart';
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart' as diag;

void main() {
  group('sanitizeLogLineForInjection', () {
    test('escapes embedded newlines so one record stays one line', () {
      final result = sanitizeLogLineForInjection(
        'clicked "Delete"\n[SEVERE] Fake: forged entry',
      );
      expect(result, isNot(contains('\n')));
      expect(result, contains(r'\n'));
    });

    test('escapes carriage returns', () {
      expect(sanitizeLogLineForInjection('a\rb'), r'a\nb');
    });

    test('strips other control characters', () {
      expect(sanitizeLogLineForInjection('a\x00\x07b'), 'ab');
    });

    test('leaves normal text unchanged', () {
      const input = 'Recording started (sessionId=abc123)';
      expect(sanitizeLogLineForInjection(input), input);
    });
  });

  group('shiftRotatedLogFiles', () {
    late Directory tmp;
    late String basePath;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('wp_log_rotation_test');
      basePath = '${tmp.path}${Platform.pathSeparator}whispaste.log';
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('moves the primary file into slot .1', () {
      File(basePath).writeAsStringSync('current');
      shiftRotatedLogFiles(basePath, maxRotations: 5);

      expect(File(basePath).existsSync(), isFalse);
      expect(File('$basePath.1').readAsStringSync(), 'current');
    });

    test('shifts existing rotated files up by one slot', () {
      File(basePath).writeAsStringSync('current');
      File('$basePath.1').writeAsStringSync('one');
      File('$basePath.2').writeAsStringSync('two');

      shiftRotatedLogFiles(basePath, maxRotations: 5);

      expect(File('$basePath.1').readAsStringSync(), 'current');
      expect(File('$basePath.2').readAsStringSync(), 'one');
      expect(File('$basePath.3').readAsStringSync(), 'two');
    });

    test('drops the oldest slot once maxRotations is exceeded', () {
      File(basePath).writeAsStringSync('current');
      for (var i = 1; i <= 5; i++) {
        File('$basePath.$i').writeAsStringSync('slot-$i');
      }

      shiftRotatedLogFiles(basePath, maxRotations: 5);

      // slot 5 ("slot-5", the oldest) must be gone; everything else shifted.
      expect(File('$basePath.1').readAsStringSync(), 'current');
      expect(File('$basePath.5').readAsStringSync(), 'slot-4');
      expect(File('$basePath.6').existsSync(), isFalse);
    });

    test('is a no-op when no files exist', () {
      expect(
        () => shiftRotatedLogFiles(basePath, maxRotations: 5),
        returnsNormally,
      );
      expect(File('$basePath.1').existsSync(), isFalse);
    });

    test('resulting rotated paths match diagnostics reader expectations', () {
      File(basePath).writeAsStringSync('current');
      shiftRotatedLogFiles(basePath, maxRotations: 5);

      final expected = diag.rotatedLogPaths(basePath, maxRotations: 5);
      expect(expected.first, '$basePath.1');
      expect(File(expected.first).existsSync(), isTrue);
    });
  });
}
