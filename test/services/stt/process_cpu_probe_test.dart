import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/process_cpu_probe.dart';

void main() {
  group('processCpuPercentBetween', () {
    test('zero wall-clock delta returns 0 rather than dividing by zero', () {
      final t = DateTime(2026);
      final a = ProcessCpuSample(cpuTime: Duration.zero, wallTime: t);
      final b = ProcessCpuSample(
        cpuTime: const Duration(seconds: 1),
        wallTime: t,
      );
      expect(processCpuPercentBetween(a, b), 0);
    });

    test(
      'one full core-second of CPU time over a one-second window is ~100%',
      () {
        final t = DateTime(2026);
        final a = ProcessCpuSample(cpuTime: Duration.zero, wallTime: t);
        final b = ProcessCpuSample(
          cpuTime: const Duration(seconds: 1),
          wallTime: t.add(const Duration(seconds: 1)),
        );
        expect(processCpuPercentBetween(a, b), closeTo(100, 0.01));
      },
    );

    test('never returns a negative percentage for a clock-skew blip', () {
      final t = DateTime(2026);
      // cpuTime went "backwards" relative to a — should clamp to 0, not -50.
      final a = ProcessCpuSample(
        cpuTime: const Duration(seconds: 2),
        wallTime: t,
      );
      final b = ProcessCpuSample(
        cpuTime: const Duration(seconds: 1),
        wallTime: t.add(const Duration(seconds: 1)),
      );
      expect(processCpuPercentBetween(a, b), 0);
    });
  });

  group('ProcessCpuProbe (real FFI call on the host platform)', () {
    test('sample() returns a non-negative, monotonically non-decreasing '
        'cumulative CPU time', () {
      const probe = ProcessCpuProbe();
      final first = probe.sample();
      expect(first.cpuTime, greaterThanOrEqualTo(Duration.zero));

      // Burn some real CPU so the second sample can't just tie the first.
      var acc = 0;
      for (var i = 0; i < 20000000; i++) {
        acc += i;
      }
      expect(acc, isNot(0)); // keep the loop from being optimised away

      final second = probe.sample();
      expect(second.cpuTime, greaterThanOrEqualTo(first.cpuTime));
    });
  });
}
