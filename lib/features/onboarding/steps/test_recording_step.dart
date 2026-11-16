import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/accessibility/announce.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/app_info.dart' as app;
import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_labels.dart' show modifierOnlyLabel;
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/download_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/recording/recording_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/engine_recommendation.dart' show fasterChoiceWhenSlow;
import '../../../services/hardware_info_service.dart' as hw;
import '../../../services/hotkey_service.dart'
    show
        activeGlobalHotkey,
        doubleTapFallbackActiveProvider,
        globalHotkeyFallbackActiveProvider;
import '../../../services/model_download_service.dart';
import '../../../services/paste/paster.dart';
import '../../../services/permissions/mic_permission_notifier.dart';
import '../../../services/permissions/permissions_overview_provider.dart';
import '../../../services/recording_orchestrator.dart';
import '../../../services/speech_recommendation.dart';
import '../../../services/stt/benchmark_freshness.dart';
import '../../../services/stt_parakeet/parakeet_download_service.dart';
import '../../../widgets/recording_behavior.dart' show localizeRecordingError;
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_hero_button.dart';
import '../../../widgets/wp_permission_row.dart';
import '../../../widgets/waveform.dart';
import '../../../widgets/wp_status_dot.dart';
import '../onboarding_completion_gate.dart';
import '../onboarding_speech_consent.dart';
import '../practice_chat_paster.dart';
import '../practice_stage.dart';
import '../onboarding_download_provider.dart';
import '../onboarding_download_status.dart';
import '../onboarding_readiness.dart';
import '../onboarding_split_page.dart';
import 'trigger_step.dart'
    show
        OnboardingKeyScene,
        onboardingHoldMode,
        onboardingHotkeyCaps,
        onboardingTriggerShortcutText;

/// Guided first dictation (Onboarding v6, screen 6), a split page like the
/// hotkey page. The copy column asks one question, shows the dictated text in
/// a field and says in one status line what happened; the panel shows the
/// hotkey's caps, lit while the recording runs. The dictation goes through the
/// real pipeline with history, snippets and Smart Mode switched off and is
/// delivered by [PracticeChatPaster], so no paste permission is needed here.
/// The shell decides the primary action: [nextLabel] and [onNext] stay
/// "Warte auf Diktat…" and null until a dictation has landed.
///
/// Above the field a readiness list (#186) names speech recognition,
/// microphone and paste; each row that is not ready has one action:
/// [onOpenMic] and [onOpenPaste] jump to the matching onboarding step.
class TestRecordingStep extends ConsumerStatefulWidget {
  const TestRecordingStep({
    super.key,
    this.primaryKey,
    this.nextLabel,
    this.onNext,
    this.onLater,
    this.onBack,
    this.onOpenMic,
    this.onOpenPaste,
  });

  final Key? primaryKey;
  final String? nextLabel;
  final VoidCallback? onNext;
  final VoidCallback? onLater;
  final VoidCallback? onBack;

  /// Jumps to the microphone step. Without it the row asks for the
  /// permission in place.
  final VoidCallback? onOpenMic;

  /// Jumps to the step that sets up Auto-Paste. Without it the paste row has
  /// no action; it never blocks the try-out anyway.
  final VoidCallback? onOpenPaste;

  @override
  ConsumerState<TestRecordingStep> createState() => _TestRecordingStepState();
}

class _TestRecordingStepState extends ConsumerState<TestRecordingStep> {
  static final _log = AppLogger('OnboardingPractice');

  /// Cached notifier reference so [dispose] never touches `ref` (Riverpod
  /// forbids `ref` access after deactivation).
  RecordingOrchestrator? _orchestrator;

  final TextEditingController _input = TextEditingController();

  late final PracticeChatPaster _paster = PracticeChatPaster(
    insert: _insertDictated,
  );

  /// What the last dictation brought, and WhisPaste's answer to it.
  String _dictated = '';
  String? _reply;

  /// The running dictation went hands-free (double tap) at some point, and
  /// a hands-free dictation has already landed: then the "speak longer" line
  /// has done its job and goes.
  bool _sessionHandsFree = false;
  bool _handsFreeLanded = false;

