/// Pure tier-card widget for STT model selection.
///
/// [SttModelSelector] renders the three quality-tier cards (compact / balanced
/// / premium) and wires download/cancel/delete actions to [ModelDownloadNotifier].
/// It does **not** import [AppSettings], [settingsProvider], or any Drift type.
///
/// The only way settings are updated is via the [onModelSelected] callback,
/// which the parent (e.g. [WpSttModelManager]) supplies.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/selectable_speech_models.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/download_error_text.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/speech_recommendation.dart';
import '../../services/stt/backend_utilization_notifier.dart'
    show processorCountProvider;
import '../../services/hardware_info_service.dart' as hw;
import '../../services/model_download_service.dart';
import '../../services/stt/stt_bundle.dart';
import '../../widgets/recommendation_reason.dart';
import '../../widgets/tier_performance_presentation.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_focus_ring.dart';
import '../../core/recording/recording_helpers.dart' show displayNameForModel;

/// Tier-based STT model selector.
///
/// Watches [modelDownloadProvider] and [localSttBundleProvider] directly.
/// Uses [currentModelId] and [benchmarkRtf] (supplied by the parent from
/// settings) to determine which tier is active.
///
/// Writes are **not** performed directly — the parent supplies [onModelSelected]
/// and is responsible for persisting the chosen model ID to settings.
class SttModelSelector extends ConsumerStatefulWidget {
  const SttModelSelector({
    super.key,
    required this.currentModelId,
    required this.onModelSelected,
    this.benchmarkRtf,
    this.gpu,
  });

  /// The model ID that is currently active in settings (may be null if no model
  /// has been selected yet).
  final String? currentModelId;

  /// Called with the chosen model ID when the user selects a tier.
  /// The parent is responsible for persisting this value to settings.
  final void Function(String modelId) onModelSelected;

  /// Benchmark RTF data per tier (from settings), used for performance labels.
  final Map<QualityTier, double>? benchmarkRtf;

  /// GPU info, used for tier recommendation and performance labels.
  /// When null, recommendations and performance labels are omitted.
  final hw.GpuInfo? gpu;

  @override
  ConsumerState<SttModelSelector> createState() => _SttModelSelectorState();
}

