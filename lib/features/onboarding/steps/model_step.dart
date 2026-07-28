import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/engine_recommendation.dart';
import '../../../services/hardware_info_service.dart' as hw;
import '../../../services/model_download_service.dart';
import '../../../services/stt_parakeet/parakeet_download_service.dart';
import '../../../services/stt_parakeet/parakeet_model_registry.dart';
import '../../../widgets/tier_performance_presentation.dart';
import '../../../widgets/wp_accent_button.dart';

/// Widget keys exposed for testing. Kept in one place so tests and production
/// code agree on the contract.
@visibleForTesting
const kModelStepGpuCpuFallbackKey = Key('modelStepGpuCpuFallbackNotice');
@visibleForTesting
const kModelStepNextButtonKey = Key('modelStepNextButton');
@visibleForTesting
const kModelStepEngineParakeetCardKey = Key('modelStepEngineParakeetCard');
@visibleForTesting
const kModelStepEngineWhisperCardKey = Key('modelStepEngineWhisperCard');

/// Onboarding step — on-device speech recognition setup.
///
/// A two-way choice presented in plain language, no engine/tier/model
/// jargon: "Fast & European" (the Parakeet engine) vs. "All 99 Languages"
/// (the Whisper engine). The app auto-recommends one card via
/// [recommendEngine], driven by the dictation language (defaulted from the
/// Welcome step's UI locale) and, for the Whisper branch only, hardware —
/// Parakeet is faster than Whisper on every machine, so hardware never rules
/// it out; only the dictation language can. The user can override the
/// recommendation by tapping the other card.
class ModelStep extends ConsumerStatefulWidget {
  const ModelStep({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  ConsumerState<ModelStep> createState() => _ModelStepState();
}

class _ModelStepState extends ConsumerState<ModelStep> {
  OnDeviceEngine? _selectedEngine;
  EngineRecommendation? _recommendation;

  /// The Whisper tier for this hardware, computed independently of which
  /// engine ends up recommended/selected.
  ///
  /// [EngineRecommendation.tier] is `null` whenever Parakeet is recommended
  /// (Parakeet has no tiers) — but the user can still override the
  /// recommendation and pick Whisper by hand. Without this separate field,
  /// that override would fall back to the `QualityTier.balanced` default
  /// instead of the tier this machine actually warrants.
  QualityTier? _whisperTier;
  hw.GpuInfo? _gpu;
  bool _hwDetected = false;

  @override
  void initState() {
    super.initState();
    _detectHardware();
  }

  Future<void> _detectHardware() async {
    final gpu = await ref.read(hw.gpuInfoProvider.future);
    if (!mounted) return;
    // Await the future rather than a one-shot `.value` read — this step can
    // be the very first place in the widget tree to touch `settingsProvider`
    // (isolated widget tests do this; in the shipped app it's always warm by
    // the time onboarding shows). A one-shot read would silently see
    // `AsyncLoading` (`.value == null`) and fall back to a wrong locale.
    final settings = await ref.read(settingsProvider.future);
    if (!mounted) return;
    final locale = settings.locale;
    final rec = recommendEngine(
      dictationLanguageCode: locale,
      vendor: gpu.vendor,
      vramMB: gpu.vramMB ?? 0,
    );
    setState(() {
      _gpu = gpu;
      _recommendation = rec;
      _whisperTier =
          rec.tier ?? recommendTier(gpu.vramMB ?? 0, vendor: gpu.vendor);
      _selectedEngine ??= rec.engine;
      _hwDetected = true;
    });
  }

  /// Whether Parakeet is eligible for the detected dictation language.
  ///
  /// [recommendEngine] only ever recommends Whisper for a language reason —
  /// hardware never overrides Parakeet once the language qualifies — so a
  /// Whisper recommendation is equivalent to "Parakeet can't do this
  /// language". `false` before hardware detection completes (card starts
  /// disabled, matching the loading state).
  bool get _parakeetEligible =>
      _recommendation?.engine == OnDeviceEngine.parakeet;

  void _selectEngine(OnDeviceEngine engine) {
    if (engine == OnDeviceEngine.parakeet && !_parakeetEligible) return;
    setState(() => _selectedEngine = engine);
  }

  void _startDownload() {
    switch (_selectedEngine) {
      case OnDeviceEngine.whisper:
        final tier = _whisperTier ?? QualityTier.balanced;
        final model = bestModelForTier(tier);
        ref.read(modelDownloadProvider.notifier).downloadModel(model.id);
      case OnDeviceEngine.parakeet:
        ref.read(parakeetDownloadProvider.notifier).downloadBundle();
      case null:
        break;
    }
  }

  /// Persists the chosen engine (+ Whisper's resolved model) and advances.
  /// Only called once [_isDone] — see [build] — so this always writes a
  /// model that is actually on disk.
  void _confirmAndAdvance() {
    final engine = _selectedEngine;
    if (engine == null) return;
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(
            sttEngine: engine.value,
            sttModel: engine == OnDeviceEngine.whisper
                ? bestModelForTier(_whisperTier ?? QualityTier.balanced).id
                : null, // leave the persisted whisper model untouched
          ),
        );
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final whisperDl = ref.watch(modelDownloadProvider);
    final parakeetDl = ref.watch(parakeetDownloadProvider);

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

    final tier = _whisperTier ?? QualityTier.balanced;
    final whisperModel = bestModelForTier(tier);

    // Per-engine download status, normalized to whisper's `DownloadPhase` so
    // both engines can share `_ModelStepDownloadStatus` (see the mapping
    // function at the bottom of this file — Parakeet's phase enum is
    // deliberately shaped like whisper's, minus `extracting`).
    final selectedPhase = switch (_selectedEngine) {
      OnDeviceEngine.whisper => whisperDl.phase,
      OnDeviceEngine.parakeet => _parakeetPhaseAsDownloadPhase(
        parakeetDl.phase,
      ),
      null => DownloadPhase.idle,
    };
    final isDownloading =
        selectedPhase == DownloadPhase.downloading ||
        selectedPhase == DownloadPhase.extracting ||
        selectedPhase == DownloadPhase.verifying;
    final isError = selectedPhase == DownloadPhase.error;
    final isDone = switch (_selectedEngine) {
      OnDeviceEngine.whisper =>
        whisperDl.phase == DownloadPhase.done ||
            whisperDl.downloadedModels.contains(whisperModel.id),
      OnDeviceEngine.parakeet =>
        parakeetDl.phase == ParakeetDownloadPhase.done || parakeetDl.installed,
      null => false,
    };
    final errorMessage = switch (_selectedEngine) {
      OnDeviceEngine.whisper => whisperDl.errorMessage,
      OnDeviceEngine.parakeet => parakeetDl.errorMessage,
      null => null,
    };
    final progressPercent = switch (_selectedEngine) {
      OnDeviceEngine.whisper => whisperDl.progressPercent,
      OnDeviceEngine.parakeet => parakeetDl.progressPercent,
      null => 0,
    };
    final selectedSizeLabel = switch (_selectedEngine) {
      OnDeviceEngine.whisper => whisperModel.sizeLabel,
      OnDeviceEngine.parakeet => parakeetModelSizeLabel,
      null => '',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        Text(
          l10n.onboardingModelTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: WpTypography.headline,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.onboardingModelSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: WpTypography.subheading,
            color: textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: WpSpacing.xl),

        // GPU CPU fallback notice — purely informational, never blocks Next.
        //
        // Renders only when hardware detection returned `GpuVendor.none`,
        // either because no GPU is present or because both Windows probes
        // (wmic + PowerShell) failed/timed out. The user keeps access to
        // both engines and the cloud option below; the message just sets the
        // expectation that CPU inference will be slower on the Whisper path
        // (Parakeet is always CPU-only, so it is unaffected).
        if (_gpu?.vendor == hw.GpuVendor.none) ...[
          _GpuCpuFallbackNotice(
            key: kModelStepGpuCpuFallbackKey,
            message: l10n.onboardingModelGpuCpuFallback,
            isDark: isDark,
          ),
          const SizedBox(height: WpSpacing.md),
        ],

        if (!_hwDetected)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: WpSpacing.xl),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          )
        else ...[
          // loam-ignore: a11y-interactive-semantics – semantics provided in _EngineCardState.build
          _EngineCard(
            key: kModelStepEngineParakeetCardKey,
            icon: LucideIcons.zap,
            label: l10n.onboardingModelEngineParakeetLabel,
            description: l10n.onboardingModelEngineParakeetDesc,
            sizeLabel: parakeetModelSizeLabel,
            isRecommended: _recommendation?.engine == OnDeviceEngine.parakeet,
            isSelected: _selectedEngine == OnDeviceEngine.parakeet,
            isDisabled: !_parakeetEligible,
            disabledReason: l10n.onboardingModelEngineUnsupportedLanguage,
            isDark: isDark,
            onTap: () => _selectEngine(OnDeviceEngine.parakeet),
          ),
          const SizedBox(height: WpSpacing.sm),
          // loam-ignore: a11y-interactive-semantics – semantics provided in _EngineCardState.build
          _EngineCard(
            key: kModelStepEngineWhisperCardKey,
            icon: LucideIcons.globe,
            label: l10n.onboardingModelEngineWhisperLabel,
            description: l10n.onboardingModelEngineWhisperDesc,
            sizeLabel: whisperModel.sizeLabel,
            isRecommended: _recommendation?.engine == OnDeviceEngine.whisper,
            isSelected: _selectedEngine == OnDeviceEngine.whisper,
            isDisabled: false,
            disabledReason: null,
            isDark: isDark,
            onTap: () => _selectEngine(OnDeviceEngine.whisper),
          ),
          const SizedBox(height: WpSpacing.md),

          _ModelStepDownloadStatus(
            phase: selectedPhase,
            progressPercent: progressPercent,
            errorMessage: errorMessage,
            isDownloading: isDownloading,
            isError: isError,
            isDone: isDone,
            isDark: isDark,
            accent: accent,
            accentGradient: accentGradient,
            sizeLabel: selectedSizeLabel,
            l10n: l10n,
            onStartDownload: _startDownload,
          ),
        ],

        const SizedBox(height: WpSpacing.sm),
        Text(
          l10n.onboardingModelChangeLater,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: WpTypography.small, color: textMuted),
        ),
        const SizedBox(height: WpSpacing.xxs),

