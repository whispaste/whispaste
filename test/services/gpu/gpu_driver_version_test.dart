/// Driver version of the detected GPU, from the Windows PowerShell probe.
///
/// The driver version is a plain version string (e.g. `31.0.15.4601`) and
/// is the only new GPU field sent in the vendor telemetry. It is parsed from
/// the probe's pipe-separated output line.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart';

void main() {
  group('parseWindowsGpuLine', () {
    test('reads name, VRAM and driver version from the four-field line', () {
      final gpu = parseWindowsGpuLine(
        'NVIDIA GeForce RTX 4070|4293918720|8589934592|31.0.15.4601',
      );

      expect(gpu, isNotNull);
      expect(gpu!.name, 'NVIDIA GeForce RTX 4070');
      expect(gpu.vramMB, 8192);
      expect(gpu.driverVersion, '31.0.15.4601');
    });

    test('a line without a driver field keeps the driver version unknown', () {
      final gpu = parseWindowsGpuLine('Intel(R) UHD Graphics|0|0');

      expect(gpu!.driverVersion, isNull);
      expect(gpu.vramMB, isNull);
    });

    test('an empty driver field is treated as unknown, not as a version', () {
      final gpu = parseWindowsGpuLine('AMD Radeon|0|0|  ');

      expect(gpu!.driverVersion, isNull);
    });

    test('a blank or nameless line yields nothing', () {
      expect(parseWindowsGpuLine(''), isNull);
      expect(parseWindowsGpuLine('|0|0|31.0'), isNull);
    });
  });
}
