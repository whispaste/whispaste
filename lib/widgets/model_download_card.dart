/// Model download card — shows STT quality tiers with download status,
/// progress, and one-tap download. Designed to be embedded in the Settings page.
///
/// The rendering logic lives in [SttModelSelector]
/// (`lib/features/settings/stt_model_selector.dart`). This file keeps
/// [SttModelManager] as the settings-aware wrapper that supplies
/// [currentModelId] / [benchmarkRtf] from [settingsProvider] and wires the
/// [onModelSelected] callback back to the settings notifier.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_provider.dart';
import '../features/settings/stt_model_selector.dart';
import '../services/hardware_info_service.dart' as hw;

/// Settings-aware wrapper around [SttModelSelector].
///
/// Reads [settingsProvider] and [hw.gpuInfoProvider] so that [SttModelSelector]
/// itself remains free of Drift / settings dependencies and is independently
/// testable.
class SttModelManager extends ConsumerWidget {
  const SttModelManager({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gpuAsync = ref.watch(hw.gpuInfoProvider);
    final gpu = gpuAsync.value;
    final settings = ref.watch(settingsProvider).value;
    final currentModelId = settings?.effectiveModelId;

    return SttModelSelector(
      currentModelId: currentModelId,
      benchmarkRtf: settings?.tierBenchmarkRtf,
      gpu: gpu,
      onModelSelected: (modelId) => ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(sttModel: modelId)),
    );
  }
}
