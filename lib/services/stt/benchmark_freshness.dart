/// Which stored benchmark results still describe this machine.
///
/// A result is only as good as the setup that produced it. A GPU swap, another
/// compute path (Metal, CUDA, Vulkan, CPU) or a new app build changes the
/// numbers, so a result from any other setup is stale: it must neither steer
/// the recommendation nor count as measured.
library;

import '../../core/config/quality_tier.dart';
import '../../core/config/settings_sections.dart';
import '../hardware_info_service.dart' as hw;

/// The machine part of a benchmark key: GPU vendor and reported VRAM, or
/// `cpu` without a GPU.
String benchmarkHardwareKey(hw.GpuInfo gpu) => gpu.vendor == hw.GpuVendor.none
    ? 'cpu'
    : '${gpu.vendor.name}_${gpu.vramMB ?? 0}';

/// Stored as [BenchmarkSettings.benchmarkHardwareId]: the machine and the app
/// build that measured it. The compute path is kept apart in
/// [BenchmarkSettings.benchmarkBackend].
String benchmarkMachineKey({
  required String hardwareKey,
  required String appVersion,
}) => '$hardwareKey|$appVersion';

/// The measured RTFs that still describe this machine, or null when there are
/// none. [backend] is checked only when known (the engine has loaded): the
/// settings screen does not know it before a model runs.
Map<QualityTier, double>? benchmarkRtfForMachine({
  required BenchmarkSettings benchmark,
  required hw.GpuInfo gpu,
  String? backend,
  required String appVersion,
}) {
  final rtf = benchmark.tierBenchmarkRtf;
  if (rtf == null || rtf.isEmpty) return null;
  final expected = benchmarkMachineKey(
    hardwareKey: benchmarkHardwareKey(gpu),
    appVersion: appVersion,
  );
  if (benchmark.benchmarkHardwareId != expected) return null;
  if (backend != null && benchmark.benchmarkBackend != backend) return null;
  return rtf;
}
