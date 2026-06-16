import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hardware_info_service.dart' as hw;
import '../../../services/model_download_service.dart';
import '../../../widgets/tier_performance_presentation.dart';
import '../../../widgets/wp_accent_button.dart';

/// Widget keys exposed for testing. Kept in one place so tests and production
/// code agree on the contract.
@visibleForTesting
const kModelStepGpuCpuFallbackKey = Key('modelStepGpuCpuFallbackNotice');
@visibleForTesting
const kModelStepNextButtonKey = Key('modelStepNextButton');

/// Onboarding Step 3 — Quality tier selection & download.
///
/// Shows a hardware-recommended tier with one-click download, plus an
/// expandable section to choose a different quality level.
class ModelStep extends ConsumerStatefulWidget {
  const ModelStep({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  ConsumerState<ModelStep> createState() => _ModelStepState();
}

class _ModelStepState extends ConsumerState<ModelStep> {
  QualityTier? _selectedTier;
  QualityTier? _recommendedTier;
  bool _showAlternatives = false;
  bool _gpuDetected = false;
  hw.GpuInfo? _gpu;

  @override
  void initState() {
    super.initState();
    _detectHardware();
  }

  Future<void> _detectHardware() async {
    final gpu = await ref.read(hw.gpuInfoProvider.future);
    if (!mounted) return;
    final rec = recommendTier(gpu.vramMB ?? 0, vendor: gpu.vendor);
    setState(() {
      _gpu = gpu;
      _recommendedTier = rec;
      _selectedTier ??= rec;
      _gpuDetected = true;
    });
  }

  void _startDownload() {
    final tier = _selectedTier ?? QualityTier.balanced;
    final model = bestModelForTier(tier);
    ref.read(modelDownloadProvider.notifier).downloadModel(model.id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final dlState = ref.watch(modelDownloadProvider);

    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final selectedTier =
        _selectedTier ?? _recommendedTier ?? QualityTier.balanced;
    final selectedPerformance = _gpu != null
        ? tierPerformance(selectedTier, _gpu!)
        : TierPerformance.unmeasured;

    final isDownloading =
        dlState.phase == DownloadPhase.downloading ||
        dlState.phase == DownloadPhase.extracting ||
        dlState.phase == DownloadPhase.verifying;
    final isDone =
        dlState.phase == DownloadPhase.done ||
        dlState.downloadedModels.isNotEmpty;
    final isError = dlState.phase == DownloadPhase.error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        Text(
          l10n.onboardingModelTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.onboardingModelSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: textSecondary, height: 1.4),
        ),
        const SizedBox(height: WpSpacing.xl),

        // GPU CPU fallback notice — purely informational, never blocks Next.
        //
        // Renders only when hardware detection returned `GpuVendor.none`,
        // either because no GPU is present or because both Windows probes
        // (wmic + PowerShell) failed/timed out. The user keeps access to
        // every tier and the cloud option below; the message just sets the
        // expectation that CPU inference will be slower.
        if (_gpu?.vendor == hw.GpuVendor.none) ...[
          _GpuCpuFallbackNotice(
            key: kModelStepGpuCpuFallbackKey,
            message: l10n.onboardingModelGpuCpuFallback,
            isDark: isDark,
          ),
          const SizedBox(height: WpSpacing.md),
        ],

        // Tier cards
        if (!_gpuDetected)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: WpSpacing.xl),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          )
        else ...[
          // Recommended tier card (always visible)
          // loam-ignore: a11y-interactive-semantics – semantics provided in _TierCardState.build
          _TierCard(
            tier: selectedTier,
            isRecommended:
                _selectedTier == _recommendedTier || _selectedTier == null,
            isSelected: true,
            performance: selectedPerformance,
            gpu: _gpu,
            isDark: isDark,
            l10n: l10n,
            onTap: null,
          ),

          // Download progress, error, success, or download button
          const SizedBox(height: WpSpacing.md),
          _ModelStepDownloadStatus(
            dlState: dlState,
            isDownloading: isDownloading,
            isError: isError,
            isDone: isDone,
            isDark: isDark,
            accent: accent,
            accentGradient: accentGradient,
            selectedTier: selectedTier,
            l10n: l10n,
            onStartDownload: _startDownload,
          ),

          // Hardware warning
          if (_gpu != null)
            _TierPerformanceWarning(
              tier: selectedTier,
              performance: selectedPerformance,
              isDark: isDark,
              l10n: l10n,
            ),

          // Choose different tier + alternative tier cards
          _ModelStepAlternatives(
            isDownloading: isDownloading,
            isDone: isDone,
            showAlternatives: _showAlternatives,
            selectedTier: _selectedTier,
            recommendedTier: _recommendedTier,
            gpu: _gpu,
            isDark: isDark,
            accent: accent,
            l10n: l10n,
            onToggleAlternatives: () =>
                setState(() => _showAlternatives = !_showAlternatives),
            onSelectTier: (tier) => setState(() {
              _selectedTier = tier;
              _showAlternatives = false;
            }),
          ),
        ],

        const SizedBox(height: WpSpacing.sm),
        Text(
          l10n.onboardingModelChangeLater,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: textMuted),
        ),
        const SizedBox(height: WpSpacing.xxs),

