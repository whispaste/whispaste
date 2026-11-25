/// Eagerly initializes all required keepAlive services via [ref.watch].
///
/// Place near the widget tree root. It renders [child] unchanged — its only
/// purpose is to ensure Riverpod providers that manage system-level services
/// (tray, hotkeys, autostart, STT) are alive for the app lifetime.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../core/data/database.dart' show historyDatabaseProvider;
import '../core/onboarding/onboarding_surface.dart'
    show onboardingSurfaceActiveProvider;
import '../core/navigation/page_state.dart'
    show activePageProvider, settingsScrollTargetProvider;
import '../core/config/secure_key_store.dart'
    show secureAccessGate, withSecureTrigger;
import '../core/config/settings_provider.dart';
import '../core/l10n/locale_provider.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/ui_thread_watchdog.dart';
import '../core/platform/macos_lifecycle_channel.dart';
import '../core/recording/discard_confirmation.dart';
import '../core/recording/recording_state.dart'
    show
        RecordingPhase,
        RecordingTarget,
        handsFreeRecordingProvider,
        recordingElapsedProvider,
        recordingPhaseProvider,
        recordingProvider;
import '../services/audio/import/audio_import_providers.dart';
import '../services/autostart_service.dart';
import '../services/clipboard_history/clipboard_history_monitor_service.dart';
import '../services/feedback_consent_store.dart';
import '../services/snippets/system_variables.dart';
import '../services/feedback_submission_service.dart';
import '../services/floating_button/floating_button_service.dart';
import '../services/floating_overlay/floating_overlay_service.dart';
import '../services/floating_overlay/overlay_hint_learning.dart';
import '../services/hotkey_disturbance.dart';
import '../services/hotkey_self_heal.dart';
import '../services/hotkey_service.dart';
import '../services/language_cycle_service.dart';
import '../services/linux_desktop_shortcut.dart';
import '../services/linux_file_selector.dart';
import '../services/paste/paste_capability_notifier.dart';
import '../services/permissions/tcc_entry_reset_confirm.dart';
import '../services/recording_orchestrator.dart';
import '../services/newsletter/newsletter_service.dart'
    show newsletterSignupProvider;
import '../services/modifier_key_monitor.dart'
    show ModifierHotkey, kBusyKeyHoldStartDelay;
import '../services/recording_trigger_handler.dart';
import '../services/paste/paste_result_notice.dart';
import '../services/paste/repaste_service.dart';
import '../services/replacements/learn_correction_hotkey.dart';
import '../services/snippet_picker/snippet_picker_service.dart';
import '../services/snippets/interactive_snippet_controller.dart';
import '../services/side_panel/side_panel_service.dart';
import '../services/app_profiles/profile_activation.dart';
import '../services/app_profiles/profile_hotkey_sync.dart';
import '../services/dictation_key_plan.dart' show resolveDictationKey;
import '../services/dictation_key_sync.dart';
import '../services/instance_cli.dart' show remoteCommandActs;
import '../services/single_instance_service.dart';
import '../services/file_import_inbox.dart';
import '../features/history/widgets/audio_import_panel.dart'
    show audioImportRejectionsProvider, importAudioFiles;
import '../services/tray_service.dart';
import '../services/paste/paster.dart' show PasteCapabilityStatus;

/// Invisible wrapper that eagerly boots keepAlive service providers.
final _log = AppLogger('ServiceBootstrap');

class WpServiceBootstrap extends ConsumerStatefulWidget {
  const WpServiceBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WpServiceBootstrap> createState() => _WpServiceBootstrapState();
}

class _WpServiceBootstrapState extends ConsumerState<WpServiceBootstrap> {
  AppSettings get _settings =>
      ref.read(settingsProvider).value ?? AppSettings.defaults;

  /// The single key that listens for dictation, or null while the
  /// combination does (none chosen, or the key is not observable here).
  ModifierHotkey? _listeningSingleKey() {
    if (ref.read(doubleTapFallbackActiveProvider)) return null;
    return ModifierHotkey.values
        .asNameMap()[_settings.hotkey.hotkeyDoubleTapKey];
  }

  /// Keys also used for typing start a hold only after a moment alone.
  Duration _holdStartDelay() => _listeningSingleKey()?.isBusy ?? false
      ? kBusyKeyHoldStartDelay
      : Duration.zero;

  bool _orchestratorInitialized = false;

  /// The hotkey service this state wired, kept so [dispose] can release its
  /// callbacks without `ref` (#439).
  late final HotkeyService _hotkeySvc;

  /// The stall handler this state gave the watchdog. A rebuilt bootstrap
  /// (the shell is keyed by the colour set, so a settings import that changes
  /// it builds a new one) installs its own before this one is disposed; the
  /// old [dispose] must then leave the watchdog running.
  late final void Function(Duration jank) _onSevereStall;

