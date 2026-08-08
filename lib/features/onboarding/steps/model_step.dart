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
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_hero_button.dart';
import '../../settings/settings_widgets.dart' show kSettingRowInset;

/// Widget keys exposed for testing. Kept in one place so tests and production
/// code agree on the contract.
@visibleForTesting
const kModelStepGpuCpuFallbackKey = Key('modelStepGpuCpuFallbackNotice');
@visibleForTesting
const kModelStepEngineParakeetCardKey = Key('modelStepEngineParakeetCard');
@visibleForTesting
const kModelStepEngineWhisperCardKey = Key('modelStepEngineWhisperCard');

/// On-device speech recognition setup — the content of the Model onboarding
/// page (the page owns the heading; see the overlay's page composition).
///
/// A two-way choice presented in plain language, no engine/tier/model
/// jargon: "Fast & European" (the Parakeet engine) vs. "All 99 Languages"
/// (the Whisper engine). The app auto-recommends one card via
/// [recommendEngine], driven by the dictation language (defaulted from the
/// Welcome step's UI locale) and, for the Whisper branch only, hardware —
/// Parakeet is faster than Whisper on every machine, so hardware never rules
/// it out; only the dictation language can. The user can override the
/// recommendation by tapping the other card.
///
/// Content only — navigation (Back/Next) is owned by the onboarding shell
/// and never gated on the download. The engine choice therefore persists as
/// soon as the selected engine's model is confirmed on disk (recommendation
/// resolving against an already-installed model, a download completing, or
/// the user switching to an engine whose model is already installed) instead
/// of on a step-local Next tap, so leaving the page can never lose a
/// downloaded selection.
class ModelStep extends ConsumerStatefulWidget {
  const ModelStep({super.key});

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

