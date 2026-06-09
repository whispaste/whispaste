/// Unit tests for av_quarantine_probe.dart (AC4).
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/probes/av_quarantine_probe.dart';

void main() {
  // -------------------------------------------------------------------------
  // parseMacosQuarantined
  // -------------------------------------------------------------------------

  group('parseMacosQuarantined', () {
    test('returns true when com.apple.quarantine is present', () {
      const output = '''
/path/to/whisper-server:
com.apple.quarantine: 0001;5f3b1234;Safari;ABC123
''';
      expect(parseMacosQuarantined(output), isTrue);
    });

    test('returns false when com.apple.quarantine is absent', () {
      const output = '''
/path/to/whisper-server:
com.apple.metadata:kMDItemDownloadedDate: ...
''';
      expect(parseMacosQuarantined(output), isFalse);
    });

    test('returns false for null input', () {
      expect(parseMacosQuarantined(null), isFalse);
    });

    test('returns false for empty string', () {
      expect(parseMacosQuarantined(''), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // parseMacosQuarantineDetail
  // -------------------------------------------------------------------------

  group('parseMacosQuarantineDetail', () {
    test('extracts quarantine value', () {
      const output = 'com.apple.quarantine: 0001;5f3b1234;Safari;ABC123\n';
      final detail = parseMacosQuarantineDetail(output);
      expect(detail, isNotNull);
      expect(detail, contains('0001'));
    });

    test('returns null when quarantine xattr is absent', () {
      expect(
        parseMacosQuarantineDetail('com.apple.metadata:kMDItemFSCreationDate'),
        isNull,
      );
    });

    test('returns null for null input', () {
      expect(parseMacosQuarantineDetail(null), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // parseWindowsThreat
  // -------------------------------------------------------------------------

  group('parseWindowsThreat', () {
    test('detects threat when binary path appears in output', () {
      final output = '''
ActionSuccess      : True
ThreatName         : Trojan:Win32/Sabsik.TE.A
ThreatStatusID     : 1
Resources          : {file:_C:\\Users\\user\\AppData\\Roaming\\WhisPaste\\models\\stt\\whisper-server.exe}
''';
      final result = parseWindowsThreat(
        output,
        r'C:\Users\user\AppData\Roaming\WhisPaste\models\stt\whisper-server.exe',
      );
      expect(result.detected, isTrue);
      expect(result.threatName, contains('Trojan'));
    });

    test('returns not detected when path not in output', () {
      const output = 'No threats detected.';
      final result = parseWindowsThreat(output, r'C:\some\whisper-server.exe');
      expect(result.detected, isFalse);
      expect(result.threatName, isNull);
    });

    test('returns not detected for null output', () {
      final result = parseWindowsThreat(null, r'C:\some\path.exe');
      expect(result.detected, isFalse);
    });

    test('returns not detected for empty output', () {
      final result = parseWindowsThreat('', r'C:\some\path.exe');
      expect(result.detected, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // gatherAvQuarantineProbe via seam
  // -------------------------------------------------------------------------

  group('gatherAvQuarantineProbe via seam', () {
    tearDown(() => setAvCommandRunnerForTesting(null));

    test('returns binaryExists=false when binary not on disk', () async {
      // Use a path that does not exist.
      const fakePath = '/tmp/definitely-does-not-exist-whisper-server-test';
      final result = await gatherAvQuarantineProbe(fakePath);
      expect(result.binaryExists, isFalse);
      expect(result.binaryPath, fakePath);
    });
  });
}
