/// VRAM gate for the GPU backends: a model whose weights do not fit the
/// detected GPU memory must not be loaded on the GPU (it would run out of
/// memory or fail mid-load). The check itself lives in the GPU probe package
/// ([checkVramGate]); this file only adapts it to the app's GPU info and
/// exposes the matching settings notice.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart'
    show VramSkipped, checkVramGate;

import '../../../core/config/settings_enums.dart'
    show GpuAcceleration, OnDeviceEngine;
import '../../../core/config/settings_provider.dart';
import '../../hardware_info_service.dart' as hw;

/// True when [modelId] needs more VRAM than [gpu] reports. Fail-open: an
/// unknown model, an unknown VRAM size or no GPU at all never counts as "does
/// not fit", so the existing backend selection stays in charge there.
bool modelExceedsGpuVram({required String modelId, required hw.GpuInfo? gpu}) =>
    checkVramGate(modelSizeKey: modelId, vramBudgetMB: gpu?.vramMB)
        is VramSkipped;

/// The settings notice shown while the selected model is kept off the GPU.
class VramGateNotice {
  const VramGateNotice({required this.requiredMb, required this.vramMb});

  final int requiredMb;
  final int vramMb;
}

/// The notice for the current settings, or null when nothing is gated: only
/// for whisper with GPU acceleration on, a known model size and a known VRAM
/// size that the model does not fit into.
VramGateNotice? vramGateNoticeFor({
  required OnDeviceEngine engine,
  required String gpuAcceleration,
  required String modelId,
  required hw.GpuInfo? gpu,
}) {
  if (engine != OnDeviceEngine.whisper) return null;
  if (gpuAcceleration == GpuAcceleration.disabled.value) return null;
  final requiredMb = hw.sttModelVramMB[modelId];
  final vramMb = gpu?.vramMB;
  if (requiredMb == null || vramMb == null) return null;
  if (!modelExceedsGpuVram(modelId: modelId, gpu: gpu)) return null;
  return VramGateNotice(requiredMb: requiredMb, vramMb: vramMb);
}

/// Watches the settings and the GPU info and yields the current notice.
final sttVramGateNoticeProvider = Provider<VramGateNotice?>((ref) {
  final settings = ref.watch(settingsProvider).value;
  if (settings == null) return null;
  return vramGateNoticeFor(
    engine: settings.onDeviceEngine,
    gpuAcceleration: settings.behavior.gpuAcceleration,
    modelId: settings.effectiveModelId,
    gpu: ref.watch(hw.gpuInfoProvider).value,
  );
});
