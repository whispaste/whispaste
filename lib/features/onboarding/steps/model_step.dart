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
          if (isDownloading)
            _DownloadProgress(
              phase: dlState.phase,
              progress: dlState.progressPercent / 100.0,
              isDark: isDark,
              accent: accent,
              l10n: l10n,
            )
          else if (isError)
            _DownloadError(
              message: dlState.errorMessage,
              isDark: isDark,
              l10n: l10n,
              onRetry: _startDownload,
            )
          else if (isDone)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.circleCheck,
                  size: 18,
                  color: isDark ? WpColorsDark.success : WpColorsLight.success,
                ),
                const SizedBox(width: WpSpacing.xs),
                Text(
                  l10n.modelReady,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? WpColorsDark.success
                        : WpColorsLight.success,
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: WpAccentButton(
                label:
                    '${l10n.qualityTierDownloadAndContinue} (${tierSizeLabel(selectedTier)})',
                gradient: accentGradient,
                onPressed: _startDownload,
              ),
            ),

          // Hardware warning
          if (_gpu != null) ...[
            Builder(
              builder: (context) {
                final infoMessage = _tierPerformanceMessage(
                  l10n: l10n,
                  tier: selectedTier,
                  performance: selectedPerformance,
                );
                if (infoMessage == null) return const SizedBox.shrink();
                final infoColor = TierPerformancePresentation.color(
                  isDark: isDark,
                );
                final infoIcon = TierPerformancePresentation.icon(
                  selectedPerformance,
                );
                return Padding(
                  padding: const EdgeInsets.only(top: WpSpacing.sm),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(WpSpacing.sm),
                    decoration: BoxDecoration(
                      color: infoColor.withValues(alpha: 0.08),
                      borderRadius: WpRadius.borderMd,
                      border: Border.all(
                        color: infoColor.withValues(alpha: 0.2),
                      ),
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
              },
            ),
          ],

          // Choose different tier
          const SizedBox(height: WpSpacing.md),
          if (!isDownloading && !isDone)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () =>
                    setState(() => _showAlternatives = !_showAlternatives),
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
                        turns: _showAlternatives ? 0.5 : 0,
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

          // Alternative tiers
          AnimatedSize(
            duration: WpMotion.smooth,
            curve: WpMotion.defaultCurve,
            child: _showAlternatives && !isDownloading && !isDone
                ? Padding(
                    padding: const EdgeInsets.only(top: WpSpacing.sm),
                    child: Column(
                      children: [
                        for (final tier in QualityTier.values)
                          if (tier != _selectedTier)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: WpSpacing.xs,
                              ),
                              child: _TierCard(
                                tier: tier,
                                isRecommended: tier == _recommendedTier,
                                isSelected: false,
                                performance: _gpu != null
                                    ? tierPerformance(tier, _gpu!)
                                    : TierPerformance.unmeasured,
                                gpu: _gpu,
                                isDark: isDark,
                                l10n: l10n,
                                onTap: () {
                                  setState(() {
                                    _selectedTier = tier;
                                    _showAlternatives = false;
                                  });
                                },
                              ),
                            ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
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
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onNext,
            borderRadius: WpRadius.borderSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.xs,
              ),
              child: Text(
                l10n.onboardingModelUseCloud,
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

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: isTappable ? SystemMouseCursors.click : SystemMouseCursors.basic,
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
                              style: TextStyle(fontSize: 11, color: infoColor),
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