        // Cloud option
        // loam-ignore: a11y-interactive-semantics – semantics provided in _ModelStepCloudOption.build
        _ModelStepCloudOption(
          accent: accent,
          label: l10n.onboardingModelUseCloud,
          onTap: widget.onNext,
        ),
        const SizedBox(height: WpSpacing.lg),

        // Navigation
        Row(
          children: [
            TextButton(
              onPressed: widget.onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(color: textSecondary),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 140,
              // loam-ignore: a11y-interactive-semantics – semantics provided in WpAccentButton.build
              child: WpAccentButton(
                key: kModelStepNextButtonKey,
                label: l10n.onboardingNext,
                gradient: accentGradient,
                onPressed: isDone ? widget.onNext : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Download status — progress / error / success / download button
// ---------------------------------------------------------------------------

class _ModelStepDownloadStatus extends StatelessWidget {
  const _ModelStepDownloadStatus({
    required this.dlState,
    required this.isDownloading,
    required this.isError,
    required this.isDone,
    required this.isDark,
    required this.accent,
    required this.accentGradient,
    required this.selectedTier,
    required this.l10n,
    required this.onStartDownload,
  });

  final ModelDownloadState dlState;
  final bool isDownloading;
  final bool isError;
  final bool isDone;
  final bool isDark;
  final Color accent;
  final LinearGradient accentGradient;
  final QualityTier selectedTier;
  final L10n l10n;
  final VoidCallback onStartDownload;

  @override
  Widget build(BuildContext context) {
    if (isDownloading) {
      return _DownloadProgress(
        phase: dlState.phase,
        progress: dlState.progressPercent / 100.0,
        isDark: isDark,
        accent: accent,
        l10n: l10n,
      );
    }
    if (isError) {
      return _DownloadError(
        message: dlState.errorMessage,
        isDark: isDark,
        l10n: l10n,
        onRetry: onStartDownload,
      );
    }
    if (isDone) {
      final success = isDark ? WpColorsDark.success : WpColorsLight.success;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.circleCheck, size: 18, color: success),
          const SizedBox(width: WpSpacing.xs),
          Text(
            l10n.modelReady,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: success,
            ),
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      // loam-ignore: a11y-interactive-semantics – semantics provided in WpAccentButton.build
      child: WpAccentButton(
        label:
            '${l10n.qualityTierDownloadAndContinue} (${tierSizeLabel(selectedTier)})',
        gradient: accentGradient,
        onPressed: onStartDownload,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tier performance warning — shown below selected tier when GPU data is present
// ---------------------------------------------------------------------------

class _TierPerformanceWarning extends StatelessWidget {
  const _TierPerformanceWarning({
    required this.tier,
    required this.performance,
    required this.isDark,
    required this.l10n,
  });

  final QualityTier tier;
  final TierPerformance performance;
  final bool isDark;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final infoMessage = _tierPerformanceMessage(
      l10n: l10n,
      tier: tier,
      performance: performance,
    );
    if (infoMessage == null) return const SizedBox.shrink();
    final infoColor = TierPerformancePresentation.color(isDark: isDark);
    final infoIcon = TierPerformancePresentation.icon(performance);
    return Padding(
      padding: const EdgeInsets.only(top: WpSpacing.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(WpSpacing.sm),
        decoration: BoxDecoration(
          color: infoColor.withValues(alpha: 0.08),
          borderRadius: WpRadius.borderMd,
          border: Border.all(color: infoColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(infoIcon, size: 14, color: infoColor),
            const SizedBox(width: WpSpacing.sm),
            Expanded(
              child: Text(
                infoMessage,
                style: TextStyle(fontSize: 12, color: infoColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alternatives section — toggle + expandable list of alternative tier cards
// ---------------------------------------------------------------------------

class _ModelStepAlternatives extends StatelessWidget {
  const _ModelStepAlternatives({
    required this.isDownloading,
    required this.isDone,
    required this.showAlternatives,
    required this.selectedTier,
    required this.recommendedTier,
    required this.gpu,
    required this.isDark,
    required this.accent,
    required this.l10n,
    required this.onToggleAlternatives,
    required this.onSelectTier,
  });

  final bool isDownloading;
  final bool isDone;
  final bool showAlternatives;
  final QualityTier? selectedTier;
  final QualityTier? recommendedTier;
  final hw.GpuInfo? gpu;
  final bool isDark;
  final Color accent;
  final L10n l10n;
  final VoidCallback onToggleAlternatives;
  final void Function(QualityTier tier) onSelectTier;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: WpSpacing.md),
        if (!isDownloading && !isDone)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggleAlternatives,
              borderRadius: WpRadius.borderSm,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.sm,
                  vertical: WpSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.qualityTierChooseDifferent,
                      style: TextStyle(fontSize: 13, color: accent),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: showAlternatives ? 0.5 : 0,
                      duration: WpMotion.fast,
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 14,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        AnimatedSize(
          duration: WpMotion.smooth,
          curve: WpMotion.defaultCurve,
          child: showAlternatives && !isDownloading && !isDone
              ? Padding(
                  padding: const EdgeInsets.only(top: WpSpacing.sm),
                  child: Column(
                    children: [
                      for (final tier in QualityTier.values)
                        if (tier != selectedTier)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: WpSpacing.xs,
                            ),
                            // loam-ignore: a11y-interactive-semantics – semantics provided in _TierCardState.build
                            child: _TierCard(
                              tier: tier,
                              isRecommended: tier == recommendedTier,
                              isSelected: false,
                              performance: gpu != null
                                  ? tierPerformance(tier, gpu!)
                                  : TierPerformance.unmeasured,
                              gpu: gpu,
                              isDark: isDark,
                              l10n: l10n,
                              onTap: () => onSelectTier(tier),
                            ),
                          ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cloud option link
// ---------------------------------------------------------------------------

class _ModelStepCloudOption extends StatelessWidget {
  const _ModelStepCloudOption({
    required this.accent,
    required this.label,
    required this.onTap,
  });

  final Color accent;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: WpRadius.borderSm,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: WpSpacing.xs,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: accent,
                decoration: TextDecoration.underline,
                decorationColor: accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _tierPerformanceMessage({
  required L10n l10n,
  required QualityTier tier,
  required TierPerformance performance,
}) => TierPerformancePresentation.message(
  l10n: l10n,
  tier: tier,
  performance: performance,
);

Color _tierInfoColor({required bool isDark}) {
  return TierPerformancePresentation.color(isDark: isDark);
}

// ---------------------------------------------------------------------------
// Tier Card — shows tier name, description, size, recommended badge
// ---------------------------------------------------------------------------

class _TierCard extends StatefulWidget {
  const _TierCard({
    required this.tier,
    required this.isRecommended,
    required this.isSelected,
    required this.performance,
    required this.gpu,
    required this.isDark,
    required this.l10n,
    required this.onTap,
  });

  final QualityTier tier;
  final bool isRecommended;
  final bool isSelected;
  final TierPerformance performance;
  final hw.GpuInfo? gpu;
  final bool isDark;
  final L10n l10n;
  final VoidCallback? onTap;

  @override
  State<_TierCard> createState() => _TierCardState();
}

class _TierCardState extends State<_TierCard> {
  bool _hovered = false;

  String _tierLabel(L10n l10n) => switch (widget.tier) {
    QualityTier.compact => l10n.qualityTierCompactLabel,
    QualityTier.balanced => l10n.qualityTierBalancedLabel,
    QualityTier.premium => l10n.qualityTierPremiumLabel,
  };

  String _tierDesc(L10n l10n) => switch (widget.tier) {
    QualityTier.compact => l10n.qualityTierCompactDesc,
    QualityTier.balanced => l10n.qualityTierBalancedDesc,
    QualityTier.premium => l10n.qualityTierPremiumDesc,
  };

  IconData get _tierIcon => switch (widget.tier) {
    QualityTier.compact => LucideIcons.zap,
    QualityTier.balanced => LucideIcons.scale,
    QualityTier.premium => LucideIcons.crown,
  };

  @override
  Widget build(BuildContext context) {
    final accent = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final infoMessage = _tierPerformanceMessage(
      l10n: widget.l10n,
      tier: widget.tier,
      performance: widget.performance,
    );
    final infoColor = _tierInfoColor(isDark: widget.isDark);
    final infoIcon = TierPerformancePresentation.icon(widget.performance);
    final bool isTappable = widget.onTap != null;
    final borderColor = widget.isSelected
        ? accent
        : _hovered
        ? accent.withValues(alpha: 0.4)
        : widget.isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final surface = widget.isDark
        ? WpColorsDark.surfaceVariant
        : WpColorsLight.surfaceVariant;
    final textPrimary = widget.isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = widget.isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textColor = textPrimary;
    final subtitleColor = textSecondary;
    final iconColor = accent;

    return Semantics(
      button: isTappable,
      label: isTappable ? _tierLabel(widget.l10n) : null,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: isTappable
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: isTappable ? widget.onTap : null,
          child: AnimatedContainer(
            duration: WpMotion.fast,
            curve: WpMotion.defaultCurve,
            padding: const EdgeInsets.all(WpSpacing.md),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? accent.withValues(alpha: 0.08)
                  : _hovered
                  ? accent.withValues(alpha: 0.05)
                  : surface.withValues(alpha: 0.5),
              border: Border.all(
                color: borderColor,
                width: widget.isSelected ? 1.5 : 1,
              ),
              borderRadius: WpRadius.borderMd,
            ),
            child: Row(
              children: [
                Icon(_tierIcon, size: 22, color: iconColor),
                const SizedBox(width: WpSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _tierLabel(widget.l10n),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                          if (widget.isRecommended) ...[
                            const SizedBox(width: WpSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.15),
                                borderRadius: WpRadius.borderFull,
                              ),
                              child: Text(
                                widget.l10n.qualityTierRecommended,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _tierDesc(widget.l10n),
                        style: TextStyle(
                          fontSize: 12,
                          color: subtitleColor,
                          height: 1.3,
                        ),
                      ),
                      if (infoMessage != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(infoIcon, size: 12, color: infoColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                infoMessage,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: infoColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                Text(
                  tierSizeLabel(widget.tier),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: subtitleColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Download progress indicator
// ---------------------------------------------------------------------------

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({
    required this.phase,
    required this.progress,
    required this.isDark,
    required this.accent,
    required this.l10n,
  });

  final DownloadPhase phase;
  final double progress;
  final bool isDark;
  final Color accent;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    final label = switch (phase) {
      DownloadPhase.downloading => '${(progress * 100).round()}%',
      DownloadPhase.extracting => l10n.modelExtracting,
      DownloadPhase.verifying => l10n.modelVerifying,
      _ => '',
    };

    return Column(
      children: [
        ClipRRect(
          borderRadius: WpRadius.borderFull,
          child: LinearProgressIndicator(
            value: phase == DownloadPhase.downloading ? progress : null,
            backgroundColor: accent.withValues(alpha: 0.15),
            color: accent,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(label, style: TextStyle(fontSize: 12, color: textSecondary)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Download error — shows error message + retry button
// ---------------------------------------------------------------------------

class _DownloadError extends StatelessWidget {
  const _DownloadError({
    required this.message,
    required this.isDark,
    required this.l10n,
    required this.onRetry,
  });

  final String? message;
  final bool isDark;
  final L10n l10n;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final errorColor = isDark ? WpColorsDark.error : WpColorsLight.error;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(WpSpacing.md),
          decoration: BoxDecoration(
            color: errorColor.withValues(alpha: 0.08),
            borderRadius: WpRadius.borderMd,
            border: Border.all(color: errorColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.triangleAlert, size: 16, color: errorColor),
              const SizedBox(width: WpSpacing.sm),
              Expanded(
                child: Text(
                  message ?? l10n.modelDownloadFailed,
                  style: TextStyle(fontSize: 12, color: errorColor),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: Icon(LucideIcons.refreshCw, size: 14, color: textSecondary),
            label: Text(
              l10n.overlayRetry,
              style: TextStyle(fontSize: 13, color: textSecondary),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: isDark
                    ? WpColorsDark.borderDefault
                    : WpColorsLight.borderDefault,
              ),
              shape: RoundedRectangleBorder(borderRadius: WpRadius.borderMd),
              padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// GPU CPU fallback notice — informational, non-blocking.
// ---------------------------------------------------------------------------

/// Renders the „Optimierte GPU-Beschleunigung nicht verfügbar — App nutzt CPU"
/// banner shown when `GpuVendor.none` is detected (either no GPU is present
/// or both Windows probes failed/timed out).
///
/// Purely informational: the user keeps full access to every quality tier
/// and the cloud option. Tier-internal performance hints
/// ([_tierPerformanceMessage]) cover „this tier will be slow on this
/// hardware" separately.
class _GpuCpuFallbackNotice extends StatelessWidget {
  const _GpuCpuFallbackNotice({
    super.key,
    required this.message,
    required this.isDark,
  });

  final String message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final infoColor = TierPerformancePresentation.color(isDark: isDark);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WpSpacing.sm),
      decoration: BoxDecoration(
        color: infoColor.withValues(alpha: 0.08),
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: infoColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 14, color: infoColor),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: infoColor),
            ),
          ),
        ],
      ),
    );
  }
}
