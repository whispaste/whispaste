/// Model download card — shows STT quality tiers with download status,
/// progress, and one-tap download. Designed to be embedded in the Settings page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/hardware_info_service.dart' as hw;
import '../services/model_download_service.dart';

/// Tier-based model manager — shows 3 quality tiers (compact, balanced,
/// premium) instead of raw model names. Auto-recommends based on GPU VRAM.
class SttModelManager extends ConsumerStatefulWidget {
  const SttModelManager({super.key});

  @override
  ConsumerState<SttModelManager> createState() => _SttModelManagerState();
}

class _SttModelManagerState extends ConsumerState<SttModelManager> {
  @override
  Widget build(BuildContext context) {
    final gpuAsync = ref.watch(hw.gpuInfoProvider);
    final gpu = gpuAsync.value;
    final recommendedTier = gpu != null
        ? recommendTier(gpu.vramMB ?? 0, vendor: gpu.vendor)
        : null;
    final downloadState = ref.watch(modelDownloadProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Server status row
        _ServerStatusRow(
          serverReady: downloadState.serverReady,
          isDark: isDark,
          l10n: l10n,
        ),
        const SizedBox(height: WpSpacing.sm),
        // Tier cards
        for (final tier in QualityTier.values) ...[
          _TierRow(
            tier: tier,
            isRecommended: tier == recommendedTier,
            warning: gpu != null ? tierWarning(tier, gpu) : null,
            downloadState: downloadState,
            isDark: isDark,
            l10n: l10n,
            onDownload: downloadState.isBusy
                ? null
                : () => ref
                    .read(modelDownloadProvider.notifier)
                    .downloadModel(bestModelForTier(tier).id),
            onCancel: _isTierActive(tier, downloadState) &&
                    downloadState.isBusy
                ? () =>
                    ref.read(modelDownloadProvider.notifier).cancelDownload()
                : null,
            onDelete: _isTierDownloaded(tier, downloadState)
                ? () {
                    // Delete ALL models in this tier
                    for (final m in modelsForTier(tier)) {
                      if (downloadState.downloadedModels.contains(m.id)) {
                        ref
                            .read(modelDownloadProvider.notifier)
                            .deleteModel(m.id);
                      }
                    }
                  }
                : null,
          ),
        ],
        // Error message
        if (downloadState.isError && downloadState.errorMessage != null) ...[
          const SizedBox(height: WpSpacing.sm),
          _ErrorBanner(
            message: downloadState.errorMessage!,
            isDark: isDark,
            l10n: l10n,
          ),
        ],
      ],
    );
  }

  /// Whether any model in this tier is currently being downloaded.
  bool _isTierActive(QualityTier tier, ModelDownloadState state) {
    if (state.activeModelId == null) return false;
    return modelsForTier(tier).any((m) => m.id == state.activeModelId);
  }

  /// Whether any model in this tier is downloaded.
  bool _isTierDownloaded(QualityTier tier, ModelDownloadState state) {
    return modelsForTier(tier)
        .any((m) => state.downloadedModels.contains(m.id));
  }
}

// ---------------------------------------------------------------------------
// Tier row — shows quality tier with icon, description, status, actions
// ---------------------------------------------------------------------------

