/// Listens to recording state changes and triggers side effects:
/// sound feedback, toasts, tray icon updates, and auto-reset timers.
///
/// Also owns the stuck-state watchdog that auto-recovers if the pipeline
/// stays in "done" for >15 seconds.
///
/// Place this inside [WpServiceBootstrap] and wrap the main layout.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/selectable_speech_models.dart';
import '../core/navigation/page_state.dart'
    show
        activePageProvider,
        notesEditorTargetProvider,
        settingsScrollTargetProvider;
import '../core/config/settings_enums.dart';
import '../core/config/settings_provider.dart';
import '../core/onboarding/onboarding_surface.dart';
import '../features/onboarding/stt_model_readiness.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/recording/recording_helpers.dart';
import '../core/recording/recording_state.dart';
import '../services/clipboard_history/app_clipboard.dart';
import '../services/model_download_service.dart';
import '../services/pending_audio/pending_audio_queue.dart';
import '../services/stt_parakeet/parakeet_download_service.dart'
    show parakeetDownloadProvider;
import '../services/transcription/language_mismatch_hint.dart';
import '../services/stt_parakeet/parakeet_language_support.dart';
import '../services/paste/paste_capability_notifier.dart';
import '../services/paste/clipboard_unsaved_notifier.dart';
import '../services/paste/paste_failure_notifier.dart';
import '../services/paste/paster.dart';
import '../services/pending_audio/pending_audio_notice.dart';
import '../services/permissions/mic_permission_notifier.dart';
import '../services/recording_orchestrator.dart';
import '../services/sound_feedback_service.dart';
import '../services/stt/recovery_toast_notifier.dart';
import '../services/stt/stt_bundle.dart';
import '../services/tray_service.dart';
import '../services/window_activation.dart';
import 'oom_recovery_dialog.dart';
import 'toast.dart';
import '../core/config/settings_labels.dart';
import '../services/permissions/tcc_entry_reset_confirm.dart';
import 'wp_error_notice.dart';
import 'parakeet_language_notice.dart';

/// Shortens [text] to [maxChars] code points for the done-toast. Works on
/// runes rather than UTF-16 units so an emoji is never cut in half.
String transcriptPreview(String text, {int maxChars = 80}) {
  final runes = text.runes;
  if (runes.length <= maxChars) return text;
  return '${String.fromCharCodes(runes.take(maxChars))}…';
}

// ---------------------------------------------------------------------------
// Localization helpers (error / info codes → human-readable messages)
// ---------------------------------------------------------------------------

// Wp naming — deliberate exception for everything in this file except
// [WpRecordingBehavior] itself: the `Wp` prefix marks the shared *component*
// vocabulary of lib/widgets/ (types you instantiate, plus the `showWp*`
// launchers that are a component's own public API, e.g. showWpFormDialog).
// The free functions below are neither — they are pure code→string mappings,
// pure gate predicates, and call sites that pour recording-specific content
// into the already-prefixed [WpToast]. Prefixing them would claim they are
// components of the design system, which they are not.

/// Maps error codes from the recording orchestrator to localized messages.
///
/// [localModelInstalled] only changes the cloud network and timeout messages:
/// the offline hint (dictate with the local model) is shown only when a local
/// model is on disk to fall back to (UIA-FLW-05).
String localizeRecordingError(
  L10n l10n,
  String errorCode, {
  bool localModelInstalled = false,
}) {
  const factsChangedPrefix = 'selection_edit_facts_changed:';
  if (errorCode.startsWith(factsChangedPrefix)) {
    return l10n.errorSelectionEditFactsChangedValue(
      errorCode.substring(factsChangedPrefix.length),
    );
  }
  switch (errorCode) {
    case 'onboarding_not_completed':
      return l10n.errorOnboardingNotCompleted;
    case 'stt_model_not_found':
      return l10n.errorSttModelNotFound;
    case 'stt_model_unknown':
      return l10n.errorSttModelUnknown;
    case 'recording_failed':
      return l10n.errorRecordingFailed;
    case 'no_audio_recorded':
      return l10n.errorNoAudioRecorded;
    // Edit selection by voice (`.scratch/voice-selection-edit/`).
    case 'selection_edit_no_selection':
      return l10n.errorSelectionEditNoSelection;
    case 'selection_edit_check_timed_out':
      return l10n.smartModeCheckTimedOut;
    case 'selection_edit_no_engine':
      return l10n.errorSelectionEditNoEngine;
    case 'selection_edit_local_unavailable':
      return l10n.smartModeLocalUnavailable;
    case 'selection_edit_unsupported':
      return l10n.errorSelectionEditUnsupported;
    case 'selection_edit_copy_failed':
      return l10n.errorSelectionEditCopyFailed;
    case 'selection_edit_failed':
      return l10n.errorSelectionEditFailed;
    case 'selection_edit_facts_changed':
      return l10n.errorSelectionEditFactsChanged;
    case 'selection_edit_paste_failed':
      return l10n.errorSelectionEditPasteFailed;
    case 'transcription_empty':
      return l10n.errorTranscriptionEmpty;
    case 'stt_server_failed':
      return l10n.errorSttServerFailed;
    case 'stt_server_connection_lost':
      return l10n.errorSttServerConnectionLost;
    case 'stt_cuda_oom':
      return l10n.errorSttCudaOom;
    case 'recording_guard_failed':
      return l10n.recordingGuardFailed;
    case 'recording_auto_stopped':
      return l10n.recordingAutoStopped;
    case 'pipeline_timeout':
      return l10n.errorPipelineTimeout;
    case 'wav_file_not_created':
      return l10n.errorWavFileNotCreated;
    case 'wav_file_empty':
      return l10n.errorWavFileEmpty;
    case 'stt_start_timeout':
      return l10n.errorSttStartTimeout;
    case 'transcription_timeout':
      return l10n.errorTranscriptionTimeout;
    case 'mic_permission_denied':
      return l10n.errorMicPermissionDenied;
    case 'recording_start_failed':
      return l10n.errorRecordingStartFailed;
    case 'no_microphone':
      return l10n.errorNoMicrophone;
    case 'cloud_auth_error':
      return l10n.errorCloudAuth;
    case 'cloud_quota_exceeded':
      return l10n.errorCloudQuota;
    case 'quick_note_append_failed':
      return l10n.errorQuickNoteAppendFailed;
    case 'stt_model_corrupted':
      return l10n.errorSttModelCorrupted;
    case 'stt_model_file_missing':
    case 'parakeet_model_not_found':
    case 'whisper_model_not_found':
      return l10n.errorSttModelFileMissing;
    case 'stt_model_load_failed':
    case 'whisper_init_failed':
    case 'whisper_library_load_failed':
      return l10n.errorSttModelLoadFailed;
    case 'cloud_network_error':
      return localModelInstalled
          ? l10n.errorCloudNetworkLocal
          : l10n.errorCloudNetwork;
    case 'cloud_timeout':
      return localModelInstalled
          ? l10n.errorCloudTimeoutLocal
          : l10n.errorCloudTimeout;
    // Pre-flight reject keys emitted by `InferenceRequestValidator` via
    // the `InferenceClientRejected` exception. Dotted IDs (stable string
    // contract owned by the validator) → camelCase ARB getters.
    case 'stt.reject.empty':
      return l10n.errorSttRejectEmpty;
    case 'stt.reject.invalid_wav':
      return l10n.errorSttRejectInvalidWav;
    case 'stt.reject.unsupported_language':
      return l10n.errorSttRejectUnsupportedLanguage;
    case 'stt.reject.prompt_too_long':
      return l10n.errorSttRejectPromptTooLong;
    default:
      return l10n.errorGeneric;
  }
}