        // Cloud option — bypasses persistence entirely (no on-device engine
        // is written for a BYOK/cloud user).
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
                onPressed: isDone ? _confirmAndAdvance : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Maps Parakeet's download-phase enum onto whisper's `DownloadPhase` so
/// `_ModelStepDownloadStatus` can render either engine's progress uniformly.
/// The two enums are deliberately shaped alike (see
/// `parakeet_download_service.dart`'s doc comment); Parakeet just has no
/// `extracting` phase (single-archive extraction is a whisper-only step).
DownloadPhase _parakeetPhaseAsDownloadPhase(ParakeetDownloadPhase phase) =>
    switch (phase) {
      ParakeetDownloadPhase.idle => DownloadPhase.idle,
      ParakeetDownloadPhase.downloading => DownloadPhase.downloading,
      ParakeetDownloadPhase.verifying => DownloadPhase.verifying,
      ParakeetDownloadPhase.done => DownloadPhase.done,
      ParakeetDownloadPhase.error => DownloadPhase.error,
    };

// ---------------------------------------------------------------------------
// Download status — progress / error / success / download button
// ---------------------------------------------------------------------------

class _ModelStepDownloadStatus extends StatelessWidget {
  const _ModelStepDownloadStatus({
    required this.phase,
    required this.progressPercent,
    required this.errorMessage,
    required this.isDownloading,
    required this.isError,
    required this.isDone,
    required this.isDark,
    required this.accent,
    required this.accentGradient,
    required this.sizeLabel,
    required this.l10n,
    required this.onStartDownload,
  });