  /// The single [RecordingTriggerHandler] instance for this state's lifetime.
  ///
  /// Must NOT be recreated on every [build] — the handler holds keyDown/keyUp
  /// state (`_keyDownAt`, `_keyUpBreadcrumbSent`) and losing it between
  /// hotkey events breaks Push-to-Talk (see issue 06 of the
  /// `hotkey-modifier-storage-fix` PRD).
  late final RecordingTriggerHandler _triggerHandler;

  /// Trigger handler for the quick-note hotkey (ticket 20). Same class, same
  /// held-for-lifetime rule as [_triggerHandler] — a second instance rather
  /// than a shared one, since each hotkey needs its own PTT/toggle mode
  /// (this action is always toggle-only) and its own recording target.
  late final RecordingTriggerHandler _quickNoteTriggerHandler;

  /// Trigger handler for the Smart-Mode hotkey. Same held-for-lifetime rule as
  /// [_triggerHandler] — unlike the quick-note handler, this one DOES support
  /// push-to-talk (mirrors the main hotkey's behaviour per the ticket), so it
  /// needs its own instance to track its own keyDown/keyUp state
  /// independently of the main hotkey's.
  late final RecordingTriggerHandler _smartModeTriggerHandler;

  /// Trigger handler for the edit-selection hotkey
  /// — push-to-talk and toggle like the
  /// Smart-Mode hotkey, recording into [RecordingTarget.selectionEdit].
  late final RecordingTriggerHandler _selectionEditTriggerHandler;

  /// Trigger handlers of the extra dictation keys (#2055), one per key id,
  /// created on the key's first press and kept for this state's lifetime
  /// (each holds its own keyDown/keyUp state, see [_triggerHandler]).
  final Map<String, RecordingTriggerHandler> _dictationKeyHandlers = {};

  /// The trigger handler of the extra dictation key [keyId]. It mirrors the
  /// main hotkey's gestures (hold, tap or hold, double tap for hands-free,
  /// #769) and forces the key's language and Smart Mode choice, resolved at
  /// the press so a change in Settings applies to the next press.
  RecordingTriggerHandler _dictationKeyHandler(String keyId) =>
      _dictationKeyHandlers.putIfAbsent(keyId, () {
        final orchestrator = ref.read(recordingOrchestratorProvider.notifier);
        final hotkeySvc = _hotkeySvc;
        return RecordingTriggerHandler(
          startRecording: () {
            final run = resolveDictationKey(_settings, keyId);
            if (run == null || _isInteractiveSnippetActive) {
              return Future<void>.value();
            }
            return orchestrator.startRecording(
              languageOverride: run.language,
              forcedSmartModePreset: run.preset,
              startToneNotBefore: _settings.hotkey.hotkeyDoubleTap
                  ? kShortTapMaxDuration
                  : Duration.zero,
            );
          },
          stopRecording: _stopOrAdvance,
          toggleRecording: () {
            if (_isInteractiveSnippetActive) return _stopOrAdvance();
            final run = resolveDictationKey(_settings, keyId);
            if (run == null) {
              // A key removed meanwhile may still stop what runs.
              return ref.read(recordingProvider).isRecording
                  ? orchestrator.stopRecording()
                  : Future<void>.value();
            }
            return orchestrator.toggleRecording(
              languageOverride: run.language,
              forcedSmartModePreset: run.preset,
            );
          },
          pushToTalkEnabled: () => _settings.pushToTalk,
          registrarSupportsKeyUp: () => hotkeySvc.dictationKeysSupportKeyUp,
          holdOrTapEnabled: () => _settings.audioInput.holdOrTap,
          holdOrTapThresholdMs: () => _settings.audioInput.holdOrTapThresholdMs,
          doubleTapEnabled: () => _settings.hotkey.hotkeyDoubleTap,
          doubleTapLatches: () => true,
          isRecording: () => ref.read(recordingProvider).isRecording,
          recordingSessionId: () => ref.read(recordingProvider).sessionId,
          cancelRecording: () => orchestrator.cancelRecording(),
          onHandsFreeChanged: (handsFree) =>
              ref.read(handsFreeRecordingProvider.notifier).set(handsFree),
          nativeEventAt: () => hotkeySvc.nativeEventAt,
          nativePressed: () => hotkeySvc.nativePressed,
        );
      });

  /// Whether an interactive-snippet guided sequence is currently running —
  /// while it is, the main recording hotkey advances to the next field
  /// (PRD `interactive-snippets` User Story 14) instead of its usual
  /// stop/toggle behavior.
  bool get _isInteractiveSnippetActive =>
      ref.read(interactiveSnippetControllerProvider.notifier).isActive;

  Future<void> _stopOrAdvance() {
    if (_isInteractiveSnippetActive) {
      return ref
          .read(interactiveSnippetControllerProvider.notifier)
          .advanceField();
    }
    return ref.read(recordingOrchestratorProvider.notifier).stopRecording();
  }