/// Maps info codes from the recording pipeline to localized messages.
String localizeRecordingInfo(L10n l10n, String infoCode) => switch (infoCode) {
  'info_engine_downloading' => l10n.infoEngineDownloading,
  'info_model_missing' => l10n.infoModelMissing,
  'info_pipeline_busy' => l10n.infoPipelineBusy,
  'info_stt_cuda_oom_model' => l10n.infoSttCudaOomFallbackModel,
  'info_stt_cuda_oom_cpu' => l10n.infoSttCudaOomFallbackCpu,
  'info_snippet_picker_empty' => l10n.infoSnippetPickerEmpty,
  // An unknown code is a bug on our side; the raw code is not user text.
  _ => l10n.errorGeneric,
};

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Label of the success toast shown when a run finishes. An edit-selection
/// run replaces text rather than transcribing it, so it gets its own label
/// (the recording target is kept after the run, see `startRecording`).
@visibleForTesting
String doneToastLabel(L10n l10n, RecordingTarget target) =>
    target == RecordingTarget.selectionEdit
    ? l10n.statusSelectionEdited
    : l10n.statusTranscriptionDone;

/// Invisible wrapper that reacts to [RecordingState] transitions.
class WpRecordingBehavior extends ConsumerStatefulWidget {
  const WpRecordingBehavior({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WpRecordingBehavior> createState() =>
      _WpRecordingBehaviorState();
}

class _WpRecordingBehaviorState extends ConsumerState<WpRecordingBehavior> {
  static final _log = AppLogger('RecordingBehavior');

  Timer? _doneResetTimer;
  Timer? _watchdogTimer;
  DateTime? _doneEnteredAt;
  bool _oomDialogOpen = false;

  /// Cached so [dispose] never touches `ref` (Riverpod forbids `ref` access
  /// after deactivation) — same defensive pattern as `TestRecordingStep`.
  RecordingOrchestrator? _orchestrator;

  @override
  void initState() {
    super.initState();
    // Quick-note completion → window forward, Notizen area, target note.
    // Registered here rather than in `NotesPage` because the reaction has to
    // work while the Notizen area is *not* on screen, which is the normal
    // case for a hotkey pressed in another app.
    _orchestrator = ref.read(recordingOrchestratorProvider.notifier);
    _orchestrator!.onQuickNoteAppended = _onQuickNoteAppended;
    // Watchdog: detect and auto-recover if state stuck in "done" for >15s.
    _watchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkStuckDone();
    });

    // GPU auto-disabled after a hard load crash (crash-loop breaker, see
    // gpu_load_crash_guard.dart) — surfaced once via the same recovery-toast
    // bridge used for exhausted/vcRuntimeMissing/abiInfo above. Post-frame
    // so the `ref.listen` registered in build() below is already attached
    // before `.report()` changes the notifier's state: `ref.listen` only
    // reacts to changes AFTER registration, not a value already set during
    // `recoverFromGpuLoadCrash` (which runs pre-`runApp()`, before any
    // listener exists).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final guard = ref.read(gpuLoadCrashGuardProvider);
      if (guard.consumePendingUserNotice()) {
        ref
            .read(recoveryToastNotifierProvider.notifier)
            .report(RecoveryToastKind.gpuLoadCrashDisabled);
      } else if (guard.consumePendingCudaNotice()) {
        ref
            .read(recoveryToastNotifierProvider.notifier)
            .report(RecoveryToastKind.cudaLoadCrashDisabled);
      }
      // A notice reported before this widget listened (startup recovery) is
      // re-raised: clearing and reporting again is a state change the listener
      // in build() reacts to.
      final pendingAudio = ref.read(pendingAudioNoticeProvider);
      if (pendingAudio != null) {
        final notifier = ref.read(pendingAudioNoticeProvider.notifier)..clear();
        notifier.report(pendingAudio);
      }
    });
  }

  @override
  void dispose() {
    _orchestrator?.onQuickNoteAppended = null;
    _doneResetTimer?.cancel();
    _watchdogTimer?.cancel();
    super.dispose();
  }

  void _onQuickNoteAppended(String noteId) =>
      unawaited(reactToQuickNoteAppended(context, ref, noteId));

  void _checkStuckDone() {
    try {
      final state = ref.read(recordingProvider);
      if (state.isDone) {
        _doneEnteredAt ??= DateTime.now();
        final stuck = DateTime.now().difference(_doneEnteredAt!);
        if (stuck.inSeconds >= 15) {
          _log.warning(
            'Watchdog: state stuck in done for ${stuck.inSeconds}s — force reset',
          );
          ref.read(recordingOrchestratorProvider.notifier).reset();
          _doneEnteredAt = null;
        }
      } else {
        _doneEnteredAt = null;
      }
    } catch (e) {
      _log.debug('Recording watchdog check skipped (provider not ready): $e');
    }
  }

  Future<void> _showPendingOomRecovery(L10n l10n) async {
    if (!mounted || _oomDialogOpen) return;

    final pending = ref.read(oomRecoveryPendingProvider);
    if (!pending.pending) return;

    _oomDialogOpen = true;
    ref.read(oomRecoveryPendingProvider.notifier).clear();

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final currentModelName = displayNameForModel(
      settings.effectiveModelId,
      l10n,
    );
    final nextModelName = pending.nextModelId == null
        ? null
        : displayNameForModel(pending.nextModelId!, l10n);

    if (ref.read(recordingOrchestratorProvider.notifier).oomAttemptCount > 0) {
      WpToast.show(
        context,
        message: l10n.oomRecoveryAttemptFailed(currentModelName),
        type: WpToastType.warning,
        duration: const Duration(seconds: 4),
      );
    }

    try {
      final choice = await showWpOomRecoveryDialog(
        context: context,
        l10n: l10n,
        modelName: nextModelName,
        hasCloudConfigured: pending.hasCloudConfigured,
        isPermanentFail: pending.isPermanentFail,
        cloudProviderName: pending.cloudProviderName,
      );

      if (!mounted) return;

      final orchestrator = ref.read(recordingOrchestratorProvider.notifier);
      switch (choice ?? WpOomRecoveryChoice.cancel) {
        case WpOomRecoveryChoice.trySmallerModel:
          if (pending.nextModelId == null || nextModelName == null) {
            if (mounted) {
              showOomNoSmallerModelToast(context: context, l10n: l10n);
            }
            break;
          }
          final didSwitch = await orchestrator.applyOomModelFallback(
            pending.nextModelId!,
          );
          if (!mounted) break;
          if (!didSwitch) {
            showOomNoSmallerModelToast(context: context, l10n: l10n);
            break;
          }
          WpToast.show(
            context,
            message: l10n.oomRecoveryDowngrading(nextModelName),
            type: WpToastType.info,
            duration: const Duration(seconds: 4),
          );
          break;
        case WpOomRecoveryChoice.switchToCloud:
          final provider = await orchestrator.switchToConfiguredCloudStt();
          if (!mounted) break;
          if (provider != null) {
            WpToast.show(
              context,
              message: l10n.oomRecoverySwitchingCloud,
              type: WpToastType.info,
              duration: const Duration(seconds: 4),
            );
          } else {
            _openSettings('stt-model');
          }
          break;
        case WpOomRecoveryChoice.openSettings:
          _openSettings('stt-model');
          break;
        case WpOomRecoveryChoice.cancel:
          break;
      }
    } finally {
      _oomDialogOpen = false;
    }
  }

  /// Makes [code] the fixed STT language, as the user chose in the hint.
  void _switchLanguage(String code) {
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(stt: s.stt.copyWith(language: code)),
          ),
    );
  }

  void _switchEngineToWhisper() {
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              stt: s.stt.copyWith(engine: OnDeviceEngine.whisper.value),
            ),
          ),
    );
  }

  void _openSettings(String target) {
    // The final onboarding step's test recording runs the real pipeline
    // (see TestRecordingStep), so this action can fire while the onboarding
    // overlay still covers the app — switching the page alone would leave it
    // invisible underneath. Issue #78.
    if (ref.read(onboardingSurfaceActiveProvider)) {
      unawaited(leaveOnboardingSurface(ref));
    }
    ref.read(settingsScrollTargetProvider.notifier).set(target);
    ref.read(activePageProvider.notifier).setPage('settings');
  }

  /// The "Open Settings" action of an error toast, deep-linked to the matching
  /// row. Within onboarding a missing model goes back to the model step
  /// (same as the info toast, UIA-RT-01). `null` when the code has no fix.
  VoidCallback? _settingsRecoveryAction(String errorCode) {
    final provider =
        ref.read(settingsProvider).value?.sttProviderType ??
        SttProviderType.onDevice;
    final row = settingsRowForRecordingError(errorCode, provider);
    if (row == null) return null;
    if (row == 'stt-model' && ref.read(onboardingSurfaceActiveProvider)) {
      return () =>
          ref.read(onboardingModelStepRequestProvider.notifier).request();
    }
    return () => _openSettings(row);
  }

  void _handleErrorState(BuildContext context, L10n l10n, RecordingState next) {
    try {
      ref.read(soundFeedbackProvider.notifier).playError();
    } catch (e) {
      _log.warning('Error sound playback failed (non-fatal)', e);
    }
    showRecordingErrorToast(
      context: context,
      l10n: l10n,
      errorCode: next.errorMessage!,
      onDismiss: () => ref.read(recordingOrchestratorProvider.notifier).reset(),
      openMicrophoneSettings: _openMicrophoneSettings,
      openSettings: _settingsRecoveryAction(next.errorMessage!),
      retry: isRepeatableTranscriptionError(next.errorMessage!)
          ? () => unawaited(_retryKeptDictation(l10n))
          : null,
      copyTranscript: next.transcript == null
          ? null
          : () => unawaited(AppClipboard.setText(next.transcript!)),
      localModelInstalled: ref.read(onboardingSttModelInstalledProvider),
    );
    // Auto-reset after toast display so FAB returns to idle.
    Future.delayed(const Duration(seconds: 5), () {
      try {
        if (mounted && ref.read(recordingProvider).isError) {
          _log.debug('Error auto-reset timer fired');
          ref.read(recordingOrchestratorProvider.notifier).reset();
        }
      } catch (e) {
        _log.warning('Error auto-reset failed', e);
      }
    });
  }

  /// Transcribes the kept dictation again (UIA-FLW-01). Only a failure is
  /// reported; a success lands in the history like any other dictation.
  Future<void> _retryKeptDictation(L10n l10n) async {
    final outcome = await ref
        .read(recordingOrchestratorProvider.notifier)
        .retryKeptDictation();
    if (outcome == PendingRetryOutcome.failed && mounted) {
      WpToast.show(
        context,
        message: l10n.pendingRetryFailed,
        type: WpToastType.error,
        duration: const Duration(seconds: 5),
      );
    }
  }

  void _handleDoneState(BuildContext context, L10n l10n, RecordingState next) {
    _log.debug('State → done, scheduling sound + toast + 2s reset');
    // Skip the success chime and toast when the paste/insert attempt for this
    // recording already failed — the error tone and the error toast (raised
    // where the failure was reported) have already told the user something
    // went wrong; a success signal right after them would contradict it and
    // the success toast would even replace the error toast (XP-5-07).
    if (!next.pasteFailed) {
      try {
        ref.read(soundFeedbackProvider.notifier).playTranscriptionComplete();
      } catch (e) {
        _log.error('Success sound playback failed (non-fatal)', e);
      }
      WpToast.show(
        context,
        message:
            '${doneToastLabel(l10n, ref.read(recordingTargetProvider))} — ${transcriptPreview(next.transcript!)}',
        type: WpToastType.success,
      );
    }
    // Auto-reset after a short delay so the FAB returns to idle.
    // Guard on isDone: if the user already preempted the linger by starting a
    // new recording (orchestrator.startRecording resets done → idle → recording),
    // this stale timer must NOT reset the fresh recording.
    _doneResetTimer?.cancel();
    _doneResetTimer = Timer(const Duration(seconds: 2), () {
      try {
        if (mounted && ref.read(recordingProvider).isDone) {
          _log.debug('Done reset timer fired — calling reset()');
          ref.read(recordingOrchestratorProvider.notifier).reset();
          _log.debug('Done reset completed');
        }
      } catch (e, st) {
        _log.error('Done reset timer error', e, st);
      }
    });
  }

  void _onRecordingStateChanged(
    BuildContext context,
    L10n l10n,
    RecordingState? prev,
    RecordingState next,
  ) {
    final tray = ref.read(trayServiceProvider.notifier);
    tray.updateRecordingState(next, l10n: l10n);

    if (next.isError && next.errorMessage != null) {
      _handleErrorState(context, l10n, next);
    } else if (next.isRecording && (prev == null || !prev.isRecording)) {
      try {
        ref.read(soundFeedbackProvider.notifier).playRecordStart();
      } catch (e) {
        _log.warning('Record-start sound failed (non-fatal)', e);
      }
    } else if (next.isTranscribing && (prev == null || !prev.isTranscribing)) {
      try {
        ref.read(soundFeedbackProvider.notifier).playRecordStop();
      } catch (e) {
        _log.warning('Record-stop sound failed (non-fatal)', e);
      }
    } else if (next.isDone && next.transcript != null) {
      _handleDoneState(context, l10n, next);
    } else if (next.isIdle && prev != null && !prev.isIdle) {
      _log.debug('State → idle (from ${prev.phase})');
      _doneResetTimer?.cancel();
      Future.microtask(() => _showPendingOomRecovery(l10n));
    }
  }

  void _onRecordingInfoChanged(BuildContext context, L10n l10n, String? next) {
    if (next == null) return;
    // A known model that is merely not on disk gets the download itself as
    // the action — the detour through Settings only remains for the cases
    // where there is nothing concrete to download.
    final missingModel = next == 'info_model_missing'
        ? ref.read(missingSelectedSpeechModelProvider)
        : null;
    // Info codes that leave the user with an obvious open question must
    // carry the last logical step as a one-tap action instead of leaving
    // them to hunt for it: "download in Settings" jumps to the STT section,
    // and the empty-snippet-list fallback jumps to the Snippets page.
    final (
      WpToastType type,
      Duration duration,
      WpToastAction? action,
    ) = switch (next) {
      'info_model_missing' when missingModel != null => (
        WpToastType.warning,
        const Duration(seconds: 10),
        // loam-ignore: a11y-interactive-semantics – WpToastAction is a data class; label is the button text
        WpToastAction(
          label: l10n.infoModelMissingDownload,
          // Whisper file or Parakeet bundle alike (UIA-MDL-GATE b).
          onPressed: () => unawaited(
            downloadSpeechModel(
              model: missingModel,
              whisper: ref.read(modelDownloadProvider.notifier),
              parakeet: ref.read(parakeetDownloadProvider.notifier),
            ),
          ),
        ),
      ),
      // Inside the onboarding flow the model step is the place to fix this,
      // so the action goes there instead of out to Settings (UIA-RT-01).
      'info_model_missing' when ref.read(onboardingSurfaceActiveProvider) => (
        WpToastType.info,
        const Duration(seconds: 6),
        // loam-ignore: a11y-interactive-semantics – WpToastAction is a data class; label is the button text
        WpToastAction(
          label: l10n.onboardingReadyBackToModel,
          onPressed: () =>
              ref.read(onboardingModelStepRequestProvider.notifier).request(),
        ),
      ),
      'info_model_missing' => (
        WpToastType.info,
        const Duration(seconds: 6),
        // loam-ignore: a11y-interactive-semantics – WpToastAction is a data class; label is the button text
        WpToastAction(
          label: l10n.pasteFailureOpenSettings,
          onPressed: () => _openSettings('stt-model'),
        ),
      ),
      // Trigger word matched but the snippet list is empty — the
      // transcript was pasted normally (see `_tryDispatchSnippetPicker`),
      // which without this warning is indistinguishable from "the
      // trigger didn't work".
      'info_snippet_picker_empty' => (
        WpToastType.warning,
        const Duration(seconds: 6),
        // loam-ignore: a11y-interactive-semantics – WpToastAction is a data class; label is the button text
        WpToastAction(
          label: l10n.infoSnippetPickerEmptyAction,
          onPressed: _openSnippets,
        ),
      ),
      _ => (WpToastType.info, const Duration(seconds: 4), null),
    };
    WpToast.show(
      context,
      message: missingModel != null
          ? l10n.infoModelMissingSelected(missingModel.sizeLabel)
          : localizeRecordingInfo(l10n, next),
      type: type,
      duration: duration,
      action: action,
    );
    Future.microtask(() => ref.read(recordingInfoProvider.notifier).clear());
  }

  void _openSnippets() {
    // Same reasoning as _openSettings above: this can fire from within the
    // onboarding test recording, and the overlay would otherwise swallow it.
    if (ref.read(onboardingSurfaceActiveProvider)) {
      unawaited(leaveOnboardingSurface(ref));
    }
    ref.read(activePageProvider.notifier).setPage('snippets');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // ── Recording state transitions ──
    ref.listen<RecordingState>(
      recordingProvider,
      (prev, next) => _onRecordingStateChanged(context, l10n, prev, next),
    );

    // ── Info notifications (soft preflight, auto-download) ──
    ref.listen<String?>(
      recordingInfoProvider,
      (prev, next) => _onRecordingInfoChanged(context, l10n, next),
    );

    // ── Paste failures (silent before — now surfaced with action) ──
    ref.listen<PasteFailureEvent?>(pasteFailureNotifierProvider, (prev, next) {
      if (next == null) return;
      _showPasteFailureToast(context, l10n, next.outcome);
      Future.microtask(
        () => ref.read(pasteFailureNotifierProvider.notifier).clear(),
      );
    });

    // ── Previous clipboard could not be kept (macOS pasteboard privacy) ──
    ref.listen<bool>(clipboardUnsavedNotifierProvider, (prev, next) {
      if (!next) return;
      _showClipboardUnsavedToast(context, l10n);
      Future.microtask(
        () => ref.read(clipboardUnsavedNotifierProvider.notifier).clear(),
      );
    });

    // ── Audio kept for a history save (save failed, or kept from an earlier start) ──
    ref.listen<PendingAudioNotice?>(pendingAudioNoticeProvider, (prev, next) {
      if (next == null) return;
      _showPendingAudioToast(context, l10n, next);
      Future.microtask(
        () => ref.read(pendingAudioNoticeProvider.notifier).clear(),
      );
    });

    // ── Server-binary recovery outcomes (issue #07 actionable toast) ──
    ref.listen<RecoveryToastEvent?>(recoveryToastNotifierProvider, (
      prev,
      next,
    ) {
      if (next == null) return;
      _showRecoveryToast(context, l10n, next.kind);
      Future.microtask(
        () => ref.read(recoveryToastNotifierProvider.notifier).clear(),
      );
    });

    // ── Wrong-language hint (9.10): offer a switch, never switch silently ──
    ref.listen<LanguageMismatchHint?>(languageMismatchHintProvider, (
      prev,
      next,
    ) {
      if (next == null) return;
      showLanguageMismatchToast(
        context: context,
        l10n: l10n,
        onSwitch: () => _switchLanguage(next.detected),
      );
      Future.microtask(
        () => ref.read(languageMismatchHintProvider.notifier).clear(),
      );
    });

    // ── Parakeet cannot transcribe the chosen language (SW-05) ──
    ref.listen<ParakeetLanguageNotice?>(parakeetLanguageNoticeProvider, (
      prev,
      next,
    ) {
      if (next == null) return;
      showWpParakeetLanguageToast(
        context: context,
        l10n: l10n,
        languageCode: next.languageCode,
        onSwitch: _switchEngineToWhisper,
      );
      Future.microtask(
        () => ref.read(parakeetLanguageNoticeProvider.notifier).clear(),
      );
    });

    // ── CPU-fallback status (issue #01: surface the silent auto-degrade) ──
    ref.listen<SttStatus>(localSttBundleProvider, (prev, next) {
      if (shouldShowCpuFallbackToast(prev, next)) {
        showCpuFallbackToast(context: context, l10n: l10n);
      }
    });

    return widget.child;
  }

  void _showRecoveryToast(
    BuildContext context,
    L10n l10n,
    RecoveryToastKind kind,
  ) {
    showRecoveryToast(
      context: context,
      l10n: l10n,
      kind: kind,
      openSettings: _openSettings,
    );
  }

  void _showPendingAudioToast(
    BuildContext context,
    L10n l10n,
    PendingAudioNotice notice,
  ) {
    final saveLater = notice == PendingAudioNotice.saveLater;
    WpToast.show(
      context,
      message: saveLater
          ? l10n.pendingAudioSaveLater
          : l10n.pendingAudioRecovered,
      type: saveLater ? WpToastType.warning : WpToastType.info,
    );
  }

  void _showPasteFailureToast(
    BuildContext context,
    L10n l10n,
    PasteOutcome outcome,
  ) {
    // Same three-way routing the failed-paste OS notification uses (see
    // `recording_orchestrator.dart`) — the two surfaces fire for one and the
    // same failure, so offering different recoveries would be a bug.
    final capNotifier = ref.read(pasteCapabilityNotifierProvider.notifier);
    showPasteFailureToast(
      context: context,
      l10n: l10n,
      outcome: outcome,
      openAccessibilitySettings: _openAccessibilitySettings,
      openAutoPasteSettings: () => _openSettings('text-after-dictation-action'),
      resetEntryAndGrant: capNotifier.staleEntryResetCandidate
          ? () => capNotifier.repairAndRequestGrant(
              confirmReset: () => confirmTccEntryReset(l10n: l10n),
            )
          : null,
      staleEntry: capNotifier.grantDidNotTakeEffect,
      linuxNoDevice:
          ref.read(pasteCapabilityNotifierProvider).capability?.status ==
          PasteCapabilityStatus.unsupported,
    );
  }

  /// Calm, non-blocking, shown once per session: the paste itself worked, only
  /// the previous clipboard content could not be kept.
  void _showClipboardUnsavedToast(BuildContext context, L10n l10n) {
    WpToast.show(
      context,
      message: l10n.pasteClipboardUnsavedHint,
      type: WpToastType.info,
      duration: const Duration(seconds: 8),
      action: WpToastAction(
        label: l10n.pasteClipboardUnsavedAction,
        onPressed: () => unawaited(_openPrivacySettings()),
        testId: 'clipboard-unsaved-toast-action',
      ),
    );
  }

  Future<void> _openPrivacySettings() async {
    if (!Platform.isMacOS) return;
    final uri = Uri.parse(
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard',
    );
    try {
      await launchUrl(uri);
    } on Exception catch (e) {
      _log.warning('Could not open privacy settings', e);
    }
  }

  Future<void> _openAccessibilitySettings() async {
    if (!Platform.isMacOS) return;
    final uri = Uri.parse(
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    );
    try {
      await launchUrl(uri);
    } on Exception catch (e) {
      _log.warning('Could not open Accessibility settings', e);
    }
  }

  Future<void> _openMicrophoneSettings() =>
      ref.read(micPermissionNotifierProvider.notifier).openSystemSettings();
}

