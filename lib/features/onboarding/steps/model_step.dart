import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hardware_info_service.dart' as hw;
import '../../../services/model_download_service.dart';
import '../../../widgets/wp_accent_button.dart';

/// Onboarding Step 3 — Quality tier selection & download.
///
/// Shows a hardware-recommended tier with one-click download, plus an
/// expandable section to choose a different quality level.
class ModelStep extends ConsumerStatefulWidget {
  const ModelStep({
    super.key,
    required this.onNext,
    required this.onBack,
  });

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

  @override
  void initState() {
    super.initState();
    _detectHardware();
  }

  Future<void> _detectHardware() async {
    final gpu = await hw.detectGpu();
    if (!mounted) return;
    final rec = recommendTier(gpu.vramMB ?? 0);
    setState(() {
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

    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;

    final isDownloading = dlState.phase == DownloadPhase.downloading ||
        dlState.phase == DownloadPhase.extracting ||
        dlState.phase == DownloadPhase.verifying;
    final isDone = dlState.phase == DownloadPhase.done ||
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
            tier: _selectedTier ?? _recommendedTier ?? QualityTier.balanced,
            isRecommended:
                _selectedTier == _recommendedTier || _selectedTier == null,
            isSelected: true,
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
            )
          else if (isError)
            _DownloadError(
              message: dlState.errorMessage,
              isDark: isDark,
              onRetry: _startDownload,
            )
          else if (isDone)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.circleCheck,
                    size: 18,
                    color: isDark
                        ? WpColorsDark.success
                        : WpColorsLight.success),
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
                    '${l10n.qualityTierDownloadAndContinue} (${tierSizeLabel(_selectedTier ?? QualityTier.balanced)})',
                gradient: accentGradient,
                onPressed: _startDownload,
              ),
            ),

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
                        child: Icon(LucideIcons.chevronDown,
                            size: 14, color: accent),
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
                                  bottom: WpSpacing.xs),
                              child: _TierCard(
                                tier: tier,
                                isRecommended: tier == _recommendedTier,
                                isSelected: false,
                                isDark: isDark,
                                l10n: l10n,
                                onTap: () => setState(() {
                                  _selectedTier = tier;
                                  _showAlternatives = false;
                                }),
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
// Tier Card — shows tier name, description, size, recommended badge
// ---------------------------------------------------------------------------

class _TierCard extends StatefulWidget {
  const _TierCard({
    required this.tier,
    required this.isRecommended,
    required this.isSelected,
    required this.isDark,
    required this.l10n,
    required this.onTap,
  });

  final QualityTier tier;
  final bool isRecommended;
  final bool isSelected;
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
    final accent =
        widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
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

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: WpMotion.fast,
          curve: WpMotion.defaultCurve,
          padding: const EdgeInsets.all(WpSpacing.md),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? accent.withValues(alpha: 0.08)
                : surface.withValues(alpha: 0.5),
            border: Border.all(color: borderColor, width: widget.isSelected ? 1.5 : 1),
            borderRadius: WpRadius.borderMd,
          ),
          child: Row(
            children: [
              Icon(_tierIcon, size: 22, color: accent),
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
                            color: textPrimary,
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
                        color: textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              Text(
                tierSizeLabel(widget.tier),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
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
  });

  final DownloadPhase phase;
  final double progress;
  final bool isDark;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;

    final label = switch (phase) {
      DownloadPhase.downloading => '${(progress * 100).round()}%',
      DownloadPhase.extracting => 'Extracting…',
      DownloadPhase.verifying => 'Verifying…',
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
        Text(
          label,
          style: TextStyle(fontSize: 12, color: textSecondary),
        ),
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
    required this.onRetry,
  });

  final String? message;
  final bool isDark;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final errorColor = isDark ? WpColorsDark.error : WpColorsLight.error;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;

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
                  message ?? 'Download failed. Please check your internet connection.',
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
              'Retry',
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