  /// Registers/unregisters the system-wide cancel-dictation Escape key (issue
  /// #145) as the recording phase crosses in/out of
  /// recording/transcribing/refining. Lives here — not in
  /// `FloatingOverlayService` — because Escape must cancel a dictation
  /// regardless of whether the floating overlay is even enabled
  /// (`OverlayMode.off`): the key is the source of truth, the overlay is
  /// just one of its visual surfaces.
  ///
  /// Skipped entirely while an interactive-snippet sequence is active — that
  /// sequence's own Escape registration (`registerInteractiveSnippetKeys`)
  /// already owns the key for its "cancel sequence" meaning, which must not
  /// be overridden or raced by this one.
  static bool _isCancelableDictationPhase(RecordingPhase phase) =>
      phase == RecordingPhase.recording ||
      phase == RecordingPhase.transcribing ||
      phase == RecordingPhase.refining;

  /// Escape during a long recording only arms a confirmation (see
  /// `discard_confirmation.dart`); every other cancel discards at once.
  void _onCancelDictationPressed() {
    final discardNow = cancelPressDiscardsNow(
      ref.read(recordingPhaseProvider),
      ref.read(recordingElapsedProvider),
      ref.read(discardConfirmProvider.notifier),
      cardOpen: ref.read(recordingCardOpenProvider),
    );
    if (!discardNow) return;
    // Overlay E: a cancel by key teaches the cancel hint.
    unawaited(
      ref.read(overlayHintLearningProvider.notifier).recordCancel(byKey: true),
    );
    unawaited(
      ref.read(recordingOrchestratorProvider.notifier).cancelRecording(),
    );
  }

  /// Overlay E: the dictation hotkey is about to stop a running recording.
  /// Counted for the stop hint before the stop, while the phase still says
  /// recording; a press that starts a recording or advances a snippet field
  /// is not counted.
  void _countHotkeyStop() {
    if (_isInteractiveSnippetActive) return;
    if (!ref.read(recordingProvider).isRecording) return;
    unawaited(
      ref.read(overlayHintLearningProvider.notifier).recordHotkeyStop(),
    );
  }

  void _syncCancelDictationEscapeKey(RecordingPhase prev, RecordingPhase next) {
    if (_isInteractiveSnippetActive) return;
    final wasActive = _isCancelableDictationPhase(prev);
    final isActive = _isCancelableDictationPhase(next);
    if (isActive && !wasActive) {
      unawaited(
        ref
            .read(hotkeyServiceProvider.notifier)
            .registerCancelDictationKey(
              key: logicalKeyForCancelDictation(
                (ref.read(settingsProvider).value ?? AppSettings.defaults)
                    .audioInput
                    .cancelDictationKey,
              ),
              onCancel: _onCancelDictationPressed,
            ),
      );
    } else if (!isActive && wasActive) {
      ref.read(discardConfirmProvider.notifier).disarm();
      unawaited(
        ref.read(hotkeyServiceProvider.notifier).unregisterCancelDictationKey(),
      );
    }
  }

  void Function()? _removeWithdrawalKick;