// ---------------------------------------------------------------------------
// Quick-note completion reaction — a free function rather than a private
// method so it can be exercised against real providers through a two-line
// `Consumer` harness, without bootstrapping the whole [WpRecordingBehavior]
// (same testability motive as the injected seams on the toast helpers below).
// ---------------------------------------------------------------------------

/// What a finished quick-note append does (UIA-SHL-08). By default the note is
/// saved in the background and a toast offers "Open note"; the main window
/// stays where it is. With the setting "Notizen im Hauptfenster öffnen" on, the
/// window comes forward and opens the note at once ([openQuickNoteInEditor]).
Future<void> reactToQuickNoteAppended(
  BuildContext context,
  WidgetRef ref,
  String noteId,
) async {
  final settings = await ref.read(settingsProvider.future);
  if (settings.quickNoteHotkey.openNoteInMainWindow) {
    openQuickNoteInEditor(ref, noteId);
    return;
  }
  if (!context.mounted) return;
  final l10n = L10n.of(context);
  WpToast.show(
    context,
    message: l10n.quickNoteToastSaved,
    type: WpToastType.success,
    action: WpToastAction(
      label: l10n.quickNoteToastOpenNote,
      testId: 'quick-note-toast-open-note',
      onPressed: () => openQuickNoteInEditor(ref, noteId),
    ),
  );
}