  /// The passive microphone check has answered, so a missing grant can be
  /// said before the first press instead of a system dialog during it.
  bool _micChecked = false;

  /// Whether the page was locked at the last build (the speech model not
  /// ready); the unlock is announced once.
  bool _wasLocked = false;

  /// The readiness at the last build; a changed row title is announced.
  OnboardingReadiness? _lastReadiness;

  /// Counts refused presses, so the lock card pulses once per press.
  int _refusals = 0;

  /// Machine facts behind the slow-model note, see [_loadSpeedFacts].
  hw.GpuInfo? _gpu;
  SpeechRecommendation? _facts;

  @override
  void initState() {
    super.initState();
    _orchestrator = ref.read(recordingOrchestratorProvider.notifier);
    _orchestrator!
      ..sandboxTranscriptSink = _onDictationResult
      ..sandboxPaster = _paster
      ..sandboxLocked = _isLocked
      ..sandboxPressRefused = _onPressRefused;
    unawaited(_checkMic());
    unawaited(_loadSpeedFacts());
  }

  /// The machine facts for the slow-model note. Loaded outside build: a
  /// provider that is first created while this page builds notifies the page
  /// during that build, which Flutter refuses (setState during build).
  Future<void> _loadSpeedFacts() async {
    try {
      final gpu = await ref.read(hw.gpuInfoProvider.future);
      final facts = await ref.read(speechRecommendationProvider.future);
      if (!mounted) return;
      setState(() {
        _gpu = gpu;
        _facts = facts;
      });
    } catch (e) {
      // Without the facts there is simply no slow-model note.
      _log.info('Speed facts unavailable, no slow-model note', e);
    }
  }

  /// The orchestrator asks before each press whether the page is locked.
  bool _isLocked() =>
      ref.read(onboardingPracticeGateProvider) != PracticeGate.open;

  /// A press on the locked page: the lock card pulses and says so aloud.
  void _onPressRefused() {
    if (!mounted) return;
    setState(() => _refusals++);
    _announce(L10n.of(context).onboardingTryoutLockBody);
  }

  void _announce(String text) {
    announce(View.of(context), text, Directionality.of(context));
  }

  Future<void> _checkMic() async {
    await ref.read(micPermissionNotifierProvider.notifier).check();
    if (mounted) setState(() => _micChecked = true);
  }

  @override
  void dispose() {
    _orchestrator
      ?..sandboxTranscriptSink = null
      ..sandboxPaster = null
      ..sandboxLocked = null
      ..sandboxPressRefused = null;
    _input.dispose();
    super.dispose();
  }

  /// Appends a dictated text to the chat input. Returns `false` when the chat
  /// is gone, so the paste reports the failure instead of pretending success.
  bool _insertDictated(String text) {
    if (!mounted) return false;
    final current = _input.text;
    final separator = current.isEmpty || current.endsWith(' ') ? '' : ' ';
    final next = '$current$separator$text';
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    return true;
  }

  /// The orchestrator's result for one dictation, after the paste. Silence
  /// and a failed paste get a WhisPaste message and no success; only a text
  /// that landed in the field counts as the proof the step waits for.
  void _onDictationResult(String text, PasteOutcome? outcome) {
    if (!mounted) return;
    final l10n = L10n.of(context);
    final handsFree = _sessionHandsFree;
    _sessionHandsFree = false;
    if (text.trim().isEmpty) {
      _addReply(l10n.onboardingPracticeSilence);
      return;
    }
    if (outcome != PasteOutcome.success) {
      _addReply(l10n.onboardingPracticePasteFailed);
      return;
    }
    _dictated = _input.text.trim();
    _input.clear();
    if (handsFree) _handsFreeLanded = true;
    _addReply(
      handsFree
          ? l10n.onboardingPracticeReceivedHandsFree
          : l10n.onboardingPracticeReceived,
    );
    ref.read(onboardingTestRecordingSucceededProvider.notifier).markSucceeded();
  }