class _SttModelSelectorState extends ConsumerState<SttModelSelector> {
  @override
  Widget build(BuildContext context) {
    final downloadState = ref.watch(modelDownloadProvider);
    final l10n = L10n.of(context);
    final gpu = widget.gpu;

    // The tiers only show while Whisper is the active engine, so the badge
    // is the recommendation within Whisper (UIA-RT-03, E2a): the benchmark's
    // verdict when this machine has measured tiers, else the hardware class
    // (MV-03). Without GPU info only a measurement can recommend a tier. The same
    // provider feeds onboarding's model step (MV-04).
    final cpuCores = ref.watch(processorCountProvider);
    final ramMB = ref.watch(ramMBProvider);
    final recommendation = whisperRecommendationFor(
      gpu: gpu,
      measuredRtf: widget.benchmarkRtf,
      cpuCores: cpuCores,
      ramMB: ramMB,
    );
    final recommendedTier = recommendation.tier;
    final recommendationMeasured =
        recommendation.tierSource == TierRecommendationSource.measured;
    final reason = recommendationReason(
      l10n,
      SpeechRecommendation(
        recommendation: recommendation,
        gpuName: gpu?.name ?? '',
        vramMB: gpu?.vramMB,
        cpuCores: cpuCores,
        ramMB: ramMB,
      ),
      recommendation,
    );

    final currentTier = widget.currentModelId != null
        ? tierForModel(widget.currentModelId!)
        : null;

    // Benchmarking state from STT service.
    final sttStatus = ref.watch(localSttBundleProvider);
    final isBenchmarking = sttStatus.isBenchmarking;
    final benchmarkingTier = sttStatus.benchmarkingTier;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sttStatus.restartNeeded) ...[
          Text(
            l10n.sttEngineRestartHint,
            key: const ValueKey('settings-stt-engine-restart-hint'),
            style: TextStyle(color: WpColors.error),
          ),
          const SizedBox(height: WpSpacing.sm),
        ],
        // Tier cards
        for (final tier in QualityTier.values) ...[
          _TierRow(
            tier: tier,
            isRecommended: tier == recommendedTier,
            recommendationMeasured: recommendationMeasured,
            isCurrentTier: tier == currentTier,
            performance: gpu != null
                ? tierPerformance(tier, gpu, benchmarkRtf: widget.benchmarkRtf)
                : TierPerformance.unmeasured,
            gpu: gpu,
            downloadState: downloadState,
            l10n: l10n,
            isBenchmarking: isBenchmarking && benchmarkingTier == tier,
            benchmarkingTier: benchmarkingTier,
            benchmarkRtf: widget.benchmarkRtf,
            onSelect: downloadState.isBusy
                ? null
                : () => _selectTier(tier, downloadState),
            onCancel: _isTierActive(tier, downloadState) && downloadState.isBusy
                ? () =>
                      ref.read(modelDownloadProvider.notifier).cancelDownload()
                : null,
            onDelete: _isTierDownloaded(tier, downloadState)
                ? () async {
                    final downloaded = [
                      for (final m in modelsForTier(tier))
                        if (_installedModelIds().contains(m.id)) m,
                    ];
                    final confirmed = await confirmDestructive(
                      context: context,
                      title: l10n.modelTierDeleteConfirm,
                      message: l10n.modelTierDeleteConfirmMessage(
                        downloaded.length,
                        formatModelSizeLabel(
                          downloaded.fold(0, (sum, m) => sum + m.sizeBytes),
                        ),
                      ),
                      confirmLabel: l10n.actionDelete,
                      cancelLabel: l10n.actionCancel,
                    );
                    if (!confirmed) return;
                    final downloads = ref.read(modelDownloadProvider.notifier);
                    final releaseEngine = ref
                        .read(localSttBundleProvider.notifier)
                        .releaseModel;
                    for (final m in downloaded) {
                      downloads.deleteModel(m.id, releaseEngine: releaseEngine);
                    }
                  }
                : null,
          ),
        ],
        // Why that tier is recommended, in the words onboarding uses (MV-03).
        if (reason != null) ...[
          const SizedBox(height: WpSpacing.xs),
          Text(
            reason,
            key: const ValueKey('settings-stt-recommendation-reason'),
            style: TextStyle(
              fontSize: WpTypography.caption,
              color: WpColors.textMuted,
            ),
          ),
        ],
        // Error message
        if (downloadState.isError && downloadState.errorMessage != null) ...[
          const SizedBox(height: WpSpacing.sm),
          _ErrorBanner(
            message: downloadState.errorMessage == modelDeleteInUseError
                ? l10n.modelDeleteInUse
                : localizedDownloadError(l10n, downloadState.errorMessage),
            l10n: l10n,
            onRetry: () => ref.invalidate(modelDownloadProvider),
          ),
        ],
      ],
    );
  }

  /// Select a tier: notify parent and auto-download if needed.
  void _selectTier(QualityTier tier, ModelDownloadState downloadState) {
    if (_isTierDownloaded(tier, downloadState)) {
      // Model already available — activate the best downloaded model.
      _activateTier(tier, downloadState);
    } else {
      // Model needs downloading — start download; [_markModelDone] in the
      // notifier auto-activates it in settings once the download succeeds.
      ref
          .read(modelDownloadProvider.notifier)
          .downloadModel(bestModelForTier(tier).id);
    }
  }

  /// Resolve the best downloaded model in [tier] and call [onModelSelected].
  void _activateTier(QualityTier tier, ModelDownloadState downloadState) {
    final downloaded = modelsForTier(
      tier,
    ).where((m) => _installedModelIds().contains(m.id));
    final modelId = downloaded.isNotEmpty
        ? downloaded.first.id
        : bestModelForTier(tier).id;
    widget.onModelSelected(modelId);
  }

  /// Whether any model in this tier is currently being downloaded.
  bool _isTierActive(QualityTier tier, ModelDownloadState state) {
    if (state.activeModelId == null) return false;
    return modelsForTier(tier).any((m) => m.id == state.activeModelId);
  }

  /// The Whisper models the user can pick, read from the same provider as the
  /// dock's speech selector.
  Set<String> _installedModelIds() => {
    for (final model in ref.read(selectableSpeechModelsProvider))
      if (model.isInstalled) model.modelId,
  };

  /// Whether any model in this tier is downloaded.
  bool _isTierDownloaded(QualityTier tier, ModelDownloadState state) {
    return modelsForTier(tier).any((m) => _installedModelIds().contains(m.id));
  }
}

