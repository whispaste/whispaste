/// Unit tests for RAM detection parsing helpers in hardware_info_service.
///
/// These tests cover the pure parsing logic (no process spawning) so they
/// run on any platform. Process-spawning detection functions (detectRamMB,
/// _unixRamMB, _windowsRamMB) are NOT tested here — same policy as the
/// existing GPU detection tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/hardware_info_service.dart';

void main() {
  group('kMinRamMB', () {
    test('equals 8192 (8 GB)', () {
      expect(kMinRamMB, equals(8192));
    });
  });

  group('parseSysctlMemsizeMb', () {
    test('parses 16 GB correctly', () {
      // 17179869184 bytes = 16384 MB
      expect(parseSysctlMemsizeMb('17179869184'), equals(16384));
    });

    test('parses 8 GB correctly', () {
      expect(parseSysctlMemsizeMb('8589934592'), equals(8192));
    });

    test('parses output with trailing newline', () {
      expect(parseSysctlMemsizeMb('17179869184\n'), equals(16384));
    });

    test('returns null for empty string', () {
      expect(parseSysctlMemsizeMb(''), isNull);
    });

    test('returns null for non-numeric output', () {
      expect(parseSysctlMemsizeMb('error: unknown oid'), isNull);
    });

    test('returns null for zero', () {
      expect(parseSysctlMemsizeMb('0'), isNull);
    });

    test('returns null for negative value', () {
      expect(parseSysctlMemsizeMb('-1'), isNull);
    });
  });

  group('parseLinuxMemTotalMb', () {
    test('parses typical /proc/meminfo output', () {
      const output = 'MemTotal:       16384000 kB\n'
          'MemFree:         1024000 kB\n';
      expect(parseLinuxMemTotalMb(output), equals(16000));
    });

    test('parses minimal single-line output', () {
      expect(parseLinuxMemTotalMb('MemTotal: 8388608 kB'), equals(8192));
    });

    test('parses output with variable whitespace', () {
      expect(parseLinuxMemTotalMb('MemTotal:    4194304 kB'), equals(4096));
    });

    test('returns null when MemTotal line is missing', () {
      expect(parseLinuxMemTotalMb('MemFree: 512000 kB\n'), isNull);
    });

    test('returns null for empty string', () {
      expect(parseLinuxMemTotalMb(''), isNull);
    });

    test('returns null when value is zero', () {
      expect(parseLinuxMemTotalMb('MemTotal: 0 kB'), isNull);
    });
  });

  group('parseWmicOsMemoryMb', () {
    test('parses typical wmic /Value output', () {
      const output = '\r\n\r\nTotalVisibleMemorySize=16777216\r\n\r\n';
      expect(parseWmicOsMemoryMb(output), equals(16384));
    });

    test('parses minimal output', () {
      expect(parseWmicOsMemoryMb('TotalVisibleMemorySize=8388608'), equals(8192));
    });

    test('returns null when key is absent', () {
      expect(parseWmicOsMemoryMb('SomeOtherKey=12345'), isNull);
    });

    test('returns null for empty string', () {
      expect(parseWmicOsMemoryMb(''), isNull);
    });

    test('returns null when value is zero', () {
      expect(parseWmicOsMemoryMb('TotalVisibleMemorySize=0'), isNull);
    });
  });
}