  Future<void> _kickFeedbackWithdrawals() async {
    final service = ref.read(feedbackSubmissionServiceProvider);
    Future<void> kick(String trigger) =>
        withSecureTrigger(trigger, () => feedbackWithdrawalRetry.kick(service));
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mayHavePendingWithdrawal(prefs)) {
        await kick('feedback withdrawal start');
        return;
      }
    } on Object catch (e) {
      _log.warning('Withdrawal check at start failed: ${e.runtimeType}');
    }
    if (!mounted) return;
    _removeWithdrawalKick = secureAccessGate.addOpenListener(() {
      _removeWithdrawalKick?.call();
      _removeWithdrawalKick = null;
      unawaited(kick('feedback withdrawal after consent'));
    });
  }

  @override
  void initState() {
    super.initState();
    // Start UI thread jank detection.
    UiThreadWatchdog.instance.start();

    // Withdrawals of the website-quote consent that were made offline are
    // sent now and retried with backoff while any are pending. The consent
    // state lives in the credential store; it is only read at start when the
    // non-secret prefs mirror shows a pending withdrawal, otherwise once the
    // user allowed the key store (#1161).
    unawaited(_kickFeedbackWithdrawals());

    // Linux file dialogs show their title and buttons in the app language
    // and follow every language change (XP-5-13).
    if (defaultTargetPlatform == TargetPlatform.linux) {
      ref.listenManual<Locale>(
        localeProvider,
        (_, next) =>
            LinuxFileSelector.install(l10nForLocaleCode(next.languageCode)),
        fireImmediately: true,
      );
    }

    // ── Trigger handler — created once and kept for the state's lifetime ──
    // Reads (`ref.read`) stay closure-bound to the live `ref`, so settings
    // and orchestrator look-ups always see the current values, not a snapshot.
    final hotkeySvc = _hotkeySvc = ref.read(hotkeyServiceProvider.notifier);
    // Claims the callbacks below; dispose releases them only while this
    // state still owns them (#439).
    hotkeySvc.bindCallbacks(this);
    _triggerHandler = RecordingTriggerHandler(
      // A no-op while an interactive-snippet sequence is running: each
      // field's recording is already started by InteractiveSnippetController
      // itself, so a Push-to-Talk keyDown of the main hotkey mid-sequence
      // must not start a second, conflicting `clipboard`-target recording.
      startRecording: () => _isInteractiveSnippetActive
          ? Future<void>.value()
          : ref
                .read(recordingOrchestratorProvider.notifier)
                .startRecording(
                  // Hold + double tap: a short tap must not chime (#329).
                  startToneNotBefore: _settings.hotkey.hotkeyDoubleTap
                      ? kShortTapMaxDuration
                      : Duration.zero,
                ),
      stopRecording: () {
        _countHotkeyStop();
        return _stopOrAdvance();
      },
      toggleRecording: () {
        _countHotkeyStop();
        return _isInteractiveSnippetActive
            ? _stopOrAdvance()
            : ref
                  .read(recordingOrchestratorProvider.notifier)
                  .toggleRecording();
      },
      pushToTalkEnabled: () =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults).pushToTalk,
      registrarSupportsKeyUp: () => hotkeySvc.supportsKeyUp,
      holdOrTapEnabled: () =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults)
              .audioInput
              .holdOrTap,
      holdOrTapThresholdMs: () =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults)
              .audioInput
              .holdOrTapThresholdMs,
      // One trigger, combination or single key: hold to dictate, double tap
      // for hands-free (maintainer 2026-10-30).
      doubleTapEnabled: () => _settings.hotkey.hotkeyDoubleTap,
      doubleTapLatches: () => true,
      singleKey: () => _listeningSingleKey() != null,
      holdStartDelay: _holdStartDelay,
      isRecording: () => ref.read(recordingProvider).isRecording,
      recordingSessionId: () => ref.read(recordingProvider).sessionId,
      cancelRecording: () =>
          ref.read(recordingOrchestratorProvider.notifier).cancelRecording(),
      onHandsFreeChanged: (handsFree) =>
          ref.read(handsFreeRecordingProvider.notifier).set(handsFree),
      nativeEventAt: () => hotkeySvc.nativeEventAt,
      nativePressed: () => hotkeySvc.nativePressed,
    );
    // macOS (#775): after the press is handed on, name secure input or a
    // slow keyboard tap of another app once. Never delays the trigger.
    final disturbance = ref.read(hotkeyDisturbanceWatcherProvider);
    // The recording hotkeys (main, quick note, Smart Mode, edit selection)
    // share one registration path and so one cause (#870); one-shot hotkeys
    // (snippets, language, repaste) are no dictation and stay out.
    void Function() withDisturbance(void Function() onKeyDown) =>
        disturbance == null
        ? onKeyDown
        : () {
            onKeyDown();
            unawaited(disturbance.onHotkeyPressed());
          };
    hotkeySvc.onHotkeyPressed = withDisturbance(_triggerHandler.onKeyDown);
    hotkeySvc.onHotkeyReleased = () {
      // #564: read the extra key at the release, before the stop runs.
      unawaited(
        ref.read(recordingOrchestratorProvider.notifier).armAutoSendOnRelease(),
      );
      _triggerHandler.onKeyUp();
    };
    hotkeySvc.onModifierOtherKey = _triggerHandler.onOtherKey;
    // A severe UI stall (>1 s) may have cost the OS registration too.
    _onSevereStall = (_) =>
        unawaited(hotkeySvc.requestHotkeyHeal(HotkeyHealTrigger.uiStall));
    UiThreadWatchdog.instance.onSevereStall = _onSevereStall;

    // ── Quick-note trigger handler (ticket 20) — toggle-only, no PTT ──
    _quickNoteTriggerHandler = RecordingTriggerHandler(
      startRecording: () => ref
          .read(recordingOrchestratorProvider.notifier)
          .startRecording(target: RecordingTarget.quickNote),
      stopRecording: () =>
          ref.read(recordingOrchestratorProvider.notifier).stopRecording(),
      toggleRecording: () => ref
          .read(recordingOrchestratorProvider.notifier)
          .toggleRecording(target: RecordingTarget.quickNote),
      // Hardcoded false: the quick-note hotkey never wires a keyUpHandler
      // (see HotkeyService.updateQuickNoteHotkey), so onKeyUp never fires
      // for it anyway — this just documents the invariant at the call site.
      pushToTalkEnabled: () => false,
      registrarSupportsKeyUp: () => hotkeySvc.supportsKeyUp,
    );
    hotkeySvc.onQuickNoteHotkeyPressed = withDisturbance(
      _quickNoteTriggerHandler.onKeyDown,
    );

    // ── Snippet-Picker hotkey (ticket 26) — one-shot, no recording, so no
    // RecordingTriggerHandler needed: just a direct closure into the
    // orchestrator's dedicated method. ──
    hotkeySvc.onSnippetPickerHotkeyPressed = () => ref
        .read(recordingOrchestratorProvider.notifier)
        .openSnippetPickerViaHotkey();

    // ── "Next favorite language" hotkey — one-shot, switches the dictation
    // language; the app shell shows the feedback toast. ──
    hotkeySvc.onLanguageCycleHotkeyPressed = () =>
        ref.read(languageCycleFeedbackProvider.notifier).cycle();

    // ── One hotkey per favorite language (#2137) — one-shot, switches
    // straight to that language with the same toast. Registered by the
    // profile hotkey sync below. ──
    hotkeySvc.onFavoriteLanguageHotkeyPressed = (code) =>
        ref.read(languageCycleFeedbackProvider.notifier).switchTo(code);

    // ── "Paste the last dictation again" hotkey — one-shot, starts nothing,
    // pastes through the shared paster. ──
    hotkeySvc.onRepasteHotkeyPressed = () => unawaited(
      ref.read(repasteServiceProvider).pasteLast().catchError((Object error) {
        _log.warning('Repaste failed: $error');
        return null;
      }),
    );

    // ── "Learn correction" hotkey (#934) — copies the selection in the app
    // in front and proposes the replacement; never throws. ──
    hotkeySvc.onLearnCorrectionHotkeyPressed = () => unawaited(
      ref.read(learnCorrectionHotkeyServiceProvider).learnFromSelection(),
    );

    // ── Profile hotkeys (ticket 13, part 2): one hotkey per profile switches
    // to it; the sync keeps the registered set in step with the profiles. ──
    hotkeySvc.onProfileHotkeyPressed = (profileId) =>
        unawaited(ref.read(profileActivatorProvider).activateById(profileId));
    ref.read(profileHotkeySyncProvider);
    ref.read(profileMarkerProvider);

    // ── Smart-Mode hotkey (#248, ADR 0015 D9) — push-to-talk AND toggle,
    // identical to the main hotkey's behaviour. It writes new text (or edits
    // a selection); a preset bound earlier is no longer applied. ──
    _smartModeTriggerHandler = RecordingTriggerHandler(
      startRecording: () => ref
          .read(recordingOrchestratorProvider.notifier)
          .startRecording(target: RecordingTarget.smartWrite),
      stopRecording: () =>
          ref.read(recordingOrchestratorProvider.notifier).stopRecording(),
      toggleRecording: () => ref
          .read(recordingOrchestratorProvider.notifier)
          .toggleRecording(target: RecordingTarget.smartWrite),
      pushToTalkEnabled: () =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults).pushToTalk,
      registrarSupportsKeyUp: () => hotkeySvc.optionalActionsSupportKeyUp,
      holdOrTapEnabled: () =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults)
              .audioInput
              .holdOrTap,
      holdOrTapThresholdMs: () =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults)
              .audioInput
              .holdOrTapThresholdMs,
      isRecording: () => ref.read(recordingProvider).isRecording,
      recordingSessionId: () => ref.read(recordingProvider).sessionId,
    );
    hotkeySvc.onSmartModeHotkeyPressed = withDisturbance(
      _smartModeTriggerHandler.onKeyDown,
    );
    hotkeySvc.onSmartModeHotkeyReleased = _smartModeTriggerHandler.onKeyUp;

    // ── Edit-selection trigger handler ──
    _selectionEditTriggerHandler = RecordingTriggerHandler(
      startRecording: () => ref
          .read(recordingOrchestratorProvider.notifier)
          .startRecording(target: RecordingTarget.selectionEdit),
      stopRecording: () =>
          ref.read(recordingOrchestratorProvider.notifier).stopRecording(),
      toggleRecording: () => ref
          .read(recordingOrchestratorProvider.notifier)
          .toggleRecording(target: RecordingTarget.selectionEdit),
      pushToTalkEnabled: () =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults).pushToTalk,
      registrarSupportsKeyUp: () => hotkeySvc.optionalActionsSupportKeyUp,
      holdOrTapEnabled: () =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults)
              .audioInput
              .holdOrTap,
      holdOrTapThresholdMs: () =>
          (ref.read(settingsProvider).value ?? AppSettings.defaults)
              .audioInput
              .holdOrTapThresholdMs,
      isRecording: () => ref.read(recordingProvider).isRecording,
      recordingSessionId: () => ref.read(recordingProvider).sessionId,
    );
    hotkeySvc.onSelectionEditHotkeyPressed = withDisturbance(
      _selectionEditTriggerHandler.onKeyDown,
    );
    hotkeySvc.onSelectionEditHotkeyReleased =
        _selectionEditTriggerHandler.onKeyUp;

    // ── Extra dictation keys (#2055): each forces its language (and
    // optionally a Smart Mode choice) and otherwise behaves like the main
    // hotkey. Without extra keys the sync registers nothing. ──
    hotkeySvc.onDictationKeyPressed = (keyId) =>
        withDisturbance(_dictationKeyHandler(keyId).onKeyDown)();
    hotkeySvc.onDictationKeyReleased = (keyId) {
      unawaited(
        ref.read(recordingOrchestratorProvider.notifier).armAutoSendOnRelease(),
      );
      _dictationKeyHandler(keyId).onKeyUp();
    };
    ref.read(dictationKeySyncProvider);

    // A bootstrap rebuilt mid-dictation takes over the Escape cancel key:
    // the phase listener only fires on a change, so the key would otherwise
    // keep the torn-down state's callback (#439).
    _syncCancelDictationEscapeKey(
      RecordingPhase.idle,
      ref.read(recordingPhaseProvider),
    );

    // ── Interactive-snippet selection (interactive-snippets PRD) — wired
    // here, not inside SnippetPickerService itself, to avoid a file-level
    // import cycle (see the doc comment on
    // SnippetPickerService.onInteractiveSnippetSelected).
    ref
        .read(snippetPickerServiceProvider.notifier)
        .onInteractiveSnippetSelected = (snippet) async {
      final fields = await ref
          .read(historyDatabaseProvider)
          .readSnippetFields(snippet.id);
      await ref
          .read(interactiveSnippetControllerProvider.notifier)
          .start(
            fields,
            template: (await resolveSystemVariablesLive(
              snippet.body,
              title: snippet.title,
            )).text,
          );
    };
    ref
        .read(snippetPickerServiceProvider.notifier)
        .onSentenceSnippetSelected = (snippet) async {
      final fields = await ref
          .read(historyDatabaseProvider)
          .readSnippetFields(snippet.id);
      await ref
          .read(interactiveSnippetControllerProvider.notifier)
          .startSentence(
            fields,
            template: (await resolveSystemVariablesLive(
              snippet.body,
              title: snippet.title,
            )).text,
            title: snippet.title,
          );
    };
    ref
        .read(interactiveSnippetControllerProvider.notifier)
        .onShowFieldPreview = (request) => ref
        .read(snippetPickerServiceProvider.notifier)
        .showFieldPreview(
          title: request.title,
          template: request.template,
          fieldNames: request.fieldNames,
          values: request.values,
          modelReady: request.modelReady,
        );
    ref
        .read(snippetPickerServiceProvider.notifier)
        .onPasteResult = (outcome) async {
      await ref.read(pasteResultReporterProvider).report(outcome);
    };

    // ── CLI remote control (`whispaste --toggle` / `--start` / `--stop` /
    // `--cancel`, #1952) — forwarded
    // by a second process over the single-instance channel. Registered after
    // the first frame, alongside the orchestrator's deferred init, so a
    // command queued during startup (cold start via `--toggle`) runs against
    // a live pipeline. `--toggle` always toggles, like the tray entry, also
    // in Push-to-Talk mode: a CLI call has no key-up to stop on. ──
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SingleInstanceService.onRemoteCommand = _onRemoteCommand;
      // Files from the file manager's "Transcribe with WhisPaste" entry
      // (#1684), from this launch or handed over by a second one. While the
      // onboarding is on top they wait in the queue (#1705): a first start
      // with a file has no model yet, and the import would fail hidden
      // behind the overlay. They run once it closes, without interrupting
      // the setup and without downloading anything on their own.
      _syncOpenFilesHandler();
      ref.listenManual<bool>(
        onboardingSurfaceActiveProvider,
        (_, _) => _syncOpenFilesHandler(),
      );
      _importInbox.start(SingleInstanceService.requeueOpenFiles);
      // macOS hands a `whispaste://` link to the running process instead of
      // an argument; collect any that arrived before this point.
      unawaited(MacOSLifecycleChannel.takeOpenUrls());
    });

    // ── Tray callbacks — stateless closures, safe to wire once ──
    final tray = ref.read(trayServiceProvider.notifier);
    tray.onToggleRecording = () {
      ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
    };
    tray.onNavigate = (page) {
      ref.read(activePageProvider.notifier).setPage(page);
    };
    tray.onTranscribeFile = () {
      ref.read(activePageProvider.notifier).setPage('history');
      ref.read(audioImportPickRequestProvider.notifier).request();
    };
    tray.onOpenSidePanel = () {
      unawaited(ref.read(sidePanelServiceProvider.notifier).open());
    };
    tray.onActionNeededTap = (key) {
      // A blocked Auto-Paste permission is handled where it broke, not in
      // settings: run the same recovery the failed-paste notification and
      // the in-app toast offer. Sending the user to a settings page to find
      // the fix themselves is what made this flow feel unguided, and the
      // tray is the surface that outlives the other two — a notification
      // expires, so this entry is often the only one still there when the
      // user gets around to acting.
      if (key == kTrayPastePermissionActionNeededKey) {
        unawaited(
          ref
              .read(pasteCapabilityNotifierProvider.notifier)
              .runMissingPermissionRecovery(
                confirmReset: () => confirmTccEntryReset(
                  l10n: l10nForLocaleCode(
                    ref.read(settingsProvider).value?.locale,
                  ),
                ),
              ),
        );
        return;
      }
      // Every other action-needed item is a paste failure the user resolves
      // by changing a setting (no target app, elevation, unknown), so those
      // still jump to the Auto-Paste settings and its capability indicator.
      if (key == kTrayPasteActionNeededKey) {
        ref
            .read(settingsScrollTargetProvider.notifier)
            .set('text-after-dictation-action');
        ref.read(activePageProvider.notifier).setPage('settings');
      }
    };
  }

  /// Shows or clears the tray's permission entry for a status transition.
  /// Clearing is keyed, so an unrelated paste-failure entry is left alone.
  void _syncPermissionTrayEntry(
    PasteCapabilityStatus? previous,
    PasteCapabilityStatus? next,
  ) {
    final tray = ref.read(trayServiceProvider.notifier);
    switch (trayPermissionChangeFor(previous, next)) {
      case TrayPermissionChange.show:
        final l10n = l10nForLocaleCode(
          ref.read(settingsProvider).value?.locale,
        );
        final entry = trayPermissionEntryFor(l10n, defaultTargetPlatform);
        tray.setActionNeeded(
          label: entry.label,
          tooltip: 'WhisPaste — ${entry.label}',
          menuItemKey: entry.key,
        );
      case TrayPermissionChange.clear:
        tray.clearActionNeeded(
          ifKey: trayPermissionEntryFor(
            l10nForLocaleCode(ref.read(settingsProvider).value?.locale),
            defaultTargetPlatform,
          ).key,
        );
      case TrayPermissionChange.none:
        break;
    }
  }

  final _importInbox = FileImportInbox();

  void _onRemoteCommand(InstanceCommand command) {
    final orchestrator = ref.read(recordingOrchestratorProvider.notifier);
    switch (command) {
      case InstanceCommand.toggle:
        unawaited(
          _isInteractiveSnippetActive
              ? _stopOrAdvance()
              : orchestrator.toggleRecording(),
        );
      case InstanceCommand.start || InstanceCommand.stop:
        // `--start`/`--stop` (#1952): the toggle's two halves, each acting
        // only in its own phase, so a script can call either without
        // knowing the state. Starting goes through toggleRecording, which
        // already hints "still processing" while a transcription runs. A
        // running interactive snippet records its fields itself: `--stop`
        // ends the current field like the hotkey, `--start` does nothing.
        final recording = ref.read(recordingProvider).isRecording;
        if (!remoteCommandActs(command, recording: recording)) {
          _log.debug('Ignoring ${command.name}: recording=$recording');
        } else if (command == InstanceCommand.stop) {
          unawaited(_stopOrAdvance());
        } else if (!_isInteractiveSnippetActive) {
          unawaited(orchestrator.toggleRecording());
        }
      case InstanceCommand.cancel:
        unawaited(orchestrator.cancelRecording());
      case InstanceCommand.newsletterConfirmed:
        unawaited(_showNewsletterStatus());
      case InstanceCommand.focus:
        // Handled by SingleInstanceService.onSecondInstanceLaunched.
        break;
      case InstanceCommand.openFiles:
        // Handled by SingleInstanceService.onOpenFiles.
        break;
    }
  }

  /// Hands opened files to [_transcribeOpenedFiles] only while no onboarding
  /// is on top; until then [SingleInstanceService] keeps them (#1705).
  void _syncOpenFilesHandler() {
    if (!mounted) return;
    SingleInstanceService.deliverOpenFilesWhen(
      ready: !ref.read(onboardingSurfaceActiveProvider),
      handler: (paths) => unawaited(_transcribeOpenedFiles(paths)),
    );
  }

  /// The file manager asked to transcribe [paths] (#1684): bring the window
  /// up on the history and run the normal file import, the same path as
  /// "Add files" and a drop. Missing files and other types are refused there
  /// with the import's notice above the list.
  Future<void> _transcribeOpenedFiles(List<String> paths) async {
    ref.read(activePageProvider.notifier).setPage('history');
    try {
      await MacOSLifecycleChannel.setRegular();
      await windowManager.show();
      await windowManager.focus();
    } on Object catch (e) {
      _log.warning('Bringing the window up for opened files failed', e);
    }
    if (!mounted) {
      // The shell was rebuilt meanwhile (it is keyed by the colour set, which
      // changes when the onboarding closes): the new one takes the files.
      _log.info('Requeueing ${paths.length} opened file(s)');
      SingleInstanceService.requeueOpenFiles(paths);
      return;
    }
    // Counts only: paths are user content and stay out of the log.
    _log.info('Transcribing ${paths.length} opened file(s)');
    await importAudioFiles(ref, paths, source: ImportStartSource.openWith);
    if (!mounted) return;
    final refused = ref.read(audioImportRejectionsProvider).length;
    _log.info('Opened files done, $refused refused');
  }

  /// The newsletter confirmation page handed the user back: bring the window
  /// up on the Übersicht, where the newsletter card shows the answer, and
  /// ask the server at once (the user waits for it).
  ///
  /// Runs unawaited from the instance command, so a window call that fails
  /// is logged and the status is still asked (F17-5).
  Future<void> _showNewsletterStatus() async {
    ref.read(activePageProvider.notifier).setPage('overview');
    try {
      await MacOSLifecycleChannel.setRegular();
      await windowManager.show();
      await windowManager.focus();
    } on Object catch (e) {
      _log.warning('Bringing the window up for the newsletter failed', e);
    }
    await ref.read(newsletterSignupProvider.notifier).ask(immediate: true);
  }

  @override
  void dispose() {
    _removeWithdrawalKick?.call();
    SingleInstanceService.onRemoteCommand = null;
    SingleInstanceService.onOpenFiles = null;
    _importInbox.close();
    _hotkeySvc.releaseCallbacks(this);
    final watchdog = UiThreadWatchdog.instance;
    if (identical(watchdog.onSevereStall, _onSevereStall)) {
      watchdog.onSevereStall = null;
      watchdog.dispose();
    }
    feedbackWithdrawalRetry.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Recording orchestrator ──
    // Defer first init until after the first frame so the window paints fast.
    if (!_orchestratorInitialized) {
      _orchestratorInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(recordingOrchestratorProvider);
      });
    } else {
      ref.watch(recordingOrchestratorProvider);
    }

    ref.listen<RecordingPhase>(recordingPhaseProvider, (prev, next) {
      _syncCancelDictationEscapeKey(prev ?? RecordingPhase.idle, next);
      // Overlay E: a recording that goes on to transcription is a finished
      // dictation, however it was stopped.
      if (prev == RecordingPhase.recording &&
          (next == RecordingPhase.transcribing ||
              next == RecordingPhase.refining)) {
        unawaited(
          ref.read(overlayHintLearningProvider.notifier).recordCompleted(),
        );
      }
    });

    // A permission that flips at runtime (revoked, or granted after a
    // recheck) shows up in the tray entry without waiting for a paste.
    ref.listen<PasteCapabilityState>(pasteCapabilityNotifierProvider, (
      prev,
      next,
    ) {
      _syncPermissionTrayEntry(
        prev?.capability?.status,
        next.capability?.status,
      );
    });

    // The tray menu follows the app language on every change in Settings,
    // not only with the next recording state change.
    ref.listen<Locale>(localeProvider, (prev, next) {
      ref
          .read(trayServiceProvider.notifier)
          .updateLocalizations(l10nForLocaleCode(next.languageCode));
    });

    // ── Keep the keepAlive service providers alive for the app lifetime ──
    ref.watch(trayServiceProvider);
    ref.watch(hotkeyServiceProvider);
    // Linux: an installed GNOME shortcut follows the hotkey setting.
    ref.watch(desktopShortcutSyncProvider);
    ref.watch(autostartServiceProvider);
    ref.watch(floatingButtonServiceProvider);
    ref.watch(floatingOverlayServiceProvider);
    // Without this watch, nothing in production ever reads
    // sidePanelServiceProvider, so it gets disposed immediately after each
    // native hover-trigger call -- tearing down its onControllerReady
    // ref.listen subscriptions and losing the row-content maps between
    // open() and the next row click.
    //
    // Gated on the setting on purpose, not just watched unconditionally: a
    // user who turns the panel off wants its native edge sensors gone, not
    // merely unreachable. Dropping the watch lets the (autoDispose) provider
    // tear down through the same disposeController -> controller.dispose()
    // path a hover-triggered auto-dispose already exercises; flipping the
    // setting back on re-runs build() and recreates the native host.
    //
    // Never during onboarding: an empty history panel sliding in from the
    // screen edge before the first dictation only distracts (maintainer,
    // 2026-10-30). It comes up once onboarding is completed.
    final sidePanelEnabled = ref.watch(
      settingsProvider.select((s) {
        final settings = s.value;
        return settings != null &&
            settings.onboarding.onboardingCompleted &&
            settings.interface_.sidePanelEnabled;
      }),
    );
    if (sidePanelEnabled) {
      ref.watch(sidePanelServiceProvider);
    }
    ref
        .read(trayServiceProvider.notifier)
        .setSidePanelAvailable(sidePanelEnabled);
    // Registers the clipEntryDetected method-call handler for the native
    // clipboard monitors (issues 04-06); same keepAlive rationale as above.
    ref.watch(clipboardHistoryMonitorServiceProvider);

    return widget.child;
  }
}