  /// Moves the chat input into the history as the user's message. Returns
  /// `false` when there is nothing to send.
  void _addReply(String text) {
    setState(() => _reply = text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    // Refreshed on every settings change (the background benchmark writes
    // there). Listening here keeps the load itself out of the build.
    ref.listen<AsyncValue<AppSettings>>(
      settingsProvider,
      (_, _) => unawaited(_loadSpeedFacts()),
    );
    final phase = ref.watch(recordingPhaseProvider);
    final recording = phase == RecordingPhase.recording;
    ref.listen<bool>(handsFreeRecordingProvider, (_, next) {
      if (next) _sessionHandsFree = true;
    });
    final handsFree = recording && ref.watch(handsFreeRecordingProvider);
    final hold = onboardingHoldMode(ref);
    // The model state is read unconditionally, the same subscriptions on every
    // build; only the lock card and the notes below depend on it.
    final gate = ref.watch(onboardingPracticeGateProvider);
    final readiness = watchOnboardingReadiness(ref, micChecked: _micChecked);
    final locked = !readiness.practiceUnlocked;
    final downloadStatus = ref.watch(onboardingDownloadStatusProvider);
    final whisper = ref.watch(modelDownloadProvider);
    final parakeet = ref.watch(parakeetDownloadProvider);
    _announceReadinessChanges(l10n, readiness, unlocked: _wasLocked && !locked);
    _wasLocked = locked;
    _lastReadiness = readiness;
    final hotkey = activeGlobalHotkey(
      settings,
      fallback: ref.watch(globalHotkeyFallbackActiveProvider),
    );
    final singleKey = ref.watch(doubleTapFallbackActiveProvider)
        ? ''
        : settings.hotkey.hotkeyDoubleTapKey;
    final succeeded = ref.watch(onboardingTestRecordingSucceededProvider);
    final recordingState = ref.watch(recordingProvider);
    final stage = practiceStageFor(recordingState);
    // "Speak longer?": once holding works, the same key's double tap is
    // taught for longer texts. Only where hold is the gesture (in toggle
    // mode every dictation is already hands-free) and double tap is on.
    final teachHandsFree = _teachHandsFree(
      succeeded: succeeded,
      hold: hold,
      doubleTap: settings.hotkey.hotkeyDoubleTap,
      recording: recording,
      locked: locked,
    );

    // While locked, the lock card says what the model state is, so the
    // status line carries no model note then.
    final status = _status(
      l10n,
      recording: recording,
      handsFree: handsFree,
      hold: hold,
      modelNote: locked ? null : _slowModelNote(l10n, settings),
      succeeded: succeeded,
      stage: stage,
      errorCode: recordingState.isError ? recordingState.errorMessage : null,
    );

    return OnboardingSplitPage(
      panelAsset: 'assets/onboarding/hotkey-glacier.webp',
      // The lock card carries the download's progress and retry itself.
      showDownloadPill: !locked,
      panel: AnimatedOpacity(
        duration: WpMotion.durationFor(context, WpMotion.fast),
        opacity: locked ? 0.35 : 1,
        child: ExcludeSemantics(
          excluding: locked,
          child: OnboardingKeyScene(
            parts: onboardingHotkeyCaps(
              l10n,
              singleKey: singleKey,
              key: hotkey.key,
              modifiers: hotkey.modifiers,
              display: hotkey.display,
            ),
            lit: recording,
            done: succeeded && !recording,
          ),
        ),
      ),
      copy: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onBack != null)
            OnboardingBackLink(
              testId: 'onboarding-tryout-back',
              label: l10n.onboardingBack,
              onPressed: widget.onBack!,
            ),
          OnboardingSplitHeading(
            l10n.onboardingTestRecordingTitle,
            testId: 'onboarding-tryout-heading',
          ),
          const SizedBox(height: WpSpacing.sm),
          _readinessList(l10n, readiness),
          const SizedBox(height: WpSpacing.md),
          // No invitation to try while the model is not ready: the lock card
          // replaces the instruction below.
          if (!locked) ...[
            Text(
              hold
                  ? l10n.onboardingTestRecordingSubtitleHold
                  : l10n.onboardingTestRecordingSubtitle,
              style: TextStyle(
                fontSize: WpTypography.body,
                height: 1.45,
                color: WpColors.textSecondary,
              ),
            ),
            const SizedBox(height: WpSpacing.lg),
          ],
          AnimatedSwitcher(
            duration: WpMotion.durationFor(context, WpMotion.fast),
            child: locked
                ? _lockCard(
                    l10n,
                    gate: gate,
                    status: downloadStatus,
                    settings: settings,
                    whisper: whisper,
                    parakeet: parakeet,
                  )
                : _ResultField(
                    question: l10n.onboardingPracticeQuestion,
                    text: _dictated,
                    placeholder: l10n.onboardingPracticePlaceholder,
                    active: recording,
                    // The landed text carries the success state in the field
                    // itself (no toast in onboarding).
                    landed: succeeded && !recording,
                  ),
          ),
          const SizedBox(height: WpSpacing.sm),
          // A minimum height, so the action below does not jump when a line
          // appears or goes.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                liveRegion: true,
                identifier: 'onboarding-practice-status',
                child: status,
              ),
            ),
          ),
          if (teachHandsFree)
            Padding(
              padding: const EdgeInsets.only(top: WpSpacing.xs),
              child: Semantics(
                identifier: 'onboarding-practice-longer',
                child: Text(
                  l10n.onboardingPracticeLonger(
                    singleKey.isNotEmpty
                        ? modifierOnlyLabel(l10n, singleKey)
                        : onboardingTriggerShortcutText(l10n, settings),
                  ),
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    height: 1.4,
                    color: WpColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: WpSpacing.sm),
          SizedBox(
            width: kOnboardingCopyWidth,
            child: WpHeroButton(
              testId: 'onboarding-tryout-next',
              key: widget.primaryKey,
              label: widget.nextLabel ?? l10n.onboardingNext,
              onPressed: widget.onNext,
            ),
          ),
          if (widget.onLater != null && !succeeded) ...[
            const SizedBox(height: WpSpacing.sm),
            WpButton(
              testId: 'onboarding-tryout-later',
              label: l10n.onboardingTryOutLaterCta,
              variant: WpButtonVariant.ghost,
              tone: WpButtonTone.neutral,
              onPressed: widget.onLater,
            ),
          ],
        ],
      ),
    );
  }

  /// The lock card for the locked states: loading (progress, unlocks by
  /// itself), failed (the error text) and missing. The action that fixes it
  /// sits on the speech row of the readiness list, one per cause.
  _LockCard _lockCard(
    L10n l10n, {
    required PracticeGate gate,
    required OnboardingDownloadStatus status,
    required AppSettings settings,
    required ModelDownloadState whisper,
    required ParakeetDownloadState parakeet,
  }) {
    final onParakeet = settings.onDeviceEngine == OnDeviceEngine.parakeet;
    final pulse = _refusals;
    switch (gate) {
      case PracticeGate.failed:
        final text = onParakeet
            ? downloadFailureText(
                l10n,
                message: parakeet.errorMessage,
                kind: parakeet.errorKind,
              )
            : downloadFailureText(
                l10n,
                message: whisper.errorMessage,
                kind: whisper.errorKind,
              );
        return _LockCard(
          key: const ValueKey('onboarding-tryout-lock'),
          gate: gate,
          title: l10n.onboardingDownloadFailed,
          body: text,
          pulse: pulse,
        );
      case PracticeGate.missing:
        return _LockCard(
          key: const ValueKey('onboarding-tryout-lock'),
          gate: gate,
          title: l10n.onboardingTryoutLockMissingTitle,
          body: l10n.onboardingPracticeModelMissing,
          pulse: pulse,
        );
      case PracticeGate.loading:
      case PracticeGate.open:
        final percent = (status.fraction * 100).round();
        final remaining = status.remaining;
        return _LockCard(
          key: const ValueKey('onboarding-tryout-lock'),
          gate: gate,
          title: l10n.onboardingTryoutLockTitle,
          body: l10n.onboardingTryoutLockBody,
          progressLine: remaining == null
              ? l10n.onboardingPracticeModelLoading(percent)
              : l10n.onboardingPracticeModelLoadingEta(
                  percent,
                  (remaining.inSeconds / 60).ceil().clamp(1, 999),
                ),
          fraction: status.fraction,
          pulse: pulse,
        );
    }
  }

  /// Announces what changed since the last build: the new title of each row
  /// whose state changed, followed by the unlock once. The download's
  /// progress alone is not a change.
  void _announceReadinessChanges(
    L10n l10n,
    OnboardingReadiness now, {
    required bool unlocked,
  }) {
    final before = _lastReadiness;
    if (before == null) return;
    final texts = <String>[
      if (before.speech != now.speech) _speechTitle(l10n, now),
      if (unlocked) l10n.onboardingTryoutLockReady,
      if (before.mic != now.mic) _micTitle(l10n, now.mic),
      if (before.paste != now.paste) _pasteTitle(l10n, now.paste),
    ];
    if (texts.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announce(texts.join('. '));
    });
  }

  String _speechTitle(L10n l10n, OnboardingReadiness r) => switch (r.speech) {
    SpeechReadiness.ready => l10n.onboardingReadinessSpeechReady,
    SpeechReadiness.loading => l10n.onboardingReadinessSpeechLoading(
      (r.speechFraction * 100).round(),
    ),
    SpeechReadiness.failed => l10n.onboardingReadinessSpeechFailed,
    SpeechReadiness.missing => l10n.onboardingReadinessSpeechMissing,
  };

  String _micTitle(L10n l10n, MicReadiness mic) => switch (mic) {
    MicReadiness.ready => l10n.onboardingReadinessMicReady,
    MicReadiness.missing => l10n.onboardingReadinessMicMissing,
  };

  String _pasteTitle(L10n l10n, PasteReadiness paste) => switch (paste) {
    PasteReadiness.automatic => l10n.onboardingReadinessPasteAutomatic,
    PasteReadiness.off => l10n.onboardingReadinessPasteOff,
    PasteReadiness.clipboardOnly => l10n.onboardingReadinessPasteClipboard,
  };

  /// The three rows: speech recognition, microphone, paste. A row that is not
  /// ready carries exactly one action; the paste row is only a hint and never
  /// locks the field. Each row is a live region, so its change is spoken.
  Widget _readinessList(L10n l10n, OnboardingReadiness r) {
    Widget row(String id, WpPermissionRow child) => Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.xs),
      child: Semantics(
        liveRegion: true,
        identifier: 'onboarding-tryout-row-$id',
        child: child,
      ),
    );

    final speechStatus = switch (r.speech) {
      SpeechReadiness.ready => PermissionOverviewStatus.granted,
      SpeechReadiness.loading => PermissionOverviewStatus.pending,
      SpeechReadiness.failed ||
      SpeechReadiness.missing => PermissionOverviewStatus.missing,
    };
    final speechAction = switch (r.speech) {
      SpeechReadiness.failed => l10n.actionRetry,
      SpeechReadiness.missing => l10n.onboardingLoadModel,
      SpeechReadiness.ready || SpeechReadiness.loading => null,
    };
    final micReady = r.mic == MicReadiness.ready;
    final pasteReady = r.paste == PasteReadiness.automatic;
    final openPaste = widget.onOpenPaste;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          'speech',
          WpPermissionRow(
            id: 'onboarding-speech',
            icon: LucideIcons.audioLines,
            title: _speechTitle(l10n, r),
            purpose: l10n.onboardingReadinessSpeechPurpose,
            status: speechStatus,
            optional: false,
            actionLabel: speechAction,
            actionTestId: 'onboarding-tryout-speech-action',
            onAction: () => unawaited(retryWelcomeSpeechDownload(ref)),
          ),
        ),
        row(
          'mic',
          WpPermissionRow(
            id: 'onboarding-mic',
            icon: LucideIcons.mic,
            title: _micTitle(l10n, r.mic),
            purpose: l10n.onboardingPracticeMicMissing,
            status: micReady
                ? PermissionOverviewStatus.granted
                : PermissionOverviewStatus.missing,
            optional: false,
            actionLabel: micReady ? null : l10n.onboardingReadinessMicAction,
            actionTestId: 'onboarding-tryout-mic-action',
            // Not yet granted (never asked, or denied): fixed before the
            // first press, so the system's dialog never lands in the middle
            // of a dictation.
            onAction:
                widget.onOpenMic ??
                () => unawaited(
                  ref.read(micPermissionNotifierProvider.notifier).request(),
                ),
          ),
        ),
        row(
          'paste',
          WpPermissionRow(
            id: 'onboarding-paste',
            icon: LucideIcons.clipboardPaste,
            title: _pasteTitle(l10n, r.paste),
            purpose: l10n.onboardingReadinessPastePurpose,
            status: pasteReady
                ? PermissionOverviewStatus.granted
                : PermissionOverviewStatus.missing,
            // A hint, not a lock: the field below receives the text anyway.
            optional: true,
            actionLabel: pasteReady || openPaste == null
                ? null
                : l10n.onboardingReadinessPasteAction,
            actionTestId: 'onboarding-tryout-paste-action',
            onAction: openPaste,
          ),
        ),
      ],
    );
  }

  bool _teachHandsFree({
    required bool succeeded,
    required bool hold,
    required bool doubleTap,
    required bool recording,
    required bool locked,
  }) =>
      succeeded &&
      hold &&
      doubleTap &&
      !_handsFreeLanded &&
      !recording &&
      !locked;

  /// One status line: the running recording, else the model note (only the slow-model note while unlocked), else the
  /// error of the last press, else WhisPaste's answer to the last dictation.
  Widget _status(
    L10n l10n, {
    required bool recording,
    required bool handsFree,
    required bool hold,
    required _ModelNote? modelNote,
    required bool succeeded,
    required PracticeStage stage,
    required String? errorCode,
  }) {
    if (recording) {
      return _Stage(
        stage: PracticeStage.listening,
        child: _StatusText(
          handsFree
              ? l10n.onboardingHotkeyStatusHandsFree
              : hold
              ? l10n.onboardingTestRecordingInProgressHold
              : l10n.onboardingTestRecordingInProgress,
          leading: const _ListeningLead(),
        ),
      );
    }
    if (stage == PracticeStage.processing) {
      return _Stage(
        stage: PracticeStage.processing,
        child: _StatusText(
          l10n.onboardingPracticeProcessing,
          leading: const _ProcessingDots(),
        ),
      );
    }
    if (modelNote?.actionLabel case final label?) {
      return _StatusAction(
        testId: 'onboarding-practice-model-status',
        text: modelNote!.text,
        actionLabel: label,
        onAction:
            modelNote.onAction ??
            () => unawaited(retryWelcomeSpeechDownload(ref)),
      );
    }
    if (errorCode case final code?) {
      return _Stage(
        stage: PracticeStage.failed,
        child: _StatusText(
          localizeRecordingError(
            l10n,
            code,
            provider: ref.read(settingsProvider).value?.sttProviderType,
          ),
          leading: const WpStatusDot(tone: WpStatusTone.error),
        ),
      );
    }
    if (_reply case final reply?) {
      return _StatusText(reply, success: succeeded);
    }
    return const SizedBox.shrink();
  }

  /// A ready Whisper model that the measurement on this machine found too
  /// slow: says how long 10 s of speech take and offers the faster choice
  /// from [fasterChoiceWhenSlow]. The measurement itself runs after every
  /// model load in the background and never blocks this page.
  _ModelNote? _slowModelNote(L10n l10n, AppSettings settings) {
    final gpu = _gpu;
    final rec = _facts?.recommendation;
    if (gpu == null || rec == null) return null;
    if (settings.onDeviceEngine != OnDeviceEngine.whisper) return null;
    final tier = tierForModel(settings.stt.model);
    if (tier == null) return null;
    final rtf = benchmarkRtfForMachine(
      benchmark: settings.benchmark,
      gpu: gpu,
      appVersion: app.appVersion,
    )?[tier];
    final faster = fasterChoiceWhenSlow(
      tier: tier,
      rtf: rtf,
      recommendation: rec,
    );
    if (faster == null || rtf == null) return null;
    final parakeet = faster.engine == OnDeviceEngine.parakeet;
    return _ModelNote(
      text: l10n.onboardingPracticeModelSlow((rtf * 10).round()),
      actionLabel: parakeet
          ? l10n.onboardingPracticeModelSlowParakeet
          : l10n.onboardingPracticeModelSlowSmaller,
      onAction: () => unawaited(
        switchWelcomeSpeechModel(
          ref,
          engine: faster.engine,
          whisperModelId: parakeet ? null : bestModelForTier(faster.tier!).id,
        ),
      ),
    );
  }
}

