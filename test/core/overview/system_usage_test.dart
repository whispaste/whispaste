import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/overview/system_usage.dart';

void main() {
  group('cpuTicksFromProcStat', () {
    test('counts idle and I/O wait as idle, guest time is not added twice', () {
      final ticks = cpuTicksFromProcStat(
        'cpu  100 10 50 800 20 5 5 0 0 0\ncpu0 1 1 1 1 1 1 1 1\n',
      );
      expect(ticks, isNotNull);
      expect(ticks!.total, 990);
      expect(ticks.busy, 170);
    });

    test('missing or short cpu line gives no reading', () {
      expect(cpuTicksFromProcStat('intr 1 2 3\n'), isNull);
      expect(cpuTicksFromProcStat('cpu 1 2 3\n'), isNull);
      expect(cpuTicksFromProcStat(''), isNull);
    });
  });

  group('cpuTicksFromWindows', () {
    test('kernel time includes idle, so the total is kernel plus user', () {
      final ticks = cpuTicksFromWindows(idle: 300, kernel: 500, user: 200);
      expect(ticks!.total, 700);
      expect(ticks.busy, 400);
    });

    test('idle larger than the total is rejected', () {
      expect(cpuTicksFromWindows(idle: 900, kernel: 500, user: 200), isNull);
      expect(cpuTicksFromWindows(idle: -1, kernel: 5, user: 5), isNull);
    });
  });

  group('cpuTicksFromMacTotals', () {
    test('busy is user, system and nice; idle is the rest', () {
      final ticks = cpuTicksFromMacTotals(
        user: 10,
        system: 20,
        idle: 60,
        nice: 10,
      );
      expect(ticks!.total, 100);
      expect(ticks.busy, 40);
    });

    test('no counted time gives no reading', () {
      expect(
        cpuTicksFromMacTotals(user: 0, system: 0, idle: 0, nice: 0),
        isNull,
      );
    });
  });

  group('cpuPercentBetween', () {
    test('share of busy time between two readings', () {
      const earlier = CpuTicks(busy: 10, total: 100);
      const later = CpuTicks(busy: 60, total: 200);
      expect(cpuPercentBetween(earlier, later), 50);
    });

    test('no elapsed time gives no percentage yet', () {
      const reading = CpuTicks(busy: 10, total: 100);
      expect(cpuPercentBetween(reading, reading), isNull);
    });

    test('clamped to 0 and 100 when the counters step oddly', () {
      const earlier = CpuTicks(busy: 10, total: 100);
      expect(
        cpuPercentBetween(earlier, const CpuTicks(busy: 300, total: 200)),
        100,
      );
      expect(
        cpuPercentBetween(earlier, const CpuTicks(busy: 5, total: 200)),
        0,
      );
    });
  });

  group('ramUsedPercent', () {
    test('whole percent of total memory in use', () {
      expect(ramUsedPercent(totalMB: 16000, availableMB: 4000), 75);
    });

    test('unknown total gives no percentage', () {
      expect(ramUsedPercent(totalMB: 0, availableMB: 0), isNull);
    });

    test('available above total never shows negative use', () {
      expect(ramUsedPercent(totalMB: 1000, availableMB: 1200), 0);
    });
  });

  group('warnings', () {
    test('low memory: free share below the threshold, not at it', () {
      expect(
        isRamLow(totalMB: 1000, availableMB: 99, lowFraction: 0.10),
        isTrue,
      );
      expect(
        isRamLow(totalMB: 1000, availableMB: 100, lowFraction: 0.10),
        isFalse,
      );
      expect(isRamLow(totalMB: 0, availableMB: 0, lowFraction: 0.10), isFalse);
    });

    test('nearly full disk: under 2 GiB free, unknown never warns', () {
      const twoGiB = 2 * 1024 * 1024 * 1024;
      expect(isDiskLow(twoGiB - 1), isTrue);
      expect(isDiskLow(twoGiB), isFalse);
      expect(isDiskLow(null), isFalse);
    });
  });
}
