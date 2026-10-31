import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/engine_recommendation.dart';
import '../../../services/speech_recommendation.dart';
import '../../../services/hardware_info_service.dart' as hw;
import '../../../services/model_hardware_telemetry.dart';
import '../../../services/download_error_kind.dart';
import '../../../services/free_disk_space.dart';
import '../../../services/model_download_service.dart';
import '../../../services/path_service.dart' show sttDir;
import '../../../services/stt_parakeet/parakeet_download_service.dart';
import '../../../widgets/wp_progress_bar.dart';
import '../../../widgets/dialog.dart' show WpDialogCta, showWpConfirmDialog;
import '../../../widgets/model_ram_precheck_dialog.dart';
import '../../../widgets/recommendation_reason.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../settings/settings_widgets.dart' show kSettingRowInset;
import '../stt_model_readiness.dart';

/// Widget keys exposed for testing. Kept in one place so tests and production
/// code agree on the contract.
@visibleForTesting
const kModelStepGpuCpuFallbackKey = Key('model-step-gpu-cpu-fallback-notice');
@visibleForTesting
const kModelStepEngineParakeetCardKey = Key('model-step-engine-parakeet-card');
@visibleForTesting
const kModelStepEngineWhisperCardKey = Key('model-step-engine-whisper-card');
@visibleForTesting
const kModelStepDownloadCancelKey = Key(_kModelStepDownloadCancelId);
const _kModelStepDownloadCancelId = 'onboarding-speech-download-cancel';
@visibleForTesting
const kModelStepNextBlockedKey = Key('model-step-next-blocked');
@visibleForTesting
const kModelStepRecommendationReasonKey = Key(
  'model-step-recommendation-reason',
);
@visibleForTesting
const kModelStepUseCloudKey = Key(_kModelStepUseCloudId);
const _kModelStepUseCloudId = 'onboarding-speech-use-cloud';
@visibleForTesting
const kModelStepUseLocalKey = Key(_kModelStepUseLocalId);
const _kModelStepUseLocalId = 'onboarding-speech-use-local';

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
/// soon as the user picks an engine or starts its download, and again when the
/// selected engine's model is confirmed on disk. The preflight reads the saved
/// engine, so a choice must be the active one before its download finishes
/// (UIA-RT-01). On a first run with nothing configured the recommendation is
/// saved as well, so leaving without a download still leaves the recommended
/// engine and tier active (UIA-RT-03, E1a); a configured choice is never
/// overwritten.
class ModelStep extends ConsumerStatefulWidget {
  const ModelStep({super.key, this.nextBlocked = false});

  /// Whether the shell's Next is held back because no model is installed and
  /// none is downloading (UIA-RT-01). The reason is then shown as visible
  /// text on the page, not only as a disabled button.
  final bool nextBlocked;

  @override
  ConsumerState<ModelStep> createState() => _ModelStepState();
}

class _ModelStepState extends ConsumerState<ModelStep> {
  OnDeviceEngine? _selectedEngine;
  EngineRecommendation? _recommendation;

  /// The hardware facts behind [_recommendation], for its reason line.
  SpeechRecommendation? _recommendationFacts;

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

  /// Whether the user picked an engine on this page (a card tap, or starting
  /// its download). A pick is saved at once; the page preselecting one is
  /// saved only while nothing is configured, see [_saveRecommendation].
  bool _engineChosen = false;