class _TierRow extends StatefulWidget {
  const _TierRow({
    required this.tier,
    required this.isRecommended,
    this.warning,
    required this.downloadState,
    required this.isDark,
    required this.l10n,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  final QualityTier tier;
  final bool isRecommended;
  final String? warning;
  final ModelDownloadState downloadState;
  final bool isDark;
  final L10n l10n;
  final VoidCallback? onDownload;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  @override
  State<_TierRow> createState() => _TierRowState();
}

class _TierRowState extends State<_TierRow> {
  bool _isHovered = false;

  bool get _isDownloaded => widget.downloadState.downloadedModels
      .contains(bestModelForTier(widget.tier).id);

  bool get _isActive =>
      widget.downloadState.activeModelId != null &&
      modelsForTier(widget.tier)
          .any((m) => m.id == widget.downloadState.activeModelId) &&
      widget.downloadState.isBusy;

  DownloadPhase get _phase {
    if (!_isActive) return DownloadPhase.idle;
    return widget.downloadState.phase;
  }

  int get _progress {
    if (!_isActive) return 0;
    return widget.downloadState.progressPercent;
  }

  IconData get _tierIcon => switch (widget.tier) {
        QualityTier.compact => LucideIcons.zap,
        QualityTier.balanced => LucideIcons.scale,
        QualityTier.premium => LucideIcons.crown,
      };

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

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary =
        widget.isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary = widget.isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted =
        widget.isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final hoverBg =
        widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;
    final success =
        widget.isDark ? WpColorsDark.success : WpColorsLight.success;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: WpMotion.hoverIn,
        curve: WpMotion.defaultCurve,
        margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xs, vertical: 1),
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: _isHovered ? hoverBg : Colors.transparent,
          borderRadius: BorderRadius.circular(WpRadius.sm),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Tier icon with status indicator
                _StatusIcon(
                  isDownloaded: _isDownloaded,
                  isActive: _isActive,
                  phase: _phase,
                  icon: _tierIcon,
                  accent: accent,
                  success: success,
                  muted: textMuted,
                ),
                const SizedBox(width: WpSpacing.sm),
                // Tier info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _tierLabel(widget.l10n),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ),
                          if (widget.isRecommended) ...[
                            const SizedBox(width: WpSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(WpRadius.full),
                              ),
                              child: Text(
                                widget.l10n.qualityTierRecommended,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: WpSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: _isDownloaded
                                  ? success.withValues(alpha: 0.12)
                                  : textMuted.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(WpRadius.full),
                            ),
                            child: Text(
                              tierSizeLabel(widget.tier),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color:
                                    _isDownloaded ? success : textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _tierDesc(widget.l10n),
                        style: TextStyle(fontSize: 11, color: textSecondary),
                      ),
                      if (widget.warning != null && !_isDownloaded) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(LucideIcons.triangleAlert,
                                size: WpIconSize.xs,
                                color: widget.isDark
                                    ? WpColorsDark.warning
                                    : WpColorsLight.warning),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                widget.warning!,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: widget.isDark
                                      ? WpColorsDark.warning
                                      : WpColorsLight.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Action
                _buildAction(accent, textMuted),
              ],
            ),
            // Progress bar
            if (_isActive && _phase == DownloadPhase.downloading)
              Padding(
                padding: const EdgeInsets.only(top: WpSpacing.xs),
                child: _DownloadProgress(
                  percent: _progress,
                  accent: accent,
                  isDark: widget.isDark,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(Color accent, Color muted) {
    if (_isActive &&
        (_phase == DownloadPhase.downloading ||
            _phase == DownloadPhase.extracting ||
            _phase == DownloadPhase.verifying)) {
      return _ActionChip(
        label: widget.l10n.actionCancel,
        icon: LucideIcons.x,
        color: muted,
        onTap: widget.onCancel,
      );
    }

    if (_isDownloaded) {
      if (_isHovered) {
        return _ActionChip(
          label: widget.l10n.actionDelete,
          icon: LucideIcons.trash2,
          color: widget.isDark ? WpColorsDark.error : WpColorsLight.error,
          onTap: widget.onDelete,
        );
      }
      // Show "ready" only when both model file AND server binary exist.
      final fullyReady = widget.downloadState.serverReady;
      final chipColor = fullyReady
          ? (widget.isDark ? WpColorsDark.success : WpColorsLight.success)
          : (widget.isDark ? WpColorsDark.warning : WpColorsLight.warning);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            fullyReady ? LucideIcons.circleCheck : LucideIcons.loaderCircle,
            size: 14,
            color: chipColor,
          ),
          const SizedBox(width: 4),
          Text(
            fullyReady
                ? widget.l10n.modelReady
                : widget.l10n.modelServerMissing,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: chipColor,
            ),
          ),
        ],
      );
    }

    return _ActionChip(
      label: widget.l10n.modelDownload,
      icon: LucideIcons.download,
      color: accent,
      onTap: widget.onDownload,
    );
  }
}

// ---------------------------------------------------------------------------
// Server status indicator
// ---------------------------------------------------------------------------

class _ServerStatusRow extends StatelessWidget {
  const _ServerStatusRow({
    required this.serverReady,
    required this.isDark,
    required this.l10n,
  });

  final bool serverReady;
  final bool isDark;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final statusColor = serverReady
        ? (isDark ? WpColorsDark.success : WpColorsLight.success)
        : (isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted);
    final textColor =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(
            serverReady ? LucideIcons.circleCheck : LucideIcons.circleAlert,
            size: 14,
            color: statusColor,
          ),
          const SizedBox(width: WpSpacing.xs),
          Text(
            serverReady
                ? l10n.modelServerReady
                : l10n.modelServerMissing,
            style: TextStyle(fontSize: 12, color: textColor),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status icon — spinner or tier icon
// ---------------------------------------------------------------------------

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.isDownloaded,
    required this.isActive,
    required this.phase,
    required this.icon,
    required this.accent,
    required this.success,
    required this.muted,
  });

  final bool isDownloaded;
  final bool isActive;
  final DownloadPhase phase;
  final IconData icon;
  final Color accent;
  final Color success;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    if (isActive &&
        (phase == DownloadPhase.downloading ||
            phase == DownloadPhase.extracting ||
            phase == DownloadPhase.verifying)) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
      );
    }

    return Icon(icon, size: 20, color: isDownloaded ? success : muted);
  }
}

// ---------------------------------------------------------------------------
// Download progress bar
// ---------------------------------------------------------------------------

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({
    required this.percent,
    required this.accent,
    required this.isDark,
  });

  final int percent;
  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(WpRadius.full),
      child: LinearProgressIndicator(
        value: percent / 100,
        minHeight: 3,
        backgroundColor: isDark
            ? WpColorsDark.borderSubtle
            : WpColorsLight.borderSubtle,
        valueColor: AlwaysStoppedAnimation(accent),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action chip — small tappable label with icon
// ---------------------------------------------------------------------------

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WpRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xs, vertical: WpSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: WpIconSize.sm, color: color),
            const SizedBox(width: WpSpacing.xxs),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error banner
// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.isDark,
    required this.l10n,
  });

  final String message;
  final bool isDark;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final errorColor = isDark ? WpColorsDark.error : WpColorsLight.error;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
      padding: const EdgeInsets.all(WpSpacing.sm),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(WpRadius.sm),
        border: Border.all(color: errorColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, size: 14, color: errorColor),
          const SizedBox(width: WpSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: errorColor),
            ),
          ),
        ],
      ),
    );
  }
}