/// Brings the window forward, aims the Notizen area at [noteId] and switches
/// to it.
///
/// Only ever reached from the quick-note path — the ordinary dictation target
/// (main hotkey, tray, shelf button, floating button) has no equivalent hook
/// and keeps its current, jump-free behaviour. The window activation is
/// fire-and-forget: navigation must not wait on a platform channel, and a
/// failed activation is logged inside [activateWindow], never thrown.
///
/// The target is set *before* the page switch, so a `NotesPage` that mounts as
/// a result already finds it during its first frame.
void openQuickNoteInEditor(WidgetRef ref, String noteId) {
  unawaited(ref.read(windowActivatorProvider)());
  ref.read(notesEditorTargetProvider.notifier).set(noteId);
  ref.read(activePageProvider.notifier).setPage('notes');
}

/// Cause and next step for a recording error, shown as a [WpErrorNotice].
class WpRecordingErrorNotice {
  const WpRecordingErrorNotice({required this.cause, required this.nextStep});

  final String cause;
  final String nextStep;
}

/// The cause-and-next-step copy for the recording errors that have one.
///
/// Covers a missing speech model, a denied microphone, a failed transcription
/// and the GPU-to-CPU fallback. Other codes return `null` and keep the
/// one-line [localizeRecordingError] text.
WpRecordingErrorNotice? recordingErrorNotice(L10n l10n, String errorCode) {
  return switch (errorCode) {
    'stt_model_not_found' => WpRecordingErrorNotice(
      cause: l10n.errorNoticeNoModelCause,
      nextStep: l10n.errorNoticeNoModelNext,
    ),
    'mic_permission_denied' => WpRecordingErrorNotice(
      cause: l10n.errorNoticeMicCause,
      nextStep: l10n.errorNoticeMicNext,
    ),
    'stt_server_failed' ||
    'stt_server_connection_lost' => WpRecordingErrorNotice(
      cause: l10n.errorNoticeTranscribeCause,
      nextStep: l10n.errorNoticeTranscribeNext,
    ),
    _ => null,
  };
}