// ---------------------------------------------------------------------------
// Tier row — shows quality tier with icon, description, status, actions.
// (Identical to the private _TierRow in wp_stt_model_manager.dart — extracted
// here so SttModelSelector carries its own rendering logic.)
// ---------------------------------------------------------------------------

class _TierRow extends StatefulWidget {
  const _TierRow({
    required this.tier,
    required this.isRecommended,
    this.recommendationMeasured = false,
    this.isCurrentTier = false,
    required this.performance,
    required this.gpu,
    required this.downloadState,
    required this.l10n,
    required this.onSelect,
    required this.onCancel,
    required this.onDelete,
    this.isBenchmarking = false,
    this.benchmarkingTier,
    this.benchmarkRtf,
  });

  final QualityTier tier;
  final bool isRecommended;

  /// The recommendation rests on this machine's measurements, not the estimate.
  final bool recommendationMeasured;
  final bool isCurrentTier;
  final TierPerformance performance;

  /// Measured RTF per tier; lets the info line quote the real numbers.
  final Map<QualityTier, double>? benchmarkRtf;
  final hw.GpuInfo? gpu;
  final ModelDownloadState downloadState;
  final L10n l10n;
  final VoidCallback? onSelect;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;
  final bool isBenchmarking;
  final QualityTier? benchmarkingTier;

  @override
  State<_TierRow> createState() => _TierRowState();
}

class _TierRowState extends State<_TierRow> {
  final FocusNode _focusNode = FocusNode();
  bool _isHovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

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

  /// The row title is the model's display name ("Whisper · Balanced"), the
  /// same one the dock, statistics and toasts show (UIA-NAM-01).
  String _tierLabel(L10n l10n) =>
      displayNameForModel(bestModelForTier(widget.tier).id, l10n);

  String _tierDesc(L10n l10n) => switch (widget.tier) {
    QualityTier.compact => l10n.qualityTierCompactDesc,
    QualityTier.balanced => l10n.qualityTierBalancedDesc,
    QualityTier.premium => l10n.qualityTierPremiumDesc,
  };

  /// Performance the info line is *allowed* to announce.
  ///
  /// While a benchmark is still running, [_TierRow.performance] is only the
  /// VRAM-based estimate — colouring the line with it would show a red "slow"
  /// verdict before anything was measured, exactly the false signal the graded
  /// colours exist to remove. Benchmarking therefore reads as `unmeasured`.
  TierPerformance get _infoPerformance =>
      widget.isBenchmarking ? TierPerformance.unmeasured : widget.performance;

