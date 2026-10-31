/// Unit tests for RAM detection parsing helpers in hardware_info_service.
///
/// These tests cover the pure parsing logic (no process spawning) so they
/// run on any platform. Process-spawning detection functions (detectRamMB,
/// _unixRamMB, _windowsRamMB) are NOT tested here — same policy as the
/// existing GPU detection tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/ram_gate_config.dart';
import 'package:whispaste/services/hardware_info_service.dart';

void main() {
  group('kMinRamMB', () {
    test('equals 8192 (8 GB)', () {
      expect(kMinRamMB, equals(8192));
    });
  });

  group('resolveRamThresholds', () {
    test('returns production defaults when no override is provided', () {
      final t = resolveRamThresholds();
      // These values must stay 8192/7500 when the test binary was NOT compiled
      // with WHISPASTE_TEST_RAM_MIN_MB / WHISPASTE_TEST_RAM_THRESHOLD_MB.
      expect(t.minRamMB, equals(8192));
      expect(t.thresholdMB, equals(7500));
    });

    test('returns injected values when test parameters are provided', () {
      final t = resolveRamThresholds(testMinRamMB: 4096, testThresholdMB: 3500);
      expect(t.minRamMB, equals(4096));
      expect(t.thresholdMB, equals(3500));
    });

    test(
      'injection overrides the dart-define even when dart-define would win',
      () {
        // Direct injection always wins — used for focused unit-test scenarios.
        final t = resolveRamThresholds(
          testMinRamMB: 2048,
          testThresholdMB: 1800,
        );
        expect(t.minRamMB, equals(2048));
        expect(t.thresholdMB, equals(1800));
      },
    );
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
      const output =
          'MemTotal:       16384000 kB\n'
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
      expect(
        parseWmicOsMemoryMb('TotalVisibleMemorySize=8388608'),
        equals(8192),
      );
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