// ---------------------------------------------------------------------------
// Recording-error toast — extracted the same way as [showPasteFailureToast]
// below so widget tests can exercise the mic-permission-denied action wiring
// directly without bootstrapping the full WpRecordingBehavior.
//
// Unprefixed on purpose (see the Wp-naming note at the top of this file):
// this and the toast helpers that follow are call sites of [WpToast],
// not components of their own.
// ---------------------------------------------------------------------------

/// Renders the actionable toast for a recording-pipeline error.
///
/// `mic_permission_denied` on macOS gets an "Open Settings" action
/// (Microphone privacy pane deep-link) instead of the generic dismiss.
/// Once macOS has denied mic access once, `AVCaptureDevice.requestAccess`
/// (called by `record`'s `hasPermission()`) will never show the system
/// dialog again — the user has to grant it manually in System Settings, so
/// the toast needs to route them there directly instead of leaving them
/// stuck on a dead-end "microphone access needed" message with nothing
/// actionable to do about it. Every other error code keeps the plain
/// dismiss action.
///
/// [openMicrophoneSettings] is injected so widget tests can substitute a
/// spy, mirroring [showPasteFailureToast]'s `openAccessibilitySettings`.
///
/// Recovery actions (UIA-FLW-02, UIA-FLW-03): a missing model or a cloud auth
/// failure offers "Open Settings" when [openSettings] is given (the caller
/// deep-links to the matching row, see [settingsRowForRecordingError]); a
/// failed quick-note append offers "Copy text" when [copyTranscript] is given.
void showRecordingErrorToast({
  required BuildContext context,
  required L10n l10n,
  required String errorCode,
  required VoidCallback onDismiss,
  VoidCallback? openMicrophoneSettings,
  VoidCallback? openSettings,
  VoidCallback? copyTranscript,
  VoidCallback? retry,
  bool localModelInstalled = false,
}) {
  final offerSettings =
      errorCode == 'mic_permission_denied' && Platform.isMacOS;
  // The caller passes [openSettings] only for codes that have a settings row.
  final offerSettingsRecovery = openSettings != null;
  final offerCopy =
      copyTranscript != null && errorCode == 'quick_note_append_failed';
  final notice = recordingErrorNotice(l10n, errorCode);
  final (String actionLabel, VoidCallback onAction) = retry != null
      ? (l10n.actionRetry, retry)
      : offerSettings
      ? (l10n.pasteFailureOpenSettings, openMicrophoneSettings ?? onDismiss)
      : offerSettingsRecovery
      ? (l10n.pasteFailureOpenSettings, openSettings)
      : offerCopy
      ? (l10n.historyCopyText, copyTranscript)
      : (l10n.actionDismiss, onDismiss);
  WpToast.show(
    context,
    message: notice == null
        ? localizeRecordingError(
            l10n,
            errorCode,
            localModelInstalled: localModelInstalled,
          )
        : '${notice.cause} ${notice.nextStep}',
    body: notice == null
        ? null
        : WpErrorNotice(cause: notice.cause, nextStep: notice.nextStep),
    type: WpToastType.error,
    duration: const Duration(seconds: 5),
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// The Settings row a recovery action deep-links to for [errorCode] (UIA-FLW-03).
/// `null` when the error has no settings fix. A missing model goes to the
/// engine selector; a cloud auth failure goes to the key row of the configured
/// provider.
String? settingsRowForRecordingError(
  String errorCode,
  SttProviderType provider,
) => switch (errorCode) {
  'stt_model_not_found' ||
  'stt_model_corrupted' ||
  'stt_model_file_missing' ||
  'stt_model_unknown' ||
  'stt_model_load_failed' ||
  'parakeet_model_not_found' ||
  'whisper_model_not_found' ||
  'whisper_init_failed' ||
  'whisper_library_load_failed' => 'stt-model',
  'cloud_auth_error' when provider == SttProviderType.deepgram =>
    'speech-deepgram-key',
  'cloud_auth_error' => 'speech-openai-key',
  _ => null,
};

// ---------------------------------------------------------------------------
// Paste-failure toast — extracted the same way as [showRecoveryToast] /
// [showCpuFallbackToast] below, so widget tests can exercise the message
// selection directly without bootstrapping the full WpRecordingBehavior.
// ---------------------------------------------------------------------------

/// Renders the actionable toast for a [PasteOutcome] failure.
///
/// - [PasteOutcome.permissionMissing] → macOS only gets an "Open Settings"
///   action (Accessibility deep-link); no button on other platforms since
///   there's nothing to grant from inside the app.
/// - [PasteOutcome.elevationBlocked] → Windows-only UIPI case: the target
///   window runs elevated and WhisPaste doesn't. No action button — there
///   is no clean way to relaunch WhisPaste elevated from the running
///   process without significant new infrastructure (out of scope here), so
///   a clear, distinct informational message is the correct, honest outcome.
/// - [PasteOutcome.noTarget] → distinct message, no action.
/// - Everything else (`failed`, `platformUnavailable`, `blocked`, `success`)
///   falls back to the generic message.
///
/// [openAccessibilitySettings] is injected so widget tests can substitute a
/// spy, mirroring [showRecoveryToast]'s [showRecoveryToast.openSettings].
/// [resetEntryAndGrant] is the same seam for the entry-reset recovery: when
/// non-null it *replaces* the Settings deep-link as the permission action,
/// because on that build a plain trip to Settings can land the user on an
/// already-enabled toggle with nothing to do (see
/// [PasteCapabilityNotifier.grantRequiresEntryReset]).
///
/// [staleEntry] only swaps the copy, never the action. It is true when this
/// process has in-memory proof that a grant already happened and did not take
/// ([PasteCapabilityNotifier.grantDidNotTakeEffect]) — then the toast can name
/// the stale entry outright instead of repeating the generic "permission
/// missing" framing, which would misdescribe what the button is about to do.
/// Without that proof the generic copy stays, since a first-time user has no
/// old entry to be told about.
void showPasteFailureToast({
  required BuildContext context,
  required L10n l10n,
  required PasteOutcome outcome,
  VoidCallback? openAccessibilitySettings,
  VoidCallback? openAutoPasteSettings,
  VoidCallback? resetEntryAndGrant,
  bool staleEntry = false,
  bool linuxNoDevice = false,
}) {
  String message;
  String? actionLabel;
  VoidCallback? onAction;

  switch (outcome) {
    case PasteOutcome.permissionMissing:
      // The transcript stays on the clipboard after a failed paste, so the
      // copy says so and names the shortcut for the manual paste.
      message = l10n.pasteFailureClipboardCopy(pasteShortcutLabel(l10n: l10n));
      if (Platform.isMacOS) {
        actionLabel = l10n.pasteFailureCheckPermission;
        onAction = openAccessibilitySettings;
        if (resetEntryAndGrant != null) {
          actionLabel = l10n.pasteCapabilityRepairButton;
          onAction = resetEntryAndGrant;
          // The stale hint names the cause; the clipboard sentence still says
          // where the transcript is. Both belong in the one message.
          if (staleEntry) {
            message =
                '${l10n.pasteCapabilityRepairHint} '
                '${l10n.pasteFailureClipboardCopy(pasteShortcutLabel(l10n: l10n))}';
          }
        }
      }
      if (defaultTargetPlatform == TargetPlatform.linux) {
        // The uinput device is not accessible to this user. Nothing in the app
        // can grant that. The action opens the Auto-Paste settings, which show
        // the one-time command with its own copy button. Copying the command
        // here would overwrite the transcript that the failed paste left on the
        // clipboard (XP-5-06 follow-up).
        // Without any /dev/uinput node the udev rule cannot help, so the
        // toast says so instead of asking for the command (PAR-028).
        final hint = linuxNoDevice
            ? l10n.pasteFailureLinuxNoDeviceHint
            : l10n.pasteFailureLinuxUinputSettingsHint;
        message =
            '${l10n.pasteFailureClipboardCopy(pasteShortcutLabel(l10n: l10n))} '
            '$hint';
        actionLabel = l10n.pasteFailureOpenSettings;
        onAction = openAutoPasteSettings;
      }
    case PasteOutcome.elevationBlocked:
      message = l10n.pasteFailureElevationBlocked;
    case PasteOutcome.noTarget:
      message = l10n.pasteFailureNoTarget;
    case PasteOutcome.targetChanged:
      message = l10n.pasteFailureTargetChanged;
    case PasteOutcome.unconfirmed:
      message = l10n.pasteFailureUnconfirmed(pasteShortcutLabel(l10n: l10n));
    case PasteOutcome.unconfirmedNoBridge:
      // Never reported as a warning, see the orchestrator.
      return;
    case PasteOutcome.failed:
    case PasteOutcome.platformUnavailable:
    case PasteOutcome.blocked:
    case PasteOutcome.success:
      message = l10n.pasteFailureGeneric(pasteShortcutLabel(l10n: l10n));
  }

  WpToast.show(
    context,
    message: message,
    type: WpToastType.warning,
    duration: const Duration(seconds: 6),
    action: actionLabel == null || onAction == null
        ? null
        : WpToastAction(
            label: actionLabel,
            onPressed: onAction,
            testId: 'paste-failure-toast-action',
          ),
  );
}

// ---------------------------------------------------------------------------
// Recovery toast — extracted so widget tests can exercise the action
// wiring directly without bootstrapping the full WpRecordingBehavior.
// ---------------------------------------------------------------------------

/// Renders the PRD-spec actionable toast for a recovery outcome.
///
/// - [RecoveryToastKind.exhausted] → error toast + "Einstellungen
///   öffnen" action that calls [openSettings] with the
///   `'advanced'` deep-link target (which holds the Factory-Reset row in
///   `cloud_advanced_section.dart`).
/// - [RecoveryToastKind.abiInfo] → passive info toast (no action) — the
///   silent re-download is already in flight inside
///   `SttServerStateNotifier`.
/// - [RecoveryToastKind.gpuLoadCrashDisabled] → warning toast + "Einstellungen
///   öffnen" action targeting `'stt'` (the GPU-Beschleunigung row in
///   `stt_section.dart`) — see `gpu_load_crash_guard.dart`.
///
/// [openSettings] is injected so widget tests can substitute a spy and
/// assert that tapping the action fires the navigation request without
/// needing the full app shell (`activePageProvider` +
/// `settingsScrollTargetProvider` are private to the production wiring).
///
/// [installVcRuntime] is likewise injectable: it defaults to opening the
/// Microsoft VC++ Redistributable download in the browser, but tests pass
/// a spy to assert the action wiring without a real `launchUrl`.
void showRecoveryToast({
  required BuildContext context,
  required L10n l10n,
  required RecoveryToastKind kind,
  required void Function(String section) openSettings,
  VoidCallback? installVcRuntime,
}) {
  switch (kind) {
    case RecoveryToastKind.exhausted:
      WpToast.show(
        context,
        message: l10n.recoveryExhaustedToast,
        type: WpToastType.error,
        duration: const Duration(seconds: 8),
        // loam-ignore: a11y-interactive-semantics – WpToastAction is a data class; label is the button text
        action: WpToastAction(
          label: l10n.recoveryExhaustedAction,
          onPressed: () => openSettings('advanced'),
        ),
      );
    case RecoveryToastKind.vcRuntimeMissing:
      WpToast.show(
        context,
        message: l10n.recoveryVcRuntimeToast,
        type: WpToastType.error,
        duration: const Duration(seconds: 10),
        // loam-ignore: a11y-interactive-semantics – WpToastAction is a data class; label is the button text
        action: WpToastAction(
          label: l10n.recoveryVcRuntimeAction,
          onPressed: installVcRuntime ?? _openVcRuntimeDownload,
        ),
      );
    case RecoveryToastKind.abiInfo:
      WpToast.show(
        context,
        message: l10n.modelAbiInfoToast,
        type: WpToastType.info,
        duration: const Duration(seconds: 5),
      );
    case RecoveryToastKind.gpuLoadCrashDisabled:
      WpToast.show(
        context,
        message: l10n.recoveryGpuDisabledToast,
        type: WpToastType.warning,
        duration: const Duration(seconds: 8),
        // loam-ignore: a11y-interactive-semantics – WpToastAction is a data class; label is the button text
        action: WpToastAction(
          label: l10n.recoveryExhaustedAction,
          onPressed: () => openSettings('stt'),
        ),
      );
    case RecoveryToastKind.cudaLoadCrashDisabled:
      WpToast.show(
        context,
        message: l10n.recoveryCudaDisabledToast,
        type: WpToastType.warning,
        duration: const Duration(seconds: 8),
        // loam-ignore: a11y-interactive-semantics – WpToastAction is a data class; label is the button text
        action: WpToastAction(
          label: l10n.recoveryExhaustedAction,
          onPressed: () => openSettings('stt'),
        ),
      );
  }
}

// ---------------------------------------------------------------------------
// CPU-fallback status toast — issue #01. `SttStatus.cpuFallbackActive`
// already exists (set by the GPU-crash recovery path in
// `stt_server_state_notifier.dart`) but had no UI consumer. Extracted the
// same way as [showRecoveryToast] above so the transition-gating logic and
// the toast rendering can each be tested without mounting the full
// `WpRecordingBehavior` + `ref.listen` wiring.
// ---------------------------------------------------------------------------

/// Pure gate: decides whether a [SttStatus] transition should surface the
/// CPU-fallback toast. Only the `false → true` edge (or an initial `null`
/// previous status that is already active) fires — repeated emissions
/// while the fallback stays active (`true → true`) must NOT re-trigger a
/// duplicate toast, and returning to GPU (`true → false`) has no toast of
/// its own (the original toast simply auto-dismisses on its own timer).
bool shouldShowCpuFallbackToast(SttStatus? prev, SttStatus next) {
  final wasActive = prev?.cpuFallbackActive ?? false;
  return !wasActive && next.cpuFallbackActive;
}

/// Quiet hint that the spoken language differs from the fixed setting, with a
/// one-tap switch. Info tone, not an error: the transcript itself is fine.
///
/// Unprefixed on purpose, like the toast helpers above: a call site of
/// [WpToast], not a component of its own.
void showLanguageMismatchToast({
  required BuildContext context,
  required L10n l10n,
  required VoidCallback onSwitch,
}) {
  WpToast.show(
    context,
    message: l10n.languageMismatchHint,
    type: WpToastType.info,
    duration: const Duration(seconds: 6),
    actionLabel: l10n.languageMismatchSwitch,
    onAction: onSwitch,
  );
}

/// Renders the plain-language, dismissable info toast for the CPU-fallback
/// status. No action button: switching the GPU-acceleration setting cannot
/// undo a fallback that already happened for the current server process, so
/// no button is offered — a passive toast (like [RecoveryToastKind.abiInfo]
/// above) is all this needs.
void showCpuFallbackToast({required BuildContext context, required L10n l10n}) {
  WpToast.show(
    context,
    message: '${l10n.errorNoticeCpuCause} ${l10n.errorNoticeCpuNext}',
    body: WpErrorNotice(
      cause: l10n.errorNoticeCpuCause,
      nextStep: l10n.errorNoticeCpuNext,
    ),
    type: WpToastType.info,
    duration: const Duration(seconds: 5),
  );
}

/// "Try a smaller model" found no smaller model to switch to (UIA-SHL-06).
/// The dialog has already closed, so the reason and the next step stay on
/// screen as an error toast instead of the outcome being silent.
/// Wp naming: call site of WpToast, not a component (see wp_prefix_consistency_test).
void showOomNoSmallerModelToast({
  required BuildContext context,
  required L10n l10n,
}) {
  WpToast.show(
    context,
    message: l10n.oomRecoveryNoSmallerModel,
    type: WpToastType.error,
    duration: const Duration(seconds: 8),
  );
}

/// Microsoft's stable short-link to the latest x64 VC++ Redistributable.
/// Opening this in the browser starts the download the user needs to
/// unblock the CPU floor build (missing MSVCP140 / VCRUNTIME140 / VCOMP140).
const _vcRuntimeDownloadUrl = 'https://aka.ms/vs/17/release/vc_redist.x64.exe';

final _recoveryToastLog = AppLogger('RecoveryToast');

Future<void> _openVcRuntimeDownload() async {
  try {
    await launchUrl(Uri.parse(_vcRuntimeDownloadUrl));
  } on Exception catch (e) {
    _recoveryToastLog.warning(
      'Could not open VC++ Redistributable download',
      e,
    );
  }
}