  /// The Whisper model id this user already has configured, captured once at
  /// hardware-detection time — `null` while nothing is configured yet, which
  /// is when the tier default applies instead.
  ///
  /// Exists because the hardware-derived tier and a deliberately chosen model
  /// are two different answers: someone on an 8-GB GPU whose tier resolves to
  /// Premium may still have picked Medium on purpose (faster, quieter fans),
  /// and merely *looking* at this page must not trade the second for the
  /// first. See [_effectiveWhisperModel].
  String? _configuredWhisperModelId;

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
    final configuredEngine = OnDeviceEngine.fromValue(settings.stt.engine);
    final configuredModelId = settings.stt.model;
    // Does this user already have an engine/model of their own, or is the
    // persisted state still the factory default? [SttSettings] carries no
    // "unset" marker (`engine` defaults to whisper, `model` to
    // whisper-medium), so the answer comes from two independent signals,
    // either of which is sufficient:
    //
    //  * Onboarding already completed — then everything in settings is this
    //    user's own state by definition. This is the branch that carries the
    //    manually reopened flow, and it is deliberately the race-free one:
    //    it needs no result from the download service's async disk scan.
    //  * The persisted engine's model is on disk — covers the interrupted
    //    first run that is resumed after a download already finished, where
    //    `onboardingCompleted` is still false.
    final configured =
        settings.onboarding.onboardingCompleted ||
        _engineModelInstalled(configuredEngine, configuredModelId);
    setState(() {
      _gpu = gpu;
      _recommendation = rec;
      _whisperTier =
          rec.tier ?? recommendTier(gpu.vramMB ?? 0, vendor: gpu.vendor);
      _configuredWhisperModelId =
          configured && configuredEngine == OnDeviceEngine.whisper
          ? configuredModelId
          : null;
      // Deliberately *not* filtered through [_parakeetEligible]: a configured
      // engine is preselected even where the recommendation would rule it
      // out, because silently switching it is exactly the overwrite this
      // guards against. The recommendation stays visible on the other card
      // and is one tap away.
      _selectedEngine ??= configured ? configuredEngine : rec.engine;
      _hwDetected = true;
    });
    // Resume case: the recommended engine's model may already be on disk
    // (e.g. an interrupted onboarding after a completed download). Persist
    // right away so the visible "Model ready" state matches settings even
    // if the user immediately continues.
    _maybePersistSelection();
  }

  /// Whether [engine]'s model is confirmed on disk right now — for Whisper,
  /// specifically [whisperModelId] rather than whatever the tier resolves to.
  bool _engineModelInstalled(OnDeviceEngine engine, String whisperModelId) {
    switch (engine) {
      case OnDeviceEngine.whisper:
        return ref
            .read(modelDownloadProvider)
            .downloadedModels
            .contains(whisperModelId);
      case OnDeviceEngine.parakeet:
        final dl = ref.read(parakeetDownloadProvider);
        return dl.installed || dl.phase == ParakeetDownloadPhase.done;
    }
  }

  /// The Whisper model this step operates on: the configured one where the
  /// user already has one, the hardware tier's otherwise.
  ///
  /// Every whisper-shaped decision goes through here — the ready check, the
  /// card's size label, what the download button fetches, and what gets
  /// persisted — so the four can never disagree about *which* model this page
  /// is talking about.
  SttModelInfo get _effectiveWhisperModel {
    final configured = _configuredWhisperModelId;
    if (configured != null) {
      final model = findSttModel(configured);
      if (model != null) return model;
    }
    return bestModelForTier(_whisperTier ?? QualityTier.balanced);
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
    // Switching to an engine whose model is already installed is a complete
    // decision — persist immediately (see class doc).
    _maybePersistSelection();
  }

  void _startDownload() {
    switch (_selectedEngine) {
      case OnDeviceEngine.whisper:
        ref
            .read(modelDownloadProvider.notifier)
            .downloadModel(_effectiveWhisperModel.id);
      case OnDeviceEngine.parakeet:
        ref.read(parakeetDownloadProvider.notifier).downloadBundle();
      case null:
        break;
    }
  }

  /// Whether the selected engine's model is confirmed on disk right now.
  /// Reads the download providers directly so the check works outside build
  /// (selection taps, hardware-detection completion, download listeners).
  bool _selectedEngineDone() {
    switch (_selectedEngine) {
      case OnDeviceEngine.whisper:
        final dl = ref.read(modelDownloadProvider);
        return dl.phase == DownloadPhase.done ||
            dl.downloadedModels.contains(_effectiveWhisperModel.id);
      case OnDeviceEngine.parakeet:
        final dl = ref.read(parakeetDownloadProvider);
        return dl.phase == ParakeetDownloadPhase.done || dl.installed;
      case null:
        return false;
    }
  }

  /// Persists the chosen engine (+ Whisper's resolved model) once it is
  /// actually on disk. No-op otherwise, so this is safe to call from every
  /// "the ready-state may have just changed" site. Idempotent — repeated
  /// calls write the same values.
  ///
  /// Writes nothing at all when the values already match what is persisted.
  /// That is the difference between "idempotent" and "silent": entering and
  /// leaving this page without touching anything must leave settings
  /// untouched, not re-save them.
  void _maybePersistSelection() {
    final engine = _selectedEngine;
    if (engine == null || !_selectedEngineDone()) return;
    final modelId = engine == OnDeviceEngine.whisper
        ? _effectiveWhisperModel.id
        : null; // leave the persisted whisper model untouched
    final current = ref.read(settingsProvider).value;
    if (current != null &&
        current.stt.engine == engine.value &&
        (modelId == null || current.stt.model == modelId)) {
      return;
    }
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(sttEngine: engine.value, sttModel: modelId),
        );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    // Persist the selection the moment its download completes — the shell's
    // Next button is generic and must not need to know about engines.
    ref.listen(modelDownloadProvider, (prev, next) {
      if (next.phase == DownloadPhase.done &&
          prev?.phase != DownloadPhase.done) {
        _maybePersistSelection();
      }
    });
    ref.listen(parakeetDownloadProvider, (prev, next) {
      if (next.phase == ParakeetDownloadPhase.done &&
          prev?.phase != ParakeetDownloadPhase.done) {
        _maybePersistSelection();
      }
    });
    final whisperDl = ref.watch(modelDownloadProvider);
    final parakeetDl = ref.watch(parakeetDownloadProvider);

    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;

    final whisperModel = _effectiveWhisperModel;

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
    // Reuses `_selectedEngineDone()` (the same "is it actually on disk"
    // check `_maybePersistSelection` gates on) instead of re-deriving it
    // here — this predicate now decides whether the selection persists at
    // all, so keeping one definition matters more than it used to.
    final isDone = _selectedEngineDone();
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

    // Content only, no title: the Model page owns the heading (see the
    // overlay's page composition), which is the same string this block used
    // to carry as a section label. The tight vertical rhythm below is kept
    // from the merged page — the download-error branch is the tall one, and
    // it still has to fit the fixed 1100×720 window.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          const SizedBox(height: WpSpacing.xxs),
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
          // Two engines side by side — a deliberate 50/50 layout so the
          // choice reads as two equal alternatives, not a ranked list.
          // IntrinsicHeight + stretch keeps both cards the same height even
          // when one description wraps to more lines than the other.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  // loam-ignore: a11y-interactive-semantics – semantics provided in _EngineCardState.build
                  child: _EngineCard(
                    key: kModelStepEngineParakeetCardKey,
                    icon: LucideIcons.zap,
                    label: l10n.onboardingModelEngineParakeetLabel,
                    description: l10n.onboardingModelEngineParakeetDesc,
                    sizeLabel: parakeetModelSizeLabel,
                    isRecommended:
                        _recommendation?.engine == OnDeviceEngine.parakeet,
                    isSelected: _selectedEngine == OnDeviceEngine.parakeet,
                    isDisabled: !_parakeetEligible,
                    disabledReason:
                        l10n.onboardingModelEngineUnsupportedLanguage,
                    isDark: isDark,
                    onTap: () => _selectEngine(OnDeviceEngine.parakeet),
                  ),
                ),
                const SizedBox(width: WpSpacing.md),
                Expanded(
                  // loam-ignore: a11y-interactive-semantics – semantics provided in _EngineCardState.build
                  child: _EngineCard(
                    key: kModelStepEngineWhisperCardKey,
                    icon: LucideIcons.globe,
                    label: l10n.onboardingModelEngineWhisperLabel,
                    description: l10n.onboardingModelEngineWhisperDesc,
                    sizeLabel: whisperModel.sizeLabel,
                    isRecommended:
                        _recommendation?.engine == OnDeviceEngine.whisper,
                    isSelected: _selectedEngine == OnDeviceEngine.whisper,
                    isDisabled: false,
                    disabledReason: null,
                    isDark: isDark,
                    onTap: () => _selectEngine(OnDeviceEngine.whisper),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: WpSpacing.xs),

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

        const SizedBox(height: WpSpacing.xxs),
        // "You can change this later in Settings" also covers the cloud
        // path: the former "use cloud instead" escape link was a pure
        // navigation affordance and is gone with the shell-owned Next —
        // cloud users simply continue without downloading.
        Padding(
          padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
          child: Text(
            l10n.onboardingModelChangeLater,
            textAlign: TextAlign.start,
            style: TextStyle(fontSize: WpTypography.small, color: textMuted),
          ),
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
      // loam-ignore: a11y-interactive-semantics – semantics provided in WpHeroButton.build
      child: WpHeroButton(
        label: '${l10n.qualityTierDownloadAndContinue} ($sizeLabel)',
        gradient: accentGradient,
        onPressed: onStartDownload,
        // Full-height CTA again: the shortened padding here was paid for by
        // the merged Model & Hotkey page, which no longer exists — the model
        // page has ~150 px of spare height now, so the primary action of the
        // page has no reason to sit below the 48-px touch-target floor.
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
              padding: const EdgeInsets.all(WpSpacing.sm),
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
                // Matches the borderLg surfaces the rest of the flow uses.
                // The accent ring on the selected card deliberately stays:
                // unlike page 1's beat highlight (emphasis), this is a binary
                // selection control, and the reference rings its active tile
                // too (reference-conductor/SCR-20260804-kayx.png, Theme).
                borderRadius: WpRadius.borderLg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Engine icon, name, "recommended" badge and selection
                  // check share one line (dense-page geometry); the quiet
                  // check fades in on the right when this card is the current
                  // selection — the accent border alone can blur together
                  // with the badge when both cards sit side by side.
                  Row(
                    children: [
                      Icon(widget.icon, size: 18, color: accent),
                      const SizedBox(width: WpSpacing.xs),
                      // Expanded, and the only widget on this line that takes
                      // free space: with `Flexible` title + `Flexible` badge +
                      // a `Spacer`, the three split the width between them and
                      // the recommended card's title silently ellipsised
                      // ("Schnell & e…") on a card wide enough to show it in
                      // full. The badge is bounded to its intrinsic width
                      // below, so what is left over is the title's.
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: WpTypography.subheading,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      if (widget.isRecommended && !widget.isDisabled) ...[
                        const SizedBox(width: WpSpacing.xs),
                        // Inflexible and capped: the pill takes its intrinsic
                        // width, so it can never claim a share of the free
                        // space the title needs. The cap plus scale-down is
                        // what keeps a long localized badge (or an enlarged
                        // text scale) shrinking rather than overflowing the
                        // shared line — the job the old `Flexible` did, minus
                        // the appetite.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 128),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: WpSpacing.xs,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.15),
                                borderRadius: WpRadius.borderFull,
                              ),
                              child: Text(
                                L10n.of(context).onboardingModelRecommended,
                                // Single line always — under tight width the
                                // enclosing FittedBox scales the pill down
                                // instead of the text wrapping (wrapping
                                // would inflate the IntrinsicHeight-coupled
                                // card pair).
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: WpTypography.caption,
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: WpSpacing.xs),
                      ],
                      AnimatedOpacity(
                        opacity: widget.isSelected ? 1.0 : 0.0,
                        duration: WpMotion.durationFor(context, WpMotion.fast),
                        curve: WpMotion.defaultCurve,
                        child: Icon(
                          LucideIcons.circleCheck,
                          size: WpIconSize.sm,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: WpSpacing.xs),
                  Text(
                    widget.description,
                    style: TextStyle(
                      fontSize: WpTypography.small,
                      color: textSecondary,
                      height: 1.3,
                    ),
                  ),
                  if (widget.isDisabled && widget.disabledReason != null) ...[
                    const SizedBox(height: WpSpacing.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.info, size: 12, color: textMuted),
                        const SizedBox(width: WpSpacing.xxs),
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
                  // Pin the size label to the bottom edge so both cards'
                  // download sizes align and compare at a glance, regardless
                  // of how many lines each description wraps to.
                  const SizedBox(height: WpSpacing.xs),
                  const Spacer(),
                  Text(
                    widget.sizeLabel,
                    style: TextStyle(
                      fontSize: WpTypography.small,
                      fontWeight: FontWeight.w500,
                      color: textMuted,
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
        WpButton(
          label: l10n.overlayRetry,
          variant: WpButtonVariant.secondary,
          tone: WpButtonTone.neutral,
          icon: LucideIcons.refreshCw,
          expanded: true,
          onPressed: onRetry,
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
    // Frameless, like the recording-duration note on the same page: a filled
    // and outlined banner gave a purely informational line the weight of a
    // warning, and it was the fourth box competing on this page. Dropping the
    // frame also returns 10 px (2 px border + 2x4 px padding) to the tightest
    // height budget in the flow.
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.info, size: 14, color: infoColor),
          ),
          const SizedBox(width: WpSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: WpTypography.small,
                color: infoColor,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
