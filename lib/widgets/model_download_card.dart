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
import '../core/config/settings_provider.dart';
import 'tier_safety_presentation.dart';

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
    final settings = ref.watch(settingsProvider).value;
    final currentModelId = settings?.effectiveModelId;
    final currentTier = currentModelId != null
        ? tierForModel(currentModelId)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tier cards
        for (final tier in QualityTier.values) ...[
          _TierRow(
            tier: tier,
            isRecommended: tier == recommendedTier,
            isCurrentTier: tier == currentTier,
            safety: gpu != null ? tierSafety(tier, gpu) : TierSafety.usable,
            gpu: gpu,
            downloadState: downloadState,
            isDark: isDark,
            l10n: l10n,
            onSelect: downloadState.isBusy
                ? null
                : () => _selectTier(tier, downloadState),
            onCancel: _isTierActive(tier, downloadState) && downloadState.isBusy
                ? () =>
                      ref.read(modelDownloadProvider.notifier).cancelDownload()
                : null,
            onDelete: _isTierDownloaded(tier, downloadState)
                ? () {
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

  /// Select a tier: activate it in settings and auto-download if needed.
  void _selectTier(QualityTier tier, ModelDownloadState downloadState) {
    if (_isTierDownloaded(tier, downloadState)) {
      // Model already available — activate the best downloaded model.
      _activateTier(tier, downloadState);
    } else {
      // Model needs downloading — start download; _markModelDone will
      // auto-activate in settings once the download succeeds.
      ref
          .read(modelDownloadProvider.notifier)
          .downloadModel(bestModelForTier(tier).id);
    }
  }

  /// Activate a tier as the current model.
  /// Uses the best downloaded model in the tier (not necessarily
  /// [bestModelForTier], which may not be on disk yet).
  void _activateTier(QualityTier tier, ModelDownloadState downloadState) {
    final downloaded = modelsForTier(
      tier,
    ).where((m) => downloadState.downloadedModels.contains(m.id));
    final modelId = downloaded.isNotEmpty
        ? downloaded.first.id
        : bestModelForTier(tier).id;
    ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => s.copyWith(sttModel: modelId));
  }

  /// Whether any model in this tier is currently being downloaded.
  bool _isTierActive(QualityTier tier, ModelDownloadState state) {
    if (state.activeModelId == null) return false;
    return modelsForTier(tier).any((m) => m.id == state.activeModelId);
  }

  /// Whether any model in this tier is downloaded.
  bool _isTierDownloaded(QualityTier tier, ModelDownloadState state) {
    return modelsForTier(
      tier,
    ).any((m) => state.downloadedModels.contains(m.id));
  }
}

// ---------------------------------------------------------------------------
// Tier row — shows quality tier with icon, description, status, actions
// ---------------------------------------------------------------------------

class _TierRow extends StatefulWidget {
  const _TierRow({
    required this.tier,
    required this.isRecommended,
    this.isCurrentTier = false,
    required this.safety,
    required this.gpu,
    required this.downloadState,
    required this.isDark,
    required this.l10n,
    required this.onSelect,
    required this.onCancel,
    required this.onDelete,
  });

  final QualityTier tier;
  final bool isRecommended;
  final bool isCurrentTier;
  final TierSafety safety;
  final hw.GpuInfo? gpu;
  final ModelDownloadState downloadState;
  final bool isDark;
  final L10n l10n;
  final VoidCallback? onSelect;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  @override
  State<_TierRow> createState() => _TierRowState();
}

class _TierRowState extends State<_TierRow> {
  bool _isHovered = false;

  bool get _isDownloaded => widget.downloadState.downloadedModels.contains(
    bestModelForTier(widget.tier).id,
  );

  bool get _isDownloading =>
      widget.downloadState.activeModelId != null &&
      modelsForTier(
        widget.tier,
      ).any((m) => m.id == widget.downloadState.activeModelId) &&
      widget.downloadState.isBusy;

  DownloadPhase get _phase {
    if (!_isDownloading) return DownloadPhase.idle;
    return widget.downloadState.phase;
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
    final accent = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = widget.isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = widget.isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = widget.isDark
        ? WpColorsDark.textMuted
        : WpColorsLight.textMuted;
    final hoverBg = widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;
    final success = widget.isDark
        ? WpColorsDark.success
        : WpColorsLight.success;

    final bestModel = bestModelForTier(widget.tier);
    final warningMessage = TierSafetyPresentation.message(
      l10n: widget.l10n,
      tier: widget.tier,
      safety: widget.safety,
      gpu: widget.gpu,
    );
    final warningColor = TierSafetyPresentation.color(
      isDark: widget.isDark,
      safety: widget.safety,
    );

    final bool isSelectable =
        widget.onSelect != null && (!widget.isCurrentTier || !_isDownloaded);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: isSelectable
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: isSelectable ? widget.onSelect : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: WpMotion.hoverIn,
          curve: WpMotion.defaultCurve,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: widget.isCurrentTier || _isDownloading
                ? accent.withValues(alpha: 0.08)
                : _isHovered && isSelectable
                ? hoverBg
                : Colors.transparent,
            borderRadius: BorderRadius.circular(WpRadius.sm),
            border: widget.isCurrentTier || _isDownloading
                ? Border.all(color: accent.withValues(alpha: 0.3))
                : null,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Tier icon with status indicator
                  _StatusIcon(
                    isDownloaded: _isDownloaded,
                    isActive: _isDownloading,
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
                            const SizedBox(width: WpSpacing.xxs),
                            Tooltip(
                              message: widget.l10n.qualityTierModelTooltip(
                                bestModel.label,
                                bestModel.sizeLabel,
                              ),
                              child: Icon(
                                LucideIcons.info,
                                size: 14,
                                color: textMuted,
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
                                  borderRadius: BorderRadius.circular(
                                    WpRadius.full,
                                  ),
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
                                borderRadius: BorderRadius.circular(
                                  WpRadius.full,
                                ),
                              ),
                              child: Text(
                                tierSizeLabel(widget.tier),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: _isDownloaded ? success : textMuted,
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
                        if (warningMessage != null) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                TierSafetyPresentation.icon(widget.safety),
                                size: WpIconSize.xs,
                                color: warningColor,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  warningMessage,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: warningColor,
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
              // Progress bar + status text
              if (_isDownloading && widget.downloadState.isBusy)
                Padding(
                  padding: const EdgeInsets.only(top: WpSpacing.xs),
                  child: _DownloadProgressInfo(
                    downloadState: widget.downloadState,
                    accent: accent,
                    isDark: widget.isDark,
                    l10n: widget.l10n,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAction(Color accent, Color muted) {
    // Active download in this tier → Cancel button
    if (_isDownloading &&
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

    if (widget.isCurrentTier) {
      // Current active tier
      if (_isDownloaded) {
        // Downloaded + active → show ready / delete on hover
        if (_isHovered) {
          return _ActionChip(
            label: widget.l10n.actionDelete,
            icon: LucideIcons.trash2,
            color: widget.isDark ? WpColorsDark.error : WpColorsLight.error,
            onTap: widget.onDelete,
          );
        }
        final success = widget.isDark
            ? WpColorsDark.success
            : WpColorsLight.success;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleCheck, size: 14, color: success),
            const SizedBox(width: 4),
            Text(
              widget.l10n.modelReady,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: success,
              ),
            ),
          ],
        );
      }
      // Active but not downloaded — show spinner only during active download.
      if (_isDownloading) {
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        );
      }
      // Not downloading (deleted or error) — no action indicator.
      return const SizedBox.shrink();
    }

    // Inactive tier — show delete on hover if downloaded
    if (_isDownloaded && _isHovered) {
      return _ActionChip(
        label: widget.l10n.actionDelete,
        icon: LucideIcons.trash2,
        color: widget.isDark ? WpColorsDark.error : WpColorsLight.error,
        onTap: widget.onDelete,
      );
    }

    return const SizedBox.shrink();
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
// Download progress bar with speed/ETA info
// ---------------------------------------------------------------------------

class _DownloadProgressInfo extends StatelessWidget {
  const _DownloadProgressInfo({
    required this.downloadState,
    required this.accent,
    required this.isDark,
    required this.l10n,
  });

  final ModelDownloadState downloadState;
  final Color accent;
  final bool isDark;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final phase = downloadState.phase;
    final isVerifying = phase == DownloadPhase.verifying;
    final isExtracting = phase == DownloadPhase.extracting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(WpRadius.full),
          child: LinearProgressIndicator(
            value: isVerifying || isExtracting
                ? null // indeterminate for verification/extraction
                : downloadState.progressPercent / 100,
            minHeight: 3,
            backgroundColor: isDark
                ? WpColorsDark.borderSubtle
                : WpColorsLight.borderSubtle,
            valueColor: AlwaysStoppedAnimation(accent),
          ),
        ),
        const SizedBox(height: 4),
        // Status text row
        Text(
          _statusText(),
          style: TextStyle(
            fontSize: 11,
            color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _statusText() {
    switch (downloadState.phase) {
      case DownloadPhase.verifying:
        return l10n.modelVerifying;
      case DownloadPhase.extracting:
        return l10n.modelExtracting;
      case DownloadPhase.downloading:
        return _downloadingText();
      default:
        return '';
    }
  }

  String _downloadingText() {
    final dl = downloadState.bytesDownloaded;
    final total = downloadState.totalBytes;
    final speed = downloadState.speedBytesPerSec;
    final eta = downloadState.etaSeconds;
    final label = downloadState.statusLabel;

    final parts = <String>[];

    // Size progress: "156 MB / 350 MB"
    if (total > 0) {
      parts.add('${_formatBytes(dl)} / ${_formatBytes(total)}');
    } else if (dl > 0) {
      parts.add(_formatBytes(dl));
    }

    // Speed: "12.3 MB/s"
    if (speed > 100) {
      parts.add('${_formatBytes(speed.round())}/s');
    }

    // ETA: "~2:30"
    if (eta != null && eta > 0 && eta < 36000) {
      parts.add('~${_formatDuration(eta)}');
    }

    final info = parts.join(' · ');

    // Prefix with what's being downloaded
    if (label == 'engine') {
      return info.isEmpty
          ? l10n.modelDownloadingEngine
          : '${l10n.modelDownloadingEngine} $info';
    }
    return info.isEmpty ? l10n.modelDownloading : info;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
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
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.xs,
          vertical: WpSpacing.xxs,
        ),
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