/// The model line of the practice chat: its text and, when the user can act on
/// it, the action label (a retry or a load) and, when the action is not the
/// retry, its own [onAction].
class _ModelNote {
  const _ModelNote({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// The card in the field's place while the model is not ready: what is
/// happening and the progress while it loads. The action sits on the speech
/// row above it. It pulses once per refused press.
class _LockCard extends StatefulWidget {
  const _LockCard({
    super.key,
    required this.gate,
    required this.title,
    required this.body,
    required this.pulse,
    this.progressLine,
    this.fraction = 0,
  });

  final PracticeGate gate;
  final String title;
  final String body;
  final int pulse;

  final String? progressLine;
  final double fraction;

  @override
  State<_LockCard> createState() => _LockCardState();
}

class _LockCardState extends State<_LockCard>
    with SingleTickerProviderStateMixin {
  // Pulse period, not a transition: WpMotion slots time one-shot changes
  // (motion rule in design-tokens/README.md).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant _LockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse != oldWidget.pulse &&
        !MediaQuery.of(context).disableAnimations) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = widget.gate == PracticeGate.loading;
    final percent = (widget.fraction * 100).round();
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        // One gentle rise and fall of the rim, towards the accent.
        final v = _pulse.value;
        final t = v < 0.5 ? v * 2 : (1 - v) * 2;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(WpSpacing.md),
          decoration: BoxDecoration(
            color: WpColors.surfaceElevated,
            borderRadius: WpRadius.borderMd,
            border: Border.all(
              color: Color.lerp(WpColors.borderDefault, WpColors.accent, t)!,
              width: 1 + 0.5 * t,
            ),
          ),
          child: child,
        );
      },
      child: Semantics(
        identifier: 'onboarding-tryout-lock-card',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: TextStyle(
                fontSize: WpTypography.body,
                fontWeight: FontWeight.w600,
                color: WpColors.textPrimary,
              ),
            ),
            if (loading) ...[
              const SizedBox(height: WpSpacing.sm),
              Semantics(
                identifier: 'onboarding-tryout-lock-progress',
                value: '$percent %',
                child: _LockProgressBar(fraction: widget.fraction),
              ),
              const SizedBox(height: WpSpacing.xs),
              Text(
                widget.progressLine ?? '',
                style: TextStyle(
                  fontSize: WpTypography.small,
                  color: WpColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: WpSpacing.xs),
            Text(
              widget.body,
              style: TextStyle(
                fontSize: WpTypography.body,
                height: 1.45,
                color: WpColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The loading line of the lock card: the fill follows the progress, and jumps
/// with reduced motion.
class _LockProgressBar extends StatelessWidget {
  const _LockProgressBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: WpRadius.borderSm,
        child: Stack(
          children: [
            ColoredBox(
              color: WpColors.cardFillElevated,
              child: const SizedBox.expand(),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(end: fraction.clamp(0.0, 1.0)),
              duration: WpMotion.durationFor(context, WpMotion.dramatic),
              curve: WpMotion.spring,
              builder: (context, value, _) => FractionallySizedBox(
                widthFactor: value,
                alignment: AlignmentDirectional.centerStart,
                child: ColoredBox(
                  color: WpColors.accent,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The field the dictation lands in: the question above, then the text, or
/// a placeholder until the first dictation. Its rim lights while recording.
class _ResultField extends StatelessWidget {
  const _ResultField({
    required this.question,
    required this.text,
    required this.placeholder,
    required this.active,
    this.landed = false,
  });

  final String question;
  final String text;
  final String placeholder;
  final bool active;

  /// The dictation landed: the rim turns to the success colour.
  final bool landed;

  @override
  Widget build(BuildContext context) {
    final empty = text.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          question,
          style: TextStyle(
            fontSize: WpTypography.body,
            fontWeight: FontWeight.w600,
            color: WpColors.textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        AnimatedContainer(
          duration: WpMotion.durationFor(context, WpMotion.fast),
          curve: WpMotion.defaultCurve,
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.all(WpSpacing.md),
          decoration: BoxDecoration(
            color: WpColors.surfaceElevated,
            borderRadius: WpRadius.borderMd,
            border: Border.all(
              color: active
                  ? WpColors.accent
                  : landed
                  ? WpColors.success
                  : WpColors.borderDefault,
              width: active || landed ? 1.5 : 1,
            ),
          ),
          child: Semantics(
            identifier: 'onboarding-practice-result',
            child: Text(
              empty ? placeholder : text,
              style: TextStyle(
                fontSize: WpTypography.body,
                height: 1.45,
                color: empty ? WpColors.textMuted : WpColors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Marks the status line of one dictation stage, so the stage is found by its
/// testID (`onboarding-practice-stage-<stage>`). Only the stage that is
/// showing exists in the tree.
class _Stage extends StatelessWidget {
  const _Stage({required this.stage, required this.child});

  final PracticeStage stage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'onboarding-practice-stage-${stage.name}',
      child: child,
    );
  }
}

/// The listening lead: the shared compact waveform, fed by the microphone
/// level the overlay reads too. Reduced motion gets one steady dot instead,
/// so nothing moves.
class _ListeningLead extends StatelessWidget {
  const _ListeningLead();

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return const ExcludeSemantics(
        child: WpStatusDot(tone: WpStatusTone.ready),
      );
    }
    return const _LevelMeter();
  }
}

class _LevelMeter extends ConsumerWidget {
  const _LevelMeter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(audioLevelProvider).clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: WpWaveformBadge(audioLevel: level, color: WpColors.accent),
    );
  }
}

/// The processing lead: three busy dots that pulse in turn. Reduced motion
/// keeps the three dots steady.
class _ProcessingDots extends StatefulWidget {
  const _ProcessingDots();

  @override
  State<_ProcessingDots> createState() => _ProcessingDotsState();
}

class _ProcessingDotsState extends State<_ProcessingDots>
    with SingleTickerProviderStateMixin {
  /// One wave across the three dots: slower than any UI transition token, so
  /// it reads as waiting and not as a flicker.
  static const _waveCycle = WpMotion.waitCycle;

  /// Opacity of a dot between two wave crests.
  static const _restOpacity = 0.3;

  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: _waveCycle,
  );

  /// Null until the first build reads the platform setting.
  bool? _still;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.of(context).disableAnimations;
    if (still == _still) return;
    _still = still;
    if (still) {
      _wave.stop();
    } else {
      _wave.repeat();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: WpIconSize.sm,
        child: AnimatedBuilder(
          animation: _wave,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.xxxs,
                  ),
                  child: Opacity(
                    opacity: (_still ?? true)
                        ? 1
                        : _restOpacity +
                              (1 - _restOpacity) *
                                  math.sin(
                                    math.pi * ((_wave.value - i * 0.2) % 1.0),
                                  ),
                    child: const WpStatusDot(tone: WpStatusTone.busy),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The status line as plain text, with an optional [leading] mark (a level
/// meter, a dot). A success reads in the success colour.
class _StatusText extends StatelessWidget {
  const _StatusText(this.text, {this.success = false, this.leading});

  final String text;
  final bool success;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading case final mark?) ...[
          mark,
          const SizedBox(width: WpSpacing.sm),
        ],
        if (success) ...[
          Icon(LucideIcons.check, size: WpIconSize.sm, color: WpColors.success),
          const SizedBox(width: WpSpacing.xs),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: WpTypography.body,
              height: 1.4,
              color: WpColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The status line when something is missing: what, and a real button that
/// fixes it.
class _StatusAction extends StatelessWidget {
  const _StatusAction({
    required this.testId,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String testId;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: WpTypography.body,
            height: 1.4,
            color: WpColors.textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        WpButton(
          testId: '$testId-action',
          label: actionLabel,
          variant: WpButtonVariant.secondary,
          tone: WpButtonTone.accent,
          onPressed: onAction,
        ),
      ],
    );
  }
}