  /// Whether nothing is configured yet (first run, no model of its own on
  /// disk), so the preselected recommendation is saved too (UIA-RT-03, E1a).
  bool _saveRecommendation = false;

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
    // The Whisper branch of [_engineModelInstalled] reads
    // [modelDownloadProvider]'s state directly — that provider's initial
    // disk scan runs deferred (off the build frame), so without this wait
    // an already-downloaded model can lose the race and get read as "not
    // installed" here, permanently (this method runs once, in initState).
    await ref.read(modelDownloadProvider.notifier).awaitInitialScan();
    if (!mounted) return;
    // The same recommendation Settings shows (UIA-RT-03, MV-04).
    final facts = await ref.read(speechRecommendationProvider.future);
    if (!mounted) return;
    final rec = facts.recommendation;
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
    final parakeetEligible =
        rec.engine == OnDeviceEngine.parakeet ||
        parakeetRecommendedFor(
          recommendationLanguages(
            sttLanguageCode: settings.sttLanguageCode,
            systemLanguages: ref.read(systemLanguageCodesProvider),
            uiLocale: settings.locale,
          ),
        );
    setState(() {
      _gpu = gpu;
      _recommendation = rec;
      _parakeetEligible = parakeetEligible;
      _recommendationFacts = facts;
      // Independent of the engine: a user who overrides Parakeet by hand gets
      // the tier this machine warrants, from the same rule as Settings.
      _whisperTier = rec.whisper.tier;
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
      _saveRecommendation = !configured;
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
  /// Parakeet writes every language this user dictates in. It stays a choice
  /// when a premium Whisper wins the recommendation for those languages, so
  /// the card must not read "language not supported" then.
  bool _parakeetEligible = false;

  void _selectEngine(OnDeviceEngine engine) {
    if (engine == OnDeviceEngine.parakeet && !_parakeetEligible) return;
    setState(() {
      _selectedEngine = engine;
      _engineChosen = true;
    });
    // A tap is a complete decision — persist immediately (see class doc).
    _maybePersistSelection();
  }

  void _cancelDownload() {
    switch (_selectedEngine) {
      case OnDeviceEngine.whisper:
        ref.read(modelDownloadProvider.notifier).cancelDownload();
      case OnDeviceEngine.parakeet:
        ref.read(parakeetDownloadProvider.notifier).cancelDownload();
      case null:
        break;
    }
  }

  Future<void> _startDownload() async {
    final engine = _selectedEngine;
    if (engine == null) return;
    // Warn before a download the disk cannot hold, instead of letting it
    // fail hundreds of MB later (UIA-ONB-09). Soft, like the Smart Mode RAM
    // check: the probe can be wrong (quotas, network drives), so the user
    // may still go ahead. An unknown answer is treated as enough.
    final needed = switch (engine) {
      OnDeviceEngine.whisper => _effectiveWhisperModel.sizeBytes,
      OnDeviceEngine.parakeet => parakeetDownloadBytes(
        gpuWanted: parakeetGpuWantedForSetting(
          ref.read(settingsProvider).value?.behavior.gpuAcceleration,
        ),
      ),
    };
    final free = await ref.read(freeDiskSpaceProbeProvider)(sttDir());
    if (!mounted) return;
    if (free != null && free < needed) {
      final l10n = L10n.of(context);
      final proceed = await showWpConfirmDialog(
        context: context,
        title: l10n.onboardingModelDiskSpaceTitle,
        message: l10n.onboardingModelDiskSpaceBody(
          formatModelSizeLabel(needed),
          formatModelSizeLabel(free),
        ),
        confirmLabel: l10n.onboardingModelDiskSpaceContinue,
        cancelLabel: l10n.actionCancel,
        cta: WpDialogCta.hero,
      );
      if (!proceed || !mounted || _selectedEngine != engine) return;
    }
    // The model loads right after its download, so the same RAM precheck as
    // in Settings applies to this explicit choice.
    final base = ref.read(settingsProvider).value;
    if (base != null) {
      final next = engine == OnDeviceEngine.whisper
          ? base.copyWith(
              sttEngine: engine.value,
              sttModel: _effectiveWhisperModel.id,
            )
          : base.copyWith(sttEngine: engine.value);
      final ramProceed = await confirmSttSettingsRam(
        context: context,
        settings: next,
      );
      if (!ramProceed || !mounted || _selectedEngine != engine) return;
    }
    // Saved before the download starts, so the engine is the active one for
    // the whole time it is downloading (UIA-RT-01).
    ref
        .read(modelHardwareTelemetryProvider)
        .modelChosen(engine: engine, whisperModelId: _effectiveWhisperModel.id);
    _engineChosen = true;
    _maybePersistSelection();
    switch (engine) {
      case OnDeviceEngine.whisper:
        ref
            .read(modelDownloadProvider.notifier)
            .downloadModel(_effectiveWhisperModel.id);
      case OnDeviceEngine.parakeet:
        ref.read(parakeetDownloadProvider.notifier).downloadBundle();
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

  /// Persists the engine (+ Whisper's resolved model) once the user has chosen
  /// it, it is actually on disk, or nothing is configured yet. No-op otherwise, so this is safe to call
  /// from every "the ready-state may have just changed" site. Idempotent —
  /// repeated calls write the same values.
  ///
  /// Writes nothing at all when the values already match what is persisted.
  /// That is the difference between "idempotent" and "silent": once a choice
  /// is configured, entering and leaving this page without touching anything
  /// must leave settings untouched, not re-save them.
  void _maybePersistSelection() {
    final engine = _selectedEngine;
    if (engine == null ||
        !(_engineChosen || _saveRecommendation || _selectedEngineDone())) {
      return;
    }
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

  /// The reason line for the selected engine: the recommendation's own when
  /// the recommended engine is selected, the Whisper tier's when Whisper is
  /// picked over Parakeet by hand.
  String? _recommendationReason(L10n l10n) {
    final rec = _recommendation;
    final facts = _recommendationFacts;
    if (rec == null || facts == null) return null;
    if (_selectedEngine == rec.engine) {
      return recommendationReason(l10n, facts, rec);
    }
    if (_selectedEngine == OnDeviceEngine.whisper) {
      return recommendationReason(l10n, facts, rec.whisper);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
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

    final textMuted = WpColors.textMuted;
    final accent = WpColors.accent;

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
    final errorKind = switch (_selectedEngine) {
      OnDeviceEngine.whisper => whisperDl.errorKind,
      OnDeviceEngine.parakeet => parakeetDl.errorKind,
      null => null,
    };
    final progressPercent = switch (_selectedEngine) {
      OnDeviceEngine.whisper => whisperDl.progressPercent,
      OnDeviceEngine.parakeet => parakeetDl.progressPercent,
      null => 0,
    };
    final selectedSizeLabel = switch (_selectedEngine) {
      OnDeviceEngine.whisper => whisperModel.sizeLabel,
      OnDeviceEngine.parakeet => parakeetDownloadSizeLabel(
        gpuWanted: parakeetGpuWantedForSetting(
          ref.watch(settingsProvider).value?.behavior.gpuAcceleration,
        ),
      ),
      null => '',
    };

    // Content only, no title: the Model page owns the heading (see the
    // overlay's page composition), which is the same string this block used
    // to carry as a section label.
    //
    // The rhythm below is still the tightest in the flow — the download-error
    // branch is the tall one and it has to fit the fixed 1100×720 window in
    // every locale — but no gap here goes below `sm` any more. The former
    // `xxs` (4 px) blocks were unique to this page and read as stuck
    // together, which made the page denser than every other one for 8 px per
    // gap. `onboarding_overlay_test.dart` measures the error branch per
    // locale at 1100×720; that test is what bounds this rhythm.
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
        if (!_hwDetected)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WpSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: WpIconSize.lg,
                  height: WpIconSize.lg,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(height: WpSpacing.sm),
                Text(
                  l10n.onboardingModelDetectingHardware,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    color: WpColors.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else ...[
          // Two engines side by side — a deliberate 50/50 layout so the
          // choice reads as two equal alternatives, not a ranked list.
          // IntrinsicHeight + stretch keeps both cards the same height even
          // when one description wraps to more lines than the other.
          //
          // Start-inset like the heading above and the footnote below: every
          // text block on this page starts `kSettingRowInset` into the frame
          // (the shared reading edge headings and frameless settings rows sit
          // on), and the cards used to start at the bare frame edge — 12 px
          // left of everything else, which read as the cards overhanging the
          // page. The same inset wraps the fallback notice and the download
          // status below so all three keep sharing the cards' half-widths.
          Padding(
            padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _EngineCardState.build
                    child: _EngineCard(
                      key: kModelStepEngineParakeetCardKey,
                      testId: 'onboarding-speech-engine-parakeet',
                      icon: LucideIcons.zap,
                      label: l10n.onboardingModelEngineParakeetLabel,
                      description: l10n.onboardingModelEngineParakeetDesc,
                      sizeLabel: parakeetDownloadSizeLabel(
                        gpuWanted: parakeetGpuWantedForSetting(
                          ref
                              .watch(settingsProvider)
                              .value
                              ?.behavior
                              .gpuAcceleration,
                        ),
                      ),
                      languagesLabel: l10n.onboardingModelFactLanguagesParakeet,
                      speedLabel: l10n.onboardingModelFactSpeedParakeet,
                      isRecommended:
                          _recommendation?.engine == OnDeviceEngine.parakeet,
                      isSelected: _selectedEngine == OnDeviceEngine.parakeet,
                      isDisabled: !_parakeetEligible,
                      disabledReason:
                          l10n.onboardingModelEngineUnsupportedLanguage,
                      onTap: () => _selectEngine(OnDeviceEngine.parakeet),
                    ),
                  ),
                  const SizedBox(width: WpSpacing.lg),
                  Expanded(
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _EngineCardState.build
                    child: _EngineCard(
                      key: kModelStepEngineWhisperCardKey,
                      testId: 'onboarding-speech-engine-whisper',
                      icon: LucideIcons.globe,
                      label: l10n.onboardingModelEngineWhisperLabel,
                      description: l10n.onboardingModelEngineWhisperDesc,
                      sizeLabel: whisperModel.sizeLabel,
                      languagesLabel: l10n.onboardingModelFactLanguagesWhisper,
                      speedLabel: l10n.onboardingModelFactSpeedWhisper,
                      isRecommended:
                          _recommendation?.engine == OnDeviceEngine.whisper,
                      isSelected: _selectedEngine == OnDeviceEngine.whisper,
                      isDisabled: false,
                      disabledReason: null,
                      onTap: () => _selectEngine(OnDeviceEngine.whisper),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Why the recommendation is what it is, in one line (MV-03). The
          // same text Settings shows under its tiers.
          if (_recommendationReason(l10n) case final reason?) ...[
            const SizedBox(height: WpSpacing.xs),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: kSettingRowInset,
              ),
              child: Text(
                reason,
                key: kModelStepRecommendationReasonKey,
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: WpTypography.small,
                  color: textMuted,
                ),
              ),
            ),
          ],

          // The CPU-fallback verdict, directly under the card it is about.
          // It used to stand in front of *both* cards while applying to one
          // (Parakeet is CPU-only either way, so the notice never concerned
          // it) — read in reading order it announced a limitation and then
          // offered two choices, neither visibly the one it meant. Sitting on
          // the Whisper card's own width and start edge, it needs no wording
          // to say which engine it belongs to.
          if (_gpu?.vendor == hw.GpuVendor.none) ...[
            const SizedBox(height: WpSpacing.xs),
            // Same start inset and same `lg` gutter as the cards row above —
            // the gutter used to be `md`, which put this notice 4 px left of
            // the Whisper card's own start edge it claims to sit on.
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: kSettingRowInset,
              ),
              child: Row(
                children: [
                  const Expanded(child: SizedBox.shrink()),
                  const SizedBox(width: WpSpacing.lg),
                  Expanded(
                    child: _GpuCpuFallbackNotice(
                      key: kModelStepGpuCpuFallbackKey,
                      message: l10n.onboardingModelGpuCpuFallback,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // `xs`, not the flat `sm` this page used between all four of its
          // blocks: picking an engine and fetching that engine's model are one
          // subject, so they bind. The rank step comes after the download
          // block, not between it and the choice it belongs to (M2).
          const SizedBox(height: WpSpacing.xs),

          // Download status on the *selected* card's half, not the row's full
          // width and not always the left half: the status (CTA, progress,
          // error, "Model ready") is about the engine the user just picked,
          // and it used to render left-aligned even with Whisper — the right
          // card — selected, visibly belonging to the wrong card. Same
          // spacer-Row geometry as [_GpuCpuFallbackNotice] above (same start
          // inset, same `lg` gutter), so the status shares its card's exact
          // start edge. With no engine selected yet the status renders a
          // disabled-looking empty CTA on the left half, which is where the
          // recommended card (Parakeet) sits — acceptable for a state the
          // hydration logic leaves within one frame.
          Padding(
            padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
            child: Row(
              children: [
                if (_selectedEngine == OnDeviceEngine.whisper) ...[
                  const Expanded(child: SizedBox.shrink()),
                  const SizedBox(width: WpSpacing.lg),
                ],
                Expanded(
                  child: _ModelStepDownloadStatus(
                    phase: selectedPhase,
                    progressPercent: progressPercent,
                    errorKind: errorKind,
                    isDownloading: isDownloading,
                    isError: isError,
                    isDone: isDone,
                    accent: accent,
                    sizeLabel: selectedSizeLabel,
                    l10n: l10n,
                    onStartDownload: _startDownload,
                    onCancelDownload: _cancelDownload,
                  ),
                ),
                if (_selectedEngine != OnDeviceEngine.whisper) ...[
                  const SizedBox(width: WpSpacing.lg),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ],
            ),
          ),
        ],

        // `lg` against the `xs` above: this is the page's one gap that
        // separates two subjects rather than spacing items inside one — the
        // choice-and-download block ends here and a standing footnote begins.
        // Four blocks of four different ranks used to be stacked on one flat
        // `sm`, which is what made the page read as an undifferentiated
        // column (M2).
        const SizedBox(height: WpSpacing.lg),
        const _CloudSttChoice(),
        if (widget.nextBlocked) ...[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
            child: Text(
              l10n.onboardingModelNextBlocked,
              key: kModelStepNextBlockedKey,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: WpTypography.small,
                fontWeight: FontWeight.w600,
                color: WpColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
        ],
        // "You can change this later in Settings" also covers the cloud
        // path: the former "use cloud instead" escape link was a pure
        // navigation affordance and is gone with the shell-owned Next. Cloud
        // users continue without downloading once an API key is saved
        // (UIA-MDL-GATE, see onboardingModelStepCanAdvanceProvider).
        // Parakeet has no quality tiers to adjust later, so the hint is Whisper's.
        if (_selectedEngine == OnDeviceEngine.whisper)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
            child: Text(
              // A choice, not a fixed answer: the preselected model is the
              // default and larger ones can be switched to later (MP-2).
              l10n.onboardingModelDefaultHint,
              textAlign: TextAlign.start,
              style: TextStyle(fontSize: WpTypography.small, color: textMuted),
            ),
          ),
      ],
    );
  }
}

/// The cloud alternative to a local model (UIA-MDL-GATE G1a): only a chosen
/// cloud provider with a saved key opens the gate, so a saved key is offered
/// as an explicit choice while the local engine is chosen, and a chosen cloud
/// provider can be switched back. Nothing switches without a tap.
class _CloudSttChoice extends ConsumerWidget {
  const _CloudSttChoice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value;
    final offered = ref.watch(onboardingOfferedCloudSttProvider);
    final inUse = ref.watch(onboardingCloudSttKeyProvider);
    if (settings == null || (offered == null && !inUse)) {
      return const SizedBox.shrink();
    }
    final provider = inUse ? settings.sttProviderType : offered!;
    final String text;
    final Widget button;
    if (inUse) {
      text = l10n.onboardingModelCloudInUse(provider.value);
      button = WpButton(
        testId: _kModelStepUseLocalId,
        label: l10n.onboardingModelUseLocal,
        variant: WpButtonVariant.ghost,
        tone: WpButtonTone.neutral,
        icon: LucideIcons.hardDrive,
        onPressed: () => _choose(ref, SttProviderType.onDevice),
      );
    } else {
      text = l10n.onboardingModelCloudKeySaved(provider.value);
      button = WpButton(
        testId: _kModelStepUseCloudId,
        label: l10n.onboardingModelUseCloud(provider.value),
        variant: WpButtonVariant.secondary,
        icon: LucideIcons.cloud,
        onPressed: () => _choose(ref, provider),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: kSettingRowInset,
        bottom: WpSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: WpTypography.small,
              color: WpColors.textPrimary,
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          button,
        ],
      ),
    );
  }

  void _choose(WidgetRef ref, SttProviderType provider) {
    ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => s.copyWith(sttProvider: provider.value));
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
    required this.errorKind,
    required this.isDownloading,
    required this.isError,
    required this.isDone,
    required this.accent,
    required this.sizeLabel,
    required this.l10n,
    required this.onStartDownload,
    required this.onCancelDownload,
  });

  final DownloadPhase phase;
  final int progressPercent;
  final DownloadErrorKind? errorKind;
  final bool isDownloading;
  final bool isError;
  final bool isDone;
  final Color accent;
  final String sizeLabel;
  final L10n l10n;
  final VoidCallback onStartDownload;
  final VoidCallback onCancelDownload;

  @override
  Widget build(BuildContext context) {
    if (isDownloading) {
      return _DownloadProgress(
        phase: phase,
        progress: progressPercent / 100.0,
        accent: accent,
        l10n: l10n,
        onCancel: onCancelDownload,
      );
    }
    if (isError) {
      return _DownloadError(
        kind: errorKind,
        l10n: l10n,
        onRetry: onStartDownload,
      );
    }
    if (isDone) {
      // Accent, not `success` (Ticket 15, *The Earned-Green Rule*). The
      // download is finished *and stays finished*: re-open the page and the
      // row is still here, reporting a fact rather than an event. Green is
      // the app's one word for "that worked just now", and a permanent row
      // wearing it leaves nothing to say it with.
      final ready = WpColors.accent;
      // Same floating-surface + edge-highlight pill material as the
      // mic-permission chip and the Auto-Paste status card (Ticket 04) — not
      // tappable, so no InkWell, just the material.
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: WpColors.floatingSurface,
            borderRadius: WpRadius.borderFull,
            border: Border.all(color: WpColors.cardEdgeHighlight),
          ),
          // Start-aligned like every other status row in the app (settings,
          // history and notes rows are all CrossAxisAlignment.start; no
          // centred status state exists anywhere else) and like the
          // full-width CTA, progress bar and error banner that occupy this
          // same spot.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.circleCheck, size: WpIconSize.sm, color: ready),
              const SizedBox(width: WpSpacing.xs),
              Text(
                l10n.modelReady,
                style: TextStyle(
                  fontSize: WpTypography.subheading,
                  fontWeight: FontWeight.w600,
                  color: ready,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // One card's width, not the row's (M6). At `double.infinity` this was
    // 720 px wide — twice the width of the card whose model it downloads, and
    // the widest button anywhere in the flow, including the shell's own Next.
    // A CTA that out-measures the thing it acts on stops reading as that
    // thing's action. The halving itself moved up into [ModelStep]'s build
    // (the spacer Row that sides every download-status state with the
    // *selected* card), so here the CTA simply fills the half it is given.
    // A `primary` WpButton, not the gradient WpHeroButton it used to be
    // (Ticket 15, *The One-Loud-Action Rule*). The shell's Next button is a
    // hero wearing the identical `accentWarmGradient` and sits directly below
    // this one; two heroes on one page is two answers to "what am I supposed
    // to do here", which is the same as none. Rank now reads off the
    // components: gradient hero for the flow CTA in the chrome, filled accent
    // button for the page's own action.
    return SizedBox(
      width: double.infinity,
      child: WpButton(
        testId: 'onboarding-speech-start-download',
        label: '${l10n.qualityTierDownloadAndContinue} ($sizeLabel)',
        variant: WpButtonVariant.primary,
        onPressed: onStartDownload,
        // Full-height CTA: the shortened padding here was paid for by the
        // merged Model & Hotkey page, which no longer exists — the model
        // page has ~150 px of spare height now, so the loud action of the
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

/// Every colour [_EngineCard] paints, resolved once for the current theme and
/// card state.
///
/// Out of `build` on purpose: these are pure lookups, and inlining a
/// theme-pair ternary per colour buried the card's actual structure under
/// twenty branches of palette plumbing.
///
/// A disabled card steps its text and icon down one rung on the token ladder
/// rather than wearing an opacity veil. The veil (0.5) this replaced dimmed
/// every colour on the card equally — including the `disabledReason` line,
/// the one thing that explains *why* the card cannot be picked, which is
/// already `textMuted` and landed around 1.8:1 behind it. DESIGN.md forbids
/// the veil for exactly this reason; the reason line now keeps full strength
/// and is the most readable thing on a card you cannot choose.
/// The decorative-glyph wash. A free function rather than one more lookup
/// inside [_EngineCardColors.resolve]: that factory is already at the repo's
/// cyclomatic ceiling, and this pick has nothing to do with the
/// selected/hovered/disabled state the rest of it resolves.
///
/// It read `_decorativeGlyphWash(isDark)` until 2026-08-11, and the reason
/// given was that it kept `isDark ? … : …` out of the factory. With one
/// palette there is no ternary left to keep out; what survives is the second
/// reason, which never depended on the theme pair.
Color _decorativeGlyphWash() => WpColors.decorativeGlyphWash;

/// One fact on an engine card's chip row (size, languages, speed).
class _ModelFactChip extends StatelessWidget {
  const _ModelFactChip({
    required this.label,
    required this.color,
    required this.borderColor,
    this.bold = false,
  });

  final String label;
  final Color color;
  final Color borderColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: WpRadius.borderFull,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: bold ? WpTypography.small : WpTypography.caption,
          fontWeight: bold ? FontWeight.w500 : FontWeight.normal,
          color: color,
        ),
      ),
    );
  }
}

class _EngineCardColors {
  const _EngineCardColors({
    required this.accent,
    required this.fill,
    required this.border,
    required this.badgeFill,
    required this.heroWash,
    required this.icon,
    required this.label,
    required this.description,
    required this.textMuted,
  });

  factory _EngineCardColors.resolve({
    required bool isSelected,
    required bool isHovered,
    required bool isTappable,
  }) {
    final accent = WpColors.accent;
    final surface = WpColors.floatingSurface;
    final textPrimary = WpColors.textPrimary;
    final textSecondary = WpColors.textSecondary;
    final textMuted = WpColors.textMuted;
    // The accent ladder's lowest rung (6 %) — the hover fill.
    final accentSix = WpColors.accentRowHover;
    final hovering = isHovered && isTappable;

    return _EngineCardColors(
      accent: accent,
      fill: isSelected
          ? (WpColors.accentButtonFill)
          : hovering
          ? accentSix
          // Ticket 15: the card material in its pre-composited spelling —
          // see [_PermissionStatusCard] in `auto_paste_step.dart` for why
          // onboarding takes `floatingSurface` rather than `cardFill`. Only
          // the resting rung moves; selected and hover are already tint-ladder
          // tokens and stay as they are.
          : surface,
      border: isSelected
          ? accent
          : hovering
          ? (WpColors.accentBorder30)
          : (WpColors.borderSubtle),
      badgeFill: WpColors.accentBadgeFill,
      // `decorativeGlyphWash`, not the tint ladder: the 6/12/30% rungs are
      // defined for badges, chips and borders, and a 140px glyph bleeding out
      // of the corner is none of those. It gets its own, lower category — and
      // its own alpha per theme, because equal alphas do not read equally on
      // near-black and near-white grounds (see `colors.dart`). A card you
      // cannot pick gets no wash at all: the same token swap the rest of this
      // class does for the disabled state, rather than a brand-accent graphic
      // behind deliberately muted text.
      heroWash: isTappable ? _decorativeGlyphWash() : null,
      icon: isTappable ? accent : textMuted,
      label: isTappable ? textPrimary : textSecondary,
      description: isTappable ? textSecondary : textMuted,
      textMuted: textMuted,
    );
  }

  final Color accent;
  final Color fill;
  final Color border;
  final Color badgeFill;

  /// Background wash behind the card content — `null` on a disabled card.
  final Color? heroWash;
  final Color icon;
  final Color label;
  final Color description;
  final Color textMuted;
}

class _EngineCard extends StatefulWidget {
  const _EngineCard({
    super.key,
    this.testId,
    required this.icon,
    required this.label,
    required this.description,
    required this.sizeLabel,
    required this.languagesLabel,
    required this.speedLabel,
    required this.isRecommended,
    required this.isSelected,
    required this.isDisabled,
    required this.disabledReason,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final String sizeLabel;
  final String languagesLabel;
  final String speedLabel;
  final bool isRecommended;
  final bool isSelected;
  final bool isDisabled;
  final String? disabledReason;
  final VoidCallback onTap;

  /// Stable id, exposed as the accessibility identifier of the card.
  final String? testId;

  @override
  State<_EngineCard> createState() => _EngineCardState();
}

/// Size of the washed-back engine glyph in the card's background. Deliberately
/// off the [WpIconSize] scale: that scale sizes icons the user reads or presses
/// (14/16 decorative, 20 interactive minimum, 24 standard, 32/48 hero), and
/// this is a background graphic that has to overrun the card to work at all.
const double _heroWashSize = 180;

class _EngineCardState extends State<_EngineCard> {
  bool _hovered = false;

  /// Shared with [WpFocusRing] in external-node mode: the [InkWell] keeps the
  /// only [Focus] widget (and with it Enter/Space activation), the ring only
  /// listens. See `wp_focus_ring.dart`.
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTappable = !widget.isDisabled;
    final c = _EngineCardColors.resolve(
      isSelected: widget.isSelected,
      isHovered: _hovered,
      isTappable: isTappable,
    );
    final accent = c.accent;
    final textMuted = c.textMuted;
    final iconColor = c.icon;
    final labelColor = c.label;
    final descriptionColor = c.description;
    final borderColor = c.border;

    return MergeSemantics(
      // No explicit `label:` — merging lets the card announce its own name,
      // description and download size instead of announcing the name twice
      // (once from this node, once from the `Text` below it).
      child: Semantics(
        button: isTappable,
        enabled: isTappable,
        selected: widget.isSelected,
        identifier: widget.testId,
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.lg,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              focusNode: _focusNode,
              onTap: isTappable ? widget.onTap : null,
              onHover: (hovered) => setState(() => _hovered = hovered),
              borderRadius: WpRadius.borderLg,
              // The card paints its own hover wash and the ring marks focus;
              // Material's overlays would double up under a filled child that
              // hides the splash anyway.
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: AnimatedContainer(
                duration: WpMotion.durationFor(context, WpMotion.fast),
                curve: WpMotion.defaultCurve,
                decoration: BoxDecoration(
                  color: c.fill,
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
                // The wash below runs off the card on two sides, so something
                // has to crop it. Doing that here, on the card's own rounded
                // rectangle, is what makes it read as a bleed: left to its own
                // devices the `Stack` would crop it at the content box, a
                // padding's width short of the border, and the straight cut
                // with a bare margin behind it reads as a mistake. The padding
                // therefore moves inside, and the `Stack` stops clipping — the
                // layer count is unchanged, the shape it clips to is not.
                child: ClipRRect(
                  borderRadius: WpRadius.borderLg,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // The engine's own glyph, blown up and washed back to the
                      // decorative-glyph tint: a quiet visual identity per
                      // engine (bolt = speed, globe = coverage) that gives the
                      // card depth without competing with the content in front
                      // of it. It is decoration, not a light effect — a flat tinted
                      // glyph, no shadow, no blur, no light around the accent.
                      // `PositionedDirectional` so it sits in the trailing
                      // corner in RTL too, away from the leading icon and
                      // label; being positioned, it takes no part in the card's
                      // own sizing.
                      if (c.heroWash != null)
                        PositionedDirectional(
                          top: -WpSpacing.xl,
                          end: -WpSpacing.xl,
                          child: Icon(
                            widget.icon,
                            size: _heroWashSize,
                            color: c.heroWash,
                          ),
                        ),
                      Padding(
                        // Compensates the border, which is 1.5 on the selected
                        // card and 1 on the others: padding is measured from
                        // the *content* box, so a flat `sm` put the selected
                        // card's text half a pixel further in than its
                        // neighbour's and the two cards' first lines no longer
                        // sat on one baseline. Selecting a card must not move
                        // anything inside it.
                        padding: EdgeInsets.all(
                          WpSpacing.sm + (widget.isSelected ? 0 : 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Engine icon, name, "recommended" badge and selection
                            // check share one line (dense-page geometry); the quiet
                            // check fades in on the right when this card is the current
                            // selection — the accent border alone can blur together
                            // with the badge when both cards sit side by side.
                            Wrap(
                              // Name and badge share a line while both fit. At
                              // large text scale the badge drops under the name
                              // instead of squeezing the name into "Parake…"
                              // (UIA-VIS-10). The first line keeps the badge at
                              // the card's trailing edge, as before.
                              crossAxisAlignment: WrapCrossAlignment.center,
                              alignment: WrapAlignment.spaceBetween,
                              spacing: WpSpacing.xs,
                              runSpacing: WpSpacing.xs,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      widget.icon,
                                      size: WpIconSize.md,
                                      color: iconColor,
                                    ),
                                    const SizedBox(width: WpSpacing.sm),
                                    // Flexible, so the title takes the room the name
                                    // needs and only ellipsises when the name alone is
                                    // wider than the card.
                                    Flexible(
                                      child: Text(
                                        widget.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: WpTypography.subheading,
                                          fontWeight: FontWeight.w600,
                                          color: labelColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.isRecommended &&
                                        !widget.isDisabled) ...[
                                      const SizedBox(width: WpSpacing.xs),
                                      // Inflexible and capped: the pill takes its intrinsic
                                      // width, so it can never claim a share of the free
                                      // space the title needs. The cap plus scale-down is
                                      // what keeps a long localized badge (or an enlarged
                                      // text scale) shrinking rather than overflowing the
                                      // shared line — the job the old `Flexible` did, minus
                                      // the appetite.
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 104,
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: WpSpacing.xs,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: c.badgeFill,
                                              borderRadius: WpRadius.borderFull,
                                            ),
                                            child: Text(
                                              L10n.of(
                                                context,
                                              ).onboardingModelRecommended,
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
                                      duration: WpMotion.durationFor(
                                        context,
                                        WpMotion.fast,
                                      ),
                                      curve: WpMotion.defaultCurve,
                                      child: Icon(
                                        LucideIcons.circleCheck,
                                        size: WpIconSize.sm,
                                        color: accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: WpSpacing.sm),
                            Text(
                              widget.description,
                              style: TextStyle(
                                fontSize: WpTypography.small,
                                color: descriptionColor,
                                height: 1.3,
                              ),
                            ),
                            if (widget.isDisabled &&
                                widget.disabledReason != null) ...[
                              const SizedBox(height: WpSpacing.xs),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    LucideIcons.info,
                                    size: WpIconSize.xs,
                                    color: textMuted,
                                  ),
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
                            // The three facts sit on one row of chips, so size,
                            // languages and speed compare at a glance and the
                            // card stays within the fixed 1100x720 window. The
                            // row wraps only at large text scale.
                            Wrap(
                              spacing: WpSpacing.xs,
                              runSpacing: WpSpacing.xxs,
                              children: [
                                _ModelFactChip(
                                  label: L10n.of(
                                    context,
                                  ).onboardingModelFactSize(widget.sizeLabel),
                                  color: textMuted,
                                  borderColor: c.border,
                                  bold: true,
                                ),
                                _ModelFactChip(
                                  label: widget.languagesLabel,
                                  color: textMuted,
                                  borderColor: c.border,
                                ),
                                _ModelFactChip(
                                  label: widget.speedLabel,
                                  color: textMuted,
                                  borderColor: c.border,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
    required this.accent,
    required this.l10n,
    required this.onCancel,
  });

  final DownloadPhase phase;
  final double progress;
  final Color accent;
  final L10n l10n;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final textSecondary = WpColors.textSecondary;

    final label = switch (phase) {
      DownloadPhase.downloading => '${(progress * 100).round()}%',
      DownloadPhase.extracting => l10n.modelExtracting,
      DownloadPhase.verifying => l10n.modelVerifying,
      _ => '',
    };

    return Column(
      // Stretch so the bar provably spans the page and the label starts at
      // the same reading edge as every other state of this slot.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WpProgressBar(
          value: phase == DownloadPhase.downloading ? progress : null,
          color: accent,
          height: 6,
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          label,
          style: TextStyle(
            fontSize: WpTypography.small,
            color: textSecondary,
            // The one number in the flow that changes in place, several times
            // a second, for minutes. Inter's proportional digits are not the
            // same width, so "38%" → "39%" reflows the glyphs under a bar
            // that is itself perfectly steady, and the counter shimmers.
            // Tabular figures give it a fixed numeric column — the same
            // vocabulary the status bar's backend chip already uses, and the
            // only spelling *The One-Family Rule* leaves for "monospace" (an
            // actual second family is forbidden outright).
            //
            // Here it needs no figure-space padding: the label is left-aligned
            // and nothing sits beside it, so only the per-character width has
            // to be fixed, not the character count.
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
        // A multi-gigabyte download on a slow line must not leave the user
        // stuck between waiting it out and quitting the app.
        const SizedBox(height: WpSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: WpButton(
            testId: _kModelStepDownloadCancelId,
            label: l10n.onboardingModelDownloadCancel,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.neutral,
            icon: LucideIcons.x,
            onPressed: onCancel,
          ),
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
    required this.kind,
    required this.l10n,
    required this.onRetry,
  });

  /// The raw exception text stays in the log; the page only names what the
  /// user can act on.
  final DownloadErrorKind? kind;
  final L10n l10n;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final errorColor = WpColors.error;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(WpSpacing.md),
          decoration: BoxDecoration(
            color: WpColors.errorButtonFill,
            borderRadius: WpRadius.borderMd,
            border: Border.all(color: WpColors.errorBorder20),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.triangleAlert,
                size: WpIconSize.sm,
                color: errorColor,
              ),
              const SizedBox(width: WpSpacing.sm),
              Expanded(
                child: Text(
                  switch (kind) {
                    DownloadErrorKind.network => l10n.modelDownloadFailed,
                    DownloadErrorKind.checksum =>
                      l10n.modelDownloadFailedChecksum,
                    DownloadErrorKind.storage =>
                      l10n.modelDownloadFailedStorage,
                    DownloadErrorKind.tls => l10n.downloadTlsError,
                    DownloadErrorKind.unknown ||
                    null => l10n.modelDownloadFailedUnknown,
                  },
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    color: errorColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        // `xs` between the error banner and the retry it belongs to: the
        // German download-error page needs 4 px more than the fixed window
        // offers at `sm` (onboarding_overlay_test measures it per locale).
        const SizedBox(height: WpSpacing.xs),
        WpButton(
          testId: 'onboarding-speech-retry',
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
  const _GpuCpuFallbackNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // Plain accent, not [WpTierPerformancePresentation.color] — this banner is
    // about the *compute backend*, not about a quality tier, and it borrowed
    // that helper only while every tier state shared one neutral blue. Now
    // that the helper grades slow/unmeasured differently, feeding it a tier
    // this notice does not have would be meaningless.
    final infoColor = WpColors.accent;
    // Frameless, like the recording-duration note on the same page: a filled
    // and outlined banner gave a purely informational line the weight of a
    // warning, and it was the fourth box competing on this page. Dropping the
    // frame also returns 10 px (2 px border + 2x4 px padding) to the tightest
    // height budget in the flow.
    // No leading inset: this no longer stands on the page's reading edge but
    // directly under the Whisper card, whose edge it takes instead.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(LucideIcons.info, size: WpIconSize.sm, color: infoColor),
        ),
        const SizedBox(width: WpSpacing.xs),
        Expanded(
          child: Text(
            message,
            // `body` (13) and a `sm` (16) icon, not the flow's smallest grade:
            // this is the page's only statement about whether the user's
            // machine can actually run what they are about to download, and it
            // was set one step below the card descriptions it qualifies — the
            // hardware verdict rendered as the least important thing on a page
            // about hardware.
            style: TextStyle(
              fontSize: WpTypography.body,
              color: infoColor,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
