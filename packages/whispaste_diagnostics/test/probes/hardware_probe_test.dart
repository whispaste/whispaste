/// Unit tests for hardware_probe.dart (AC1).
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/probes/gpu_info.dart'
    show GpuInfo, GpuVendor;
import 'package:whispaste_diagnostics/src/probes/hardware_probe.dart';

void main() {
  // -------------------------------------------------------------------------
  // Parsing helpers
  // -------------------------------------------------------------------------

  group('parseHwMemsizeMb', () {
    test('converts bytes to MB', () {
      expect(parseHwMemsizeMb('8589934592\n'), 8192);
    });

    test('returns null for empty string', () {
      expect(parseHwMemsizeMb(''), isNull);
    });

    test('returns null for non-numeric', () {
      expect(parseHwMemsizeMb('not-a-number'), isNull);
    });
  });

  group('parseVmStatFreeMb', () {
    test('parses free + speculative pages', () {
      const output = '''
Mach Virtual Memory Statistics: (page size of 4096 bytes)
Pages free:                               12345.
Pages speculative:                         4321.
Pages inactive:                          123456.
''';
      // (12345 + 4321) * 4096 / 1024 / 1024 = 64 MB (approx)
      final result = parseVmStatFreeMb(output);
      expect(result, isNotNull);
      expect(result!, greaterThan(0));
    });

    test('returns null when no free pages found', () {
      expect(parseVmStatFreeMb('nothing here'), isNull);
    });
  });

  group('parseSysctlCpuBrand', () {
    test('trims and returns brand string', () {
      expect(parseSysctlCpuBrand('Apple M2 Pro\n'), 'Apple M2 Pro');
    });

    test('returns null for empty output', () {
      expect(parseSysctlCpuBrand('  '), isNull);
    });
  });

  group('parseSysctlLogicalCpu', () {
    test('parses integer', () {
      expect(parseSysctlLogicalCpu('8\n'), 8);
    });

    test('returns null for non-integer', () {
      expect(parseSysctlLogicalCpu('abc'), isNull);
    });
  });

  group('parseWmicFreeMemoryMb', () {
    test('parses FreePhysicalMemory from wmic output', () {
      const output = '\r\nFreePhysicalMemory=4194304\r\n\r\n';
      expect(parseWmicFreeMemoryMb(output), 4096);
    });

    test('returns null when key missing', () {
      expect(parseWmicFreeMemoryMb('something else'), isNull);
    });
  });

  group('parseWmicCpuInfo', () {
    test('parses name and core count', () {
      const output = '''

Name=Intel(R) Core(TM) i9-12900K
NumberOfLogicalProcessors=24

''';
      final result = parseWmicCpuInfo(output);
      expect(result.model, 'Intel(R) Core(TM) i9-12900K');
      expect(result.cores, 24);
    });

    test('returns null fields when absent', () {
      final result = parseWmicCpuInfo('nothing here');
      expect(result.model, isNull);
      expect(result.cores, isNull);
    });
  });

  group('parseLinuxMemInfo', () {
    test('parses MemTotal and MemAvailable', () {
      const content = '''
MemTotal:       16384000 kB
MemFree:          200000 kB
MemAvailable:    8192000 kB
Buffers:          100000 kB
''';
      final result = parseLinuxMemInfo(content);
      expect(result.totalMb, 16000); // 16384000 / 1024 = 16000
      expect(result.freeMb, 8000); // 8192000 / 1024 = 8000
    });

    test('returns null fields for empty input', () {
      final result = parseLinuxMemInfo('');
      expect(result.totalMb, isNull);
      expect(result.freeMb, isNull);
    });
  });

  group('parseDfFreeMb', () {
    test('parses available KB and converts to MB', () {
      // df -k output: Filesystem 1K-blocks Used Available Capacity Mounted
      const output = '''
Filesystem     1K-blocks     Used Available Use% Mounted on
/dev/sda1      102400000 20480000  81920000  20% /
''';
      // 81920000 kB / 1024 = 80000 MB
      expect(parseDfFreeMb(output, '/home/user'), 80000);
    });

    test('returns null when path does not match any mount', () {
      const output = '''
Filesystem     1K-blocks     Used Available Use% Mounted on
/dev/sda1      102400000 20480000  81920000  20% /other
''';
      expect(parseDfFreeMb(output, '/not/matching'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Full parse via seam
  // -------------------------------------------------------------------------

  group('parseHardwareProbeResult (macOS)', () {
    test('returns RAM total and free correctly', () {
      final inputs = HardwareProbeInputs(
        ramTotalRaw: '8589934592\n', // 8192 MB
        ramFreeRaw: '''
Pages free:                               12345.
Pages speculative:                         4321.
''',
        cpuModelRaw: 'Apple M2 Pro\n',
        cpuCoresRaw: '10\n',
        gpuInfo: const GpuInfo(
          vendor: GpuVendor.apple,
          name: 'Apple M2 Pro',
          vramMB: 8192,
        ),
        dfRaw: '''
Filesystem     1K-blocks    Used Available Use% Mounted on
/dev/disk1s1  204800000 40960000 163840000  20% /
''',
        dfPath: '/Users/test',
      );

      final result = parseHardwareProbeResult(inputs, platform: 'macos');

      expect(result.ramTotalMb, 8192);
      expect(result.ramFreeMb, isNotNull);
      expect(result.cpuModel, 'Apple M2 Pro');
      expect(result.cpuCores, 10);
      expect(result.gpuName, 'Apple M2 Pro');
      expect(result.gpuVramMb, 8192);
      expect(result.diskFreeMb, isNotNull);
    });

    test('marks RAM as scarce when below threshold (4 GB)', () {
      // 4 GB = 4096 MB, well below 7500
      final inputs = HardwareProbeInputs(
        ramTotalRaw: '4294967296\n', // 4096 MB
        gpuInfo: null,
      );
      final result = parseHardwareProbeResult(inputs, platform: 'macos');
      expect(result.ramScarce, isTrue);
    });

    test('does not mark RAM scarce when above threshold (8 GB)', () {
      final inputs = HardwareProbeInputs(
        ramTotalRaw: '8589934592\n', // 8192 MB — above 7500 threshold
        gpuInfo: null,
      );
      final result = parseHardwareProbeResult(inputs, platform: 'macos');
      expect(result.ramScarce, isFalse);
    });

    test('does not mark RAM scarce at exactly 7500 MB', () {
      // 7500 MB in bytes = 7500 * 1024 * 1024 = 7864320000
      final inputs = HardwareProbeInputs(
        ramTotalRaw: '7864320000\n', // exactly 7500 MB
        gpuInfo: null,
      );
      final result = parseHardwareProbeResult(inputs, platform: 'macos');
      // kRamCheckThresholdMB = 7500; 7500 < 7500 is false
      expect(result.ramScarce, isFalse);
    });

    test('marks RAM scarce just below threshold (7499 MB)', () {
      // 7499 * 1024 * 1024 = 7863296000 bytes
      final inputs = HardwareProbeInputs(
        ramTotalRaw: '7863296000\n', // 7499 MB
        gpuInfo: null,
      );
      final result = parseHardwareProbeResult(inputs, platform: 'macos');
      expect(result.ramScarce, isTrue);
    });
  });

  group('parseHardwareProbeResult (windows)', () {
    test('parses wmic total and free RAM', () {
      final inputs = HardwareProbeInputs(
        ramTotalRaw: 'TotalVisibleMemorySize=16384000\r\n',
        ramFreeRaw: 'FreePhysicalMemory=8192000\r\n',
        cpuModelRaw:
            'Name=Intel(R) Core(TM) i7-12700K\r\nNumberOfLogicalProcessors=20\r\n',
        gpuInfo: const GpuInfo(
          vendor: GpuVendor.nvidia,
          name: 'NVIDIA RTX 3080',
          vramMB: 10240,
          cudaAvailable: true,
          vulkanAvailable: true,
        ),
      );

      final result = parseHardwareProbeResult(inputs, platform: 'windows');

      expect(result.ramTotalMb, greaterThan(0));
      expect(result.ramFreeMb, greaterThan(0));
      expect(result.cpuModel, 'Intel(R) Core(TM) i7-12700K');
      expect(result.cpuCores, 20);
      expect(result.gpuName, 'NVIDIA RTX 3080');
      expect(result.gpuVramMb, 10240);
    });
  });

  group('parseHardwareProbeResult (linux)', () {
    test('parses /proc/meminfo and /proc/cpuinfo', () {
      final inputs = HardwareProbeInputs(
        ramTotalRaw: '''
MemTotal:       16000000 kB
MemFree:          500000 kB
MemAvailable:    8000000 kB
''',
        cpuModelRaw: '''
processor\t: 0
model name\t: Intel(R) Core(TM) i5-9400 CPU @ 2.90GHz
cpu MHz\t\t: 2900.000
''',
        cpuCoresRaw: '6',
        gpuInfo: const GpuInfo(vendor: GpuVendor.none, name: 'No GPU detected'),
      );

      final result = parseHardwareProbeResult(inputs, platform: 'linux');

      expect(result.ramTotalMb, isNotNull);
      expect(result.ramFreeMb, isNotNull);
      expect(result.cpuModel, contains('i5-9400'));
      expect(result.cpuCores, 6);
    });
  });

  group('parseHardwareProbeResult (unknown platform)', () {
    test('returns all null fields', () {
      final inputs = HardwareProbeInputs(
        ramTotalRaw: 'some data',
        gpuInfo: null,
      );
      final result = parseHardwareProbeResult(inputs, platform: 'unknown');
      expect(result.ramTotalMb, isNull);
      expect(result.cpuModel, isNull);
    });
  });
}
