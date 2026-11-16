/// A stored benchmark result counts only for the machine, build and compute
/// path that produced it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/quality_tier.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/stt/benchmark_freshness.dart';

const _nvidia = hw.GpuInfo(
  vendor: hw.GpuVendor.nvidia,
  name: 'RTX',
  vramMB: 8192,
);

BenchmarkSettings _stored({
  String hardwareKey = 'nvidia_8192',
  String version = '1.2.3',
  String backend = 'cuda',
}) => BenchmarkSettings(
  tierBenchmarkRtf: const {QualityTier.balanced: 0.4},
  benchmarkHardwareId: benchmarkMachineKey(
    hardwareKey: hardwareKey,
    appVersion: version,
  ),
  benchmarkBackend: backend,
  benchmarkTimestamp: DateTime(2026, 10, 19),
);

void main() {
  test('the hardware key is the vendor and VRAM, or cpu without a GPU', () {
    expect(benchmarkHardwareKey(_nvidia), 'nvidia_8192');
    expect(
      benchmarkHardwareKey(
        const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
      ),
      'cpu',
    );
  });

  test('results from this machine, build and path are current', () {
    expect(
      benchmarkRtfForMachine(
        benchmark: _stored(),
        gpu: _nvidia,
        backend: 'cuda',
        appVersion: '1.2.3',
      ),
      const {QualityTier.balanced: 0.4},
    );
  });

  test('a changed app build makes the results stale', () {
    expect(
      benchmarkRtfForMachine(
        benchmark: _stored(),
        gpu: _nvidia,
        appVersion: '1.2.4',
      ),
      isNull,
    );
  });

  test('another GPU makes the results stale', () {
    expect(
      benchmarkRtfForMachine(
        benchmark: _stored(),
        gpu: const hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'RTX',
          vramMB: 4096,
        ),
        appVersion: '1.2.3',
      ),
      isNull,
    );
  });

  test('a different compute path is stale once the engine reports it', () {
    expect(
      benchmarkRtfForMachine(
        benchmark: _stored(),
        gpu: _nvidia,
        backend: 'vulkan',
        appVersion: '1.2.3',
      ),
      isNull,
    );
  });

  test('without a stored result there is nothing to compare', () {
    expect(
      benchmarkRtfForMachine(
        benchmark: const BenchmarkSettings(),
        gpu: _nvidia,
        appVersion: '1.2.3',
      ),
      isNull,
    );
  });
}
