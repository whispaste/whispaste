import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/app_info.dart' as app;
import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/engine_recommendation.dart' show isSoftwareRenderer;
import '../../../services/hardware_info_service.dart' as hw;
import '../../../services/model_download_service.dart';
import '../../../services/stt/benchmark_freshness.dart';
import '../../../services/stt/stt_bundle.dart';
import '../../../widgets/wp_button.dart';
import '../widgets/wp_settings_group.dart';

/// Speech-section row that runs the performance benchmark and reports it in
/// place: progress while running (with cancel), the last result afterwards
/// (per-tier speed, hardware path, timestamp, recommendation with a switch),
/// and an inline error with retry. The results are persisted in settings, so
/// the last measurement is still shown when the page is opened later.
class SttBenchmarkRow extends ConsumerWidget {
  const SttBenchmarkRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final run = ref.watch(sttBenchmarkRunProvider);
    final settings = ref.watch(settingsProvider).value;
    final rtfMap = settings?.benchmark.tierBenchmarkRtf;
    final hasResult = rtfMap != null && rtfMap.isNotEmpty;
    final gpu = ref.watch(hw.gpuInfoProvider).value;
    final freshRtf = settings == null || gpu == null
        ? null
        : benchmarkRtfForMachine(
            benchmark: settings.benchmark,
            gpu: gpu,
            appVersion: app.appVersion,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WpSettingsRow(
          rowId: 'speech-benchmark',
          title: hasResult
              ? l10n.qualityTierBenchmarkReRun
              : l10n.qualityTierBenchmarkRun,
          subtitle: l10n.benchmarkRowSubtitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (run.isRunning)
                Semantics(
                  identifier: 'settings-benchmark-cancel',
                  label: l10n.benchmarkCancel,
                  button: true,
                  child: IconButton(
                    key: const ValueKey('settings-benchmark-cancel'),
                    icon: const Icon(LucideIcons.x, size: WpIconSize.sm),
                    tooltip: l10n.benchmarkCancel,
                    onPressed: ref
                        .read(sttBenchmarkRunProvider.notifier)
                        .requestCancel,
                  ),
                ),
              Semantics(
                identifier: 'settings-benchmark-run',
                label: l10n.qualityTierBenchmarkReRun,
                button: true,
                enabled: !run.isRunning,
                child: IconButton(
                  key: const ValueKey('settings-benchmark-run'),
                  icon: const Icon(LucideIcons.refreshCw, size: WpIconSize.sm),
                  tooltip: l10n.qualityTierBenchmarkReRun,
                  onPressed: run.isRunning
                      ? null
                      : () => ref
                            .read(localSttBundleProvider.notifier)
                            .runBenchmark(),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: WpSpacing.sm),
          child: _BenchmarkDetail(
            l10n: l10n,
            run: run,
            settings: settings,
            freshRtf: freshRtf,
            stale: hasResult && gpu != null && freshRtf == null,
          ),
        ),
      ],
    );
  }
}

class _BenchmarkDetail extends ConsumerWidget {
  const _BenchmarkDetail({
    required this.l10n,
    required this.run,
    required this.settings,
    required this.freshRtf,
    required this.stale,
  });

  final L10n l10n;
  final BenchmarkRunState run;
  final AppSettings? settings;

  /// Results that describe this machine; the recommendation uses only these.
  final Map<QualityTier, double>? freshRtf;

