/// Model download card — shows STT model list with download status, progress,
/// and one-tap download. Designed to be embedded in the Settings page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/model_download_service.dart';

/// Inline model manager — lists all available STT models with download
/// status indicators, progress bars, and action buttons.
///
/// UX pattern: "download-on-demand with status badges". Each model shows:
/// - ✓ Ready (green check) — model file exists on disk
/// - ↓ Download button — not yet downloaded, shows size
/// - ⟳ Progress bar — downloading with percentage
/// - ✗ Error — failed with retry option
class SttModelManager extends ConsumerWidget {
  const SttModelManager({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        // Model list
        for (final model in sttModels) ...[
          _ModelRow(
            model: model,
            isDownloaded: downloadState.downloadedModels.contains(model.id),
            isActive:
                downloadState.activeModelId == model.id && downloadState.isBusy,
            phase: downloadState.activeModelId == model.id
                ? downloadState.phase
                : DownloadPhase.idle,
            progressPercent: downloadState.activeModelId == model.id
                ? downloadState.progressPercent
                : 0,
            isDark: isDark,
            l10n: l10n,
            onDownload: downloadState.isBusy
                ? null
                : () => ref
                    .read(modelDownloadProvider.notifier)
                    .downloadModel(model.id),
            onCancel: downloadState.activeModelId == model.id &&
                    downloadState.isBusy
                ? () =>
                    ref.read(modelDownloadProvider.notifier).cancelDownload()
                : null,
            onDelete: downloadState.downloadedModels.contains(model.id)
                ? () => ref
                    .read(modelDownloadProvider.notifier)
                    .deleteModel(model.id)
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
          const Spacer(),
          Text(
            l10n.modelServerWhisper,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual model row
// ---------------------------------------------------------------------------

class _ModelRow extends StatefulWidget {
  const _ModelRow({
    required this.model,
    required this.isDownloaded,
    required this.isActive,
    required this.phase,
    required this.progressPercent,
    required this.isDark,
    required this.l10n,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  final SttModelInfo model;
  final bool isDownloaded;
  final bool isActive;
  final DownloadPhase phase;
  final int progressPercent;
  final bool isDark;
  final L10n l10n;
  final VoidCallback? onDownload;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  @override
  State<_ModelRow> createState() => _ModelRowState();
}

class _ModelRowState extends State<_ModelRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary =
        widget.isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary =
        widget.isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
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
        margin: const EdgeInsets.symmetric(
          horizontal: WpSpacing.xs,
          vertical: 1,
        ),
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
                // Status icon
                _StatusIcon(
                  isDownloaded: widget.isDownloaded,
                  isActive: widget.isActive,
                  phase: widget.phase,
                  accent: accent,
                  success: success,
                  muted: textMuted,
                ),
                const SizedBox(width: WpSpacing.sm),
                // Model info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _localizedLabel(widget.model.id, widget.l10n),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(width: WpSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: widget.isDownloaded
                                  ? success.withValues(alpha: 0.12)
                                  : textMuted.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(WpRadius.full),
                            ),
                            child: Text(
                              widget.model.sizeLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: widget.isDownloaded
                                    ? success
                                    : textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _localizedDescription(widget.model.id, widget.l10n),
                        style: TextStyle(fontSize: 11, color: textSecondary),
                      ),
                    ],
                  ),
                ),
                // Action button
                _buildAction(accent, textMuted),
              ],
            ),
            // Progress bar (only when active)
            if (widget.isActive && widget.phase == DownloadPhase.downloading)
              Padding(
                padding: const EdgeInsets.only(top: WpSpacing.xs),
                child: _DownloadProgress(
                  percent: widget.progressPercent,
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
    if (widget.isActive && isBusy) {
      // Cancel button during download
      return _ActionChip(
        label: widget.l10n.actionCancel,
        icon: LucideIcons.x,
        color: muted,
        onTap: widget.onCancel,
      );
    }

    if (widget.isDownloaded) {
      // Ready badge + delete on hover
      if (_isHovered) {
        return _ActionChip(
          label: widget.l10n.actionDelete,
          icon: LucideIcons.trash2,
          color: widget.isDark ? WpColorsDark.error : WpColorsLight.error,
          onTap: widget.onDelete,
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.circleCheck, size: 14,
            color: widget.isDark ? WpColorsDark.success : WpColorsLight.success),
          const SizedBox(width: 4),
          Text(
            widget.l10n.modelReady,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: widget.isDark ? WpColorsDark.success : WpColorsLight.success,
            ),
          ),
        ],
      );
    }

    // Download button
    return _ActionChip(
      label: widget.l10n.modelDownload,
      icon: LucideIcons.download,
      color: accent,
      onTap: widget.onDownload,
    );
  }

  bool get isBusy =>
      widget.phase == DownloadPhase.downloading ||
      widget.phase == DownloadPhase.extracting ||
      widget.phase == DownloadPhase.verifying;

  static String _localizedDescription(String modelId, L10n l10n) {
    return switch (modelId) {
      'whisper-tiny' => l10n.modelSizeTiny,
      'whisper-base' => l10n.modelSizeBase,
      'whisper-small' => l10n.modelSizeSmall,
      'whisper-medium' => l10n.modelSizeMedium,
      'whisper-large-v3-turbo' => l10n.modelSizeLargeTurbo,
      'whisper-large-v3' => l10n.modelSizeLarge,
      _ => '',
    };
  }

  static String _localizedLabel(String modelId, L10n l10n) {
    return switch (modelId) {
      'whisper-tiny' => l10n.settingsQualityFast,
      'whisper-base' => l10n.settingsQualityBasic,
      'whisper-small' => l10n.settingsQualityBalanced,
      'whisper-medium' => l10n.settingsQualityHigh,
      'whisper-large-v3-turbo' => l10n.settingsQualityBest,
      'whisper-large-v3' => l10n.settingsQualityMaximum,
      _ => modelId,
    };
  }
}

// ---------------------------------------------------------------------------
// Status icon — animated spinner or static icon
// ---------------------------------------------------------------------------

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.isDownloaded,
    required this.isActive,
    required this.phase,
    required this.accent,
    required this.success,
    required this.muted,
  });

  final bool isDownloaded;
  final bool isActive;
  final DownloadPhase phase;
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
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: accent,
        ),
      );
    }

    if (isDownloaded) {
      return Icon(LucideIcons.brain, size: 20, color: success);
    }

    return Icon(LucideIcons.brain, size: 20, color: muted);
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
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
