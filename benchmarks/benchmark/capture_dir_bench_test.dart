/// Micro-benchmark for the capture-folder resolution on the recording start
/// path: cold resolve (`id -u`, `stat`, `chmod` process spawns) against the
/// cached [currentCaptureDir] call that every later recording pays.
///
/// Manual tool, skipped in the default `flutter test` sweep:
///
/// ```sh
/// CAPTURE_BENCH=1 flutter test test/benchmark/capture_dir_bench_test.dart
/// ```
library;

// ignore_for_file: avoid_print — a manual measurement tool; stdout is the
// deliverable.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/capture/capture_dir.dart';

double _percentile(List<int> sortedUs, double q) {
  final index = ((sortedUs.length - 1) * q).round();
  return sortedUs[index] / 1000.0;
}

void main() {
  final enabled = Platform.environment['CAPTURE_BENCH'] == '1';

  test(
    'capture folder: cold resolve vs cached call',
    () async {
      final system = CaptureSystem.current();
      const coldRuns = 15;
      const cachedRuns = 2000;

      final cold = <int>[];
      for (var i = 0; i < coldRuns; i++) {
        final sw = Stopwatch()..start();
        await resolveCaptureDir(system);
        sw.stop();
        cold.add(sw.elapsedMicroseconds);
      }
      cold.sort();

      // Warm the process-wide cache once, then measure the per-recording path.
      await currentCaptureDir();
      final cachedUs = <int>[];
      for (var i = 0; i < cachedRuns; i++) {
        final sw = Stopwatch()..start();
        await currentCaptureDir();
        sw.stop();
        cachedUs.add(sw.elapsedMicroseconds);
      }
      cachedUs.sort();

      print(
        'capture_dir_bench platform=${Platform.operatingSystem} '
        'dir=${await currentCaptureDir()}',
      );
      print(
        'capture_dir_bench cold n=$coldRuns '
        'median=${_percentile(cold, 0.5).toStringAsFixed(2)} ms '
        'p90=${_percentile(cold, 0.9).toStringAsFixed(2)} ms',
      );
      print(
        'capture_dir_bench cached n=$cachedRuns '
        'median=${_percentile(cachedUs, 0.5).toStringAsFixed(4)} ms '
        'p90=${_percentile(cachedUs, 0.9).toStringAsFixed(4)} ms',
      );
    },
    skip: enabled ? false : 'manual benchmark: set CAPTURE_BENCH=1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