  final DownloadPhase phase;
  final int progressPercent;
  final String? errorMessage;
  final bool isDownloading;
  final bool isError;
  final bool isDone;
  final bool isDark;
  final Color accent;
  final LinearGradient accentGradient;
  final String sizeLabel;
  final L10n l10n;
  final VoidCallback onStartDownload;

  @override
  Widget build(BuildContext context) {
    if (isDownloading) {
      return _DownloadProgress(
        phase: phase,
        progress: progressPercent / 100.0,
        isDark: isDark,
        accent: accent,
        l10n: l10n,
      );
    }
    if (isError) {
      return _DownloadError(
        message: errorMessage,
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
              fontSize: WpTypography.subheading,
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
        label: '${l10n.qualityTierDownloadAndContinue} ($sizeLabel)',
        gradient: accentGradient,
        onPressed: onStartDownload,
      ),
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
                fontSize: WpTypography.small,
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

// ---------------------------------------------------------------------------
// Engine card — shows engine name, description, size, recommended badge,
// selected/disabled state. Two of these (Parakeet, Whisper) form the whole
// choice — no tier cards, no "choose a different level" expander.
// ---------------------------------------------------------------------------

class _EngineCard extends StatefulWidget {
  const _EngineCard({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.sizeLabel,
    required this.isRecommended,
    required this.isSelected,
    required this.isDisabled,
    required this.disabledReason,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final String sizeLabel;
  final bool isRecommended;
  final bool isSelected;
  final bool isDisabled;
  final String? disabledReason;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_EngineCard> createState() => _EngineCardState();
}

class _EngineCardState extends State<_EngineCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final isTappable = !widget.isDisabled;
    final borderColor = widget.isSelected
        ? accent
        : (_hovered && isTappable)
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
    final textMuted = widget.isDark
        ? WpColorsDark.textMuted
        : WpColorsLight.textMuted;
    final opacity = widget.isDisabled ? 0.5 : 1.0;

    return Semantics(
      button: isTappable,
      label: widget.label,
      enabled: isTappable,
      selected: widget.isSelected,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: isTappable
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: isTappable ? widget.onTap : null,
          child: Opacity(
            opacity: opacity,
            child: AnimatedContainer(
              duration: WpMotion.durationFor(context, WpMotion.fast),
              curve: WpMotion.defaultCurve,
              padding: const EdgeInsets.all(WpSpacing.md),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? accent.withValues(alpha: 0.08)
                    : (_hovered && isTappable)
                    ? accent.withValues(alpha: 0.05)
                    : surface.withValues(alpha: 0.5),
                border: Border.all(
                  color: borderColor,
                  width: widget.isSelected ? 1.5 : 1,
                ),
                borderRadius: WpRadius.borderMd,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(widget.icon, size: 22, color: accent),
                  const SizedBox(width: WpSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.label,
                              style: TextStyle(
                                fontSize: WpTypography.subheading,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                            if (widget.isRecommended && !widget.isDisabled) ...[
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
                                  L10n.of(context).onboardingModelRecommended,
                                  style: TextStyle(
                                    fontSize: WpTypography.micro,
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
                          widget.description,
                          style: TextStyle(
                            fontSize: WpTypography.small,
                            color: textSecondary,
                            height: 1.3,
                          ),
                        ),
                        if (widget.isDisabled &&
                            widget.disabledReason != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                LucideIcons.info,
                                size: 12,
                                color: textMuted,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.disabledReason!,
                                  style: TextStyle(
                                    fontSize: WpTypography.caption,
                                    color: textMuted,
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
                    widget.sizeLabel,
                    style: TextStyle(
                      fontSize: WpTypography.small,
                      fontWeight: FontWeight.w500,
                      color: textSecondary,
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
        Text(
          label,
          style: TextStyle(fontSize: WpTypography.small, color: textSecondary),
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
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    color: errorColor,
                  ),
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
              style: TextStyle(
                fontSize: WpTypography.body,
                color: textSecondary,
              ),
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
/// Purely informational: the user keeps full access to both engines and the
/// cloud option. It only concerns the Whisper branch's compute backend —
/// Parakeet is always CPU-only, so this doesn't change its speed.
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
              style: TextStyle(fontSize: WpTypography.small, color: infoColor),
            ),
          ),
        ],
      ),
    );
  }
}
