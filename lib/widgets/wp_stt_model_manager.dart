/// Model download card — shows STT quality tiers with download status,
/// progress, and one-tap download. Designed to be embedded in the Settings page.
///
/// The rendering logic lives in [SttModelSelector]
/// (`lib/features/settings/stt_model_selector.dart`). This file keeps
/// [WpSttModelManager] as the settings-aware wrapper that supplies
/// [currentModelId] / [benchmarkRtf] from [settingsProvider] and wires the
/// [onModelSelected] callback back to the settings notifier.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../features/settings/stt_model_selector.dart';
import '../services/hardware_info_service.dart' as hw;
import '../services/model_download_service.dart';
import 'toast.dart';

/// Settings-aware wrapper around [SttModelSelector].
///
/// Reads [settingsProvider] and [hw.gpuInfoProvider] so that [SttModelSelector]
/// itself remains free of Drift / settings dependencies and is independently
/// testable.
class WpSttModelManager extends ConsumerWidget {
  const WpSttModelManager({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The moment a download finishes. Ticket 14 took the green off the tier
    // row — it was painting an on-disk *fact* in the colour reserved for a
    // just-finished action (the Earned-Green Rule, `lib/DESIGN.md`) — and the
    // completion itself had never been announced anywhere: the row simply
    // turned green at some point while the user was elsewhere on the page.
    // Reporting it as a toast is what the rule asks for and is also the only
    // way the user learns *when* the model became usable. Edge-triggered, so
    // a rebuild in the `done` phase cannot re-fire it. Onboarding does the
    // same thing at `model_step.dart:258`.
    ref.listen<ModelDownloadState>(modelDownloadProvider, (previous, next) {
      if (next.phase != DownloadPhase.done) return;
      if (previous?.phase == DownloadPhase.done) return;
      if (!context.mounted) return;
      WpToast.show(
        context,
        message: L10n.of(context).modelDownloadComplete,
        type: WpToastType.success,
      );
    });

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
