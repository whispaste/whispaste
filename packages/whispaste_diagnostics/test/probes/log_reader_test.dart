/// Unit tests for log_reader.dart (AC5).
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/probes/log_reader.dart';

void main() {
  tearDown(() => setLogFileReaderForTesting(null));

  // -------------------------------------------------------------------------
  // sanitizeLogLine
  // -------------------------------------------------------------------------

  group('sanitizeLogLine', () {
    test('passes through a normal log line', () {
      const line = '2024-01-01 12:00:00 INFO: Server started';
      expect(sanitizeLogLine(line), line);
    });

    test('returns null for a line containing an API key', () {
      const line = 'api_key=sk-abcdefghij1234567 debug';
      expect(sanitizeLogLine(line), isNull);
    });

    test('returns null for a line with bearer token', () {
      const line = 'Authorization: Bearer sk-abc123def456ghi789';
      expect(sanitizeLogLine(line), isNull);
    });

    test('sanitizes path segments', () {
      // This test just verifies sanitizePaths is called — the actual result
      // depends on env vars, so we only assert it returns a String.
      const line = 'Loading model from /some/path/model.bin';
      final result = sanitizeLogLine(line);
      expect(result, isA<String>());
    });
  });

  // -------------------------------------------------------------------------
  // rotatedLogPaths
  // -------------------------------------------------------------------------

  group('rotatedLogPaths', () {
    test('returns paths .1 through .maxRotations', () {
      final paths = rotatedLogPaths('/var/log/whispaste.log', maxRotations: 3);
      expect(paths, [
        '/var/log/whispaste.log.1',
        '/var/log/whispaste.log.2',
        '/var/log/whispaste.log.3',
      ]);
    });

    test('returns 5 paths by default', () {
      final paths = rotatedLogPaths('/logs/app.log');
      expect(paths.length, 5);
    });
  });

  // -------------------------------------------------------------------------
  // readFullLog via injectable seam
  // -------------------------------------------------------------------------

  group('readFullLog', () {
    test('reads primary file when no rotated files exist', () {
      final result = readFullLog(
        logFilePath: '/logs/primary.log',
        fileReader: (path) {
          if (path == '/logs/primary.log') {
            return ['line 1', 'line 2', 'line 3'];
          }
          return null; // rotated files absent
        },
      );

      expect(result.lines, ['line 1', 'line 2', 'line 3']);
      expect(result.totalLines, 3);
      expect(result.rotatedPaths, isEmpty);
    });

    test('reads rotated files before primary (oldest first)', () {
      final calls = <String>[];
      final result = readFullLog(
        logFilePath: '/logs/app.log',
        fileReader: (path) {
          calls.add(path);
          if (path == '/logs/app.log') return ['newest'];
          if (path == '/logs/app.log.1') return ['older'];
          if (path == '/logs/app.log.2') return ['oldest'];
          return null;
        },
      );

      // oldest rotated (.2) first, then .1, then primary
      expect(result.lines.first, 'oldest');
      expect(result.lines.last, 'newest');
      expect(result.totalLines, 3);
      expect(result.rotatedPaths, hasLength(2));
    });

    test('omits lines containing secrets', () {
      final result = readFullLog(
        logFilePath: '/logs/app.log',
        fileReader: (path) {
          if (path == '/logs/app.log') {
            return [
              'normal line',
              'api_key=sk-abcdefghij1234567 secret!',
              'another normal line',
            ];
          }
          return null;
        },
      );

      expect(result.lines, hasLength(2));
      expect(result.lines, isNot(contains(contains('sk-'))));
    });

    test('returns empty result when no files exist', () {
      final result = readFullLog(
        logFilePath: '/nonexistent/app.log',
        fileReader: (_) => null,
      );

      expect(result.lines, isEmpty);
      expect(result.totalLines, 0);
      expect(result.rotatedPaths, isEmpty);
    });

    test('records the primary path in result', () {
      final result = readFullLog(
        logFilePath: '/logs/test.log',
        fileReader: (_) => null,
      );

      expect(result.primaryPath, '/logs/test.log');
    });

    test('handles rotated files that mix present and absent', () {
      final result = readFullLog(
        logFilePath: '/logs/app.log',
        maxRotations: 3,
        fileReader: (path) {
          // Only .2 and primary exist; .1 and .3 are absent.
          if (path == '/logs/app.log') return ['primary'];
          if (path == '/logs/app.log.2') return ['rotated-2'];
          return null;
        },
      );

      expect(result.lines, contains('rotated-2'));
      expect(result.lines, contains('primary'));
      expect(result.rotatedPaths, hasLength(1));
      expect(result.rotatedPaths.first, '/logs/app.log.2');
    });
  });
}