  @override
  Widget build(BuildContext context) {
    final accent = WpColors.accent;
    final accentButtonFill = WpColors.accentButtonFill;
    final accentBorder30 = WpColors.accentBorder30;
    final textMuted = WpColors.textMuted;
    final hoverBg = WpColors.hover;

    // Performance info is only shown on the current tier
    final showPerformanceInfo = widget.isCurrentTier || widget.isBenchmarking;
    final infoMessage = showPerformanceInfo
        ? WpTierPerformancePresentation.message(
            l10n: widget.l10n,
            tier: widget.tier,
            performance: widget.performance,
            rtf: widget.benchmarkRtf?[widget.tier],
            benchmarkRtf: widget.benchmarkRtf,
          )
        : null;
    final infoPerformance = _infoPerformance;
    final infoColor = WpTierPerformancePresentation.color(
      performance: infoPerformance,
    );

    final bool isSelectable =
        widget.onSelect != null && (!widget.isCurrentTier || !_isDownloaded);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: isSelectable
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Semantics(
        // No `label:` — the tier name and description are already rendered
        // as visible Text descendants further down this subtree, and a
        // Semantics label is prepended to (not substituted for) that text,
        // so adding one here would announce the tier name twice (see the
        // identical tradeoff documented on `_SnippetTile._buildRow`).
        button: isSelectable,
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.sm,
          child: InkWell(
            onTap: isSelectable ? widget.onSelect : null,
            focusNode: _focusNode,
            borderRadius: BorderRadius.circular(WpRadius.sm),
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: AnimatedContainer(
              duration: WpMotion.durationFor(context, WpMotion.hoverIn),
              curve: WpMotion.defaultCurve,
              // 1px margin keeps adjacent rows' selection borders from touching.
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: widget.isCurrentTier || _isDownloading
                    ? accentButtonFill
                    : _isHovered && isSelectable
                    ? hoverBg
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(WpRadius.sm),
                border: widget.isCurrentTier || _isDownloading
                    ? Border.all(color: accentBorder30)
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
                        muted: textMuted,
                      ),
                      const SizedBox(width: WpSpacing.sm),
                      // Tier info
                      Expanded(
                        child: _TierRowInfo(
                          tier: widget.tier,
                          label: _tierLabel(widget.l10n),
                          desc: _tierDesc(widget.l10n),
                          isRecommended: widget.isRecommended,
                          recommendationMeasured: widget.recommendationMeasured,
                          isBenchmarking: widget.isBenchmarking,
                          infoMessage: infoMessage,
                          infoColor: infoColor,
                          performance: infoPerformance,
                          l10n: widget.l10n,
                          accent: accent,
                          textMuted: textMuted,
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
                        l10n: widget.l10n,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The row's trailing slot: cancel while downloading, delete on hover,
  /// otherwise the downloaded marker.
  ///
  /// This slot is now the *only* place the row says "on disk". It used to say
  /// it three times in green — the tier icon, the size badge and a "Ready"
  /// chip — which spent the app's one earned-green colour on a fact that is
  /// true for as long as the file exists, i.e. never on anything that just
  /// happened (the Earned-Green Rule, `lib/DESIGN.md`; Ticket 14). Two of the
  /// three said it redundantly anyway. What is left is one neutral marker,
  /// and it now appears on *every* downloaded tier rather than only the active
  /// one: the green tier icon was what told the reader that an inactive tier
  /// was already downloaded, so removing it without moving that information
  /// here would have hidden it. The moment a download actually completes is
  /// reported where a moment belongs — a success toast, fired by
  /// `WpSttModelManager`.
  Widget _buildAction(Color accent, Color muted) {
    // Active download in this tier → Cancel button
    if (_isDownloading &&
        (_phase == DownloadPhase.downloading ||
            _phase == DownloadPhase.extracting ||
            _phase == DownloadPhase.verifying)) {
      // loam-ignore: a11y-interactive-semantics – semantics provided in _ActionChip.build
      return _ActionChip(
        label: widget.l10n.actionCancel,
        icon: LucideIcons.x,
        color: muted,
        onTap: widget.onCancel,
      );
    }

    // Downloaded, whichever tier — delete on hover, otherwise the one place
    // this row states that the model is on disk.
    if (_isDownloaded) {
      if (_isHovered) {
        // loam-ignore: a11y-interactive-semantics – semantics provided in _ActionChip.build
        return _ActionChip(
          label: widget.l10n.actionDelete,
          icon: LucideIcons.trash2,
          color: WpColors.error,
          onTap: widget.onDelete,
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.circleCheck,
            size: WpIconSize.xs,
            color: WpColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            widget.l10n.modelReady,
            style: TextStyle(
              fontSize: WpTypography.caption,
              fontWeight: FontWeight.w500,
              color: WpColors.textSecondary,
            ),
          ),
        ],
      );
    }

    // Active but not downloaded — show spinner only during active download.
    if (widget.isCurrentTier && _isDownloading) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
      );
    }

    // Selected but not on disk: dictation cannot run until it is, so the
    // row says so and carries the download instead of looking ready.
    if (widget.isCurrentTier &&
        widget.downloadState.scanned &&
        widget.onSelect != null) {
      // loam-ignore: a11y-interactive-semantics – semantics provided in _ActionChip.build
      return _ActionChip(
        key: ValueKey('stt-model-download-${widget.tier.name}'),
        label: widget.l10n.modelMissingDownloadAction,
        icon: LucideIcons.download,
        color: WpColors.warning,
        onTap: widget.onSelect,
      );
    }

    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// Tier row info — label, description, benchmarking, performance hint
// ---------------------------------------------------------------------------

class _TierRowInfo extends StatelessWidget {
  const _TierRowInfo({
    required this.tier,
    required this.label,
    required this.desc,
    required this.isRecommended,
    this.recommendationMeasured = false,
    required this.isBenchmarking,
    required this.infoMessage,
    required this.infoColor,
    required this.performance,
    required this.l10n,
    required this.accent,
    required this.textMuted,
  });

  final QualityTier tier;
  final String label;
  final String desc;
  final bool isRecommended;
  final bool recommendationMeasured;
  final bool isBenchmarking;
  final String? infoMessage;
  final Color infoColor;
  final TierPerformance performance;
  final L10n l10n;
  final Color accent;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    final textPrimary = WpColors.textPrimary;
    final textSecondary = WpColors.textSecondary;
    final bestModel = bestModelForTier(tier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A Wrap, not a Row: at large text scale the label, info icon and
        // badges do not fit one line, and the badges move to the next line
        // instead of overflowing the row.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: WpSpacing.xs,
          runSpacing: WpSpacing.xxs,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: WpTypography.body,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            Tooltip(
              message: l10n.qualityTierModelTooltip(
                bestModel.label,
                bestModel.sizeLabel,
              ),
              child: Icon(
                LucideIcons.info,
                size: WpIconSize.xs,
                color: textMuted,
              ),
            ),
            if (isRecommended)
              Container(
                // Sub-scale pill padding: keeps the micro-type badge hugging
                // its text.
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(WpRadius.full),
                ),
                child: Text(
                  recommendationMeasured
                      ? l10n.qualityTierRecommendedMeasured
                      : l10n.qualityTierRecommended,
                  style: TextStyle(
                    fontSize: WpTypography.micro,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
            Container(
              // Sub-scale pill padding: keeps the micro-type badge hugging
              // its text.
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: textMuted.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(WpRadius.full),
              ),
              // Download size — a property of the model, not a status. It used
              // to turn green once the tier was on disk, which made the *size*
              // carry the download state a second time (see `_buildAction`).
              child: Text(
                tierSizeLabel(tier),
                style: TextStyle(
                  fontSize: WpTypography.micro,
                  fontWeight: FontWeight.w500,
                  color: textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          desc,
          style: TextStyle(
            fontSize: WpTypography.caption,
            color: textSecondary,
          ),
        ),
        if (isBenchmarking) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: infoColor,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  l10n.qualityTierInfoBenchmarking,
                  style: TextStyle(
                    fontSize: WpTypography.micro,
                    color: infoColor,
                  ),
                ),
              ),
            ],
          ),
        ] else if (infoMessage != null) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(
                WpTierPerformancePresentation.icon(performance),
                size: WpIconSize.xs,
                color: infoColor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  infoMessage!,
                  style: TextStyle(
                    fontSize: WpTypography.micro,
                    color: infoColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
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
    required this.muted,
  });

  final bool isDownloaded;
  final bool isActive;
  final DownloadPhase phase;
  final IconData icon;
  final Color accent;
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

    // Downloaded tiers read a step brighter than tiers that are not on disk
    // yet — the same distinction the icon used to draw in green, made with
    // the neutral ramp instead so the colour is free for things that just
    // happened (`_buildAction`).
    return Icon(
      icon,
      size: WpIconSize.md,
      color: isDownloaded ? WpColors.textPrimary : muted,
    );
  }
}

// ---------------------------------------------------------------------------
// Download progress bar with speed/ETA info
// ---------------------------------------------------------------------------

class _DownloadProgressInfo extends StatelessWidget {
  const _DownloadProgressInfo({
    required this.downloadState,
    required this.accent,
    required this.l10n,
  });

  final ModelDownloadState downloadState;
  final Color accent;
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
            backgroundColor: WpColors.borderSubtle,
            valueColor: AlwaysStoppedAnimation(accent),
          ),
        ),
        const SizedBox(height: 4),
        // Status text row
        Text(
          _statusText(),
          style: TextStyle(
            fontSize: WpTypography.caption,
            color: WpColors.textMuted,
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
    super.key,
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
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
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
                  fontSize: WpTypography.caption,
                  fontWeight: FontWeight.w600,
                  color: color,
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
// Error banner
// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.l10n, this.onRetry});

  final String message;
  final L10n l10n;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final errorColor = WpColors.error;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
      padding: const EdgeInsets.all(WpSpacing.sm),
      decoration: BoxDecoration(
        color: WpColors.errorButtonFill,
        borderRadius: BorderRadius.circular(WpRadius.sm),
        border: Border.all(color: WpColors.errorBorder20),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: WpIconSize.xs,
            color: errorColor,
          ),
          const SizedBox(width: WpSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: WpTypography.small, color: errorColor),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: WpSpacing.xs),
            WpButton(
              label: l10n.actionRetry,
              variant: WpButtonVariant.ghost,
              tone: WpButtonTone.danger,
              size: WpButtonSize.dense,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