  /// Results exist but were measured on another machine, build or path.
  final bool stale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (run.isRunning) {
      final tierLabel = run.tier == null ? '' : _tierLabel(l10n, run.tier!);
      final step = run.done + 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.benchmarkRunningStep(step, run.total, tierLabel),
              key: const ValueKey('settings-benchmark-progress-text'),
              style: _captionStyle(),
            ),
          ),
          const SizedBox(height: WpSpacing.xxs),
          LinearProgressIndicator(
            key: const ValueKey('settings-benchmark-progress'),
            value: run.total == 0 ? null : run.done / run.total,
          ),
        ],
      );
    }

    if (run.phase == BenchmarkRunPhase.failed) {
      final message = switch (run.error) {
        BenchmarkRunError.busy => l10n.benchmarkErrorBusy,
        BenchmarkRunError.noModel => l10n.benchmarkErrorNoModel,
        _ => l10n.benchmarkErrorFailed,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            key: const ValueKey('settings-benchmark-error'),
            style: TextStyle(
              fontSize: WpTypography.caption,
              color: WpColors.error,
            ),
          ),
          const SizedBox(height: WpSpacing.xxs),
          WpButton(
            key: const ValueKey('settings-benchmark-retry'),
            label: l10n.benchmarkRetry,
            variant: WpButtonVariant.ghost,
            icon: LucideIcons.refreshCw,
            onPressed: () =>
                ref.read(localSttBundleProvider.notifier).runBenchmark(),
          ),
        ],
      );
    }

    final rtfMap = settings?.benchmark.tierBenchmarkRtf;
    final measuredAt = settings?.benchmark.benchmarkTimestamp;
    final gpu = ref.watch(hw.gpuInfoProvider).value;
    final hasResult = rtfMap != null && rtfMap.isNotEmpty && measuredAt != null;
    final locale = Localizations.localeOf(context).toString();

    final parakeet = settings?.onDeviceEngine == OnDeviceEngine.parakeet;
    final parakeetNote = parakeet
        ? Text(
            l10n.benchmarkParakeetNotMeasured,
            key: const ValueKey('settings-benchmark-parakeet'),
            style: _captionStyle(),
          )
        : null;

    if (!hasResult) {
      final noResult = Text(
        l10n.benchmarkNoResult,
        key: const ValueKey('settings-benchmark-result'),
        style: _captionStyle(),
      );
      if (parakeetNote == null) return noResult;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          parakeetNote,
          const SizedBox(height: WpSpacing.xxs),
          noResult,
        ],
      );
    }

    final lines = <Widget>[
      ?parakeetNote,
      if (stale)
        Text(
          l10n.benchmarkStaleNotice,
          key: const ValueKey('settings-benchmark-stale'),
          style: _captionStyle(),
        ),
      if (run.phase == BenchmarkRunPhase.done)
        Text(
          run.cancelled
              ? l10n.benchmarkCancelled
              : l10n.benchmarkDone(rtfMap.length),
          key: const ValueKey('settings-benchmark-done'),
          style: _captionStyle(),
        ),
      Text(
        l10n.benchmarkLastMeasured(
          DateFormat.yMd(locale).add_Hm().format(measuredAt.toLocal()),
        ),
        key: const ValueKey('settings-benchmark-result'),
        style: _captionStyle(),
      ),
      Text(
        l10n.benchmarkBackendLine(
          benchmarkBackendLabel(
            l10n,
            settings?.benchmark.benchmarkBackend,
            gpuName: gpu?.name,
          ),
        ),
        key: const ValueKey('settings-benchmark-backend'),
        style: _captionStyle(),
      ),
      for (final tier in QualityTier.values)
        if (rtfMap[tier] != null)
          Text(
            l10n.benchmarkTierResult(
              _tierLabel(l10n, tier),
              NumberFormat.decimalPatternDigits(
                locale: locale,
                decimalDigits: 2,
              ).format(rtfMap[tier]),
            ),
            key: ValueKey('settings-benchmark-tier-${tier.name}'),
            style: _captionStyle(),
          ),
      ..._recommendation(context, ref, freshRtf ?? const {}),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  /// Names the measured-best tier and offers the switch when it differs from
  /// the active one and is installed.
  List<Widget> _recommendation(
    BuildContext context,
    WidgetRef ref,
    Map<QualityTier, double> rtfMap,
  ) {
    final recommended = recommendTierFromBenchmark(rtfMap);
    final currentModel = settings?.effectiveModelId;
    final currentTier = currentModel == null
        ? null
        : tierForModel(currentModel);
    if (recommended == null || recommended == currentTier) return const [];

    final modelId = bestModelForTier(recommended).id;
    final installed = ref
        .watch(modelDownloadProvider)
        .downloadedModels
        .contains(modelId);
    if (!installed) return const [];

    final label = _tierLabel(l10n, recommended);
    return [
      const SizedBox(height: WpSpacing.xxs),
      Text(
        l10n.benchmarkRecommendation(label),
        key: const ValueKey('settings-benchmark-recommendation'),
        style: _captionStyle(),
      ),
      const SizedBox(height: WpSpacing.xxs),
      WpButton(
        key: const ValueKey('settings-benchmark-switch'),
        label: l10n.benchmarkSwitchTo(label),
        variant: WpButtonVariant.secondary,
        onPressed: () => ref
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(sttModel: modelId)),
      ),
    ];
  }

  TextStyle _captionStyle() =>
      TextStyle(fontSize: WpTypography.caption, color: WpColors.textMuted);
}

String _tierLabel(L10n l10n, QualityTier tier) => switch (tier) {
  QualityTier.compact => l10n.qualityTierCompactLabel,
  QualityTier.balanced => l10n.qualityTierBalancedLabel,
  QualityTier.premium => l10n.qualityTierPremiumLabel,
};

/// The compute path a benchmark ran on. Vulkan on a software renderer
/// (llvmpipe and the like) is the processor, never a graphics card, or the
/// user would believe the GPU is in use (UIA-XP-7-03).
@visibleForTesting
String benchmarkBackendLabel(
  L10n l10n,
  String? backend, {
  required String? gpuName,
}) => switch (backend) {
  'metal' => l10n.benchmarkBackendGpu('Metal'),
  'cuda' => l10n.benchmarkBackendGpu('CUDA'),
  'vulkan' when gpuName != null && isSoftwareRenderer(gpuName) =>
    l10n.benchmarkBackendSoftwareVulkan(_shortDeviceName(gpuName)),
  'vulkan' => l10n.benchmarkBackendGpu('Vulkan'),
  _ => l10n.benchmarkBackendCpu,
};

/// "llvmpipe (LLVM 15.0.7, 256 bits)" reads as "llvmpipe".
String _shortDeviceName(String name) => name.split(' (').first.trim();
