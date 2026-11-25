/// Listens to recording state changes and triggers side effects:
/// sound feedback, toasts, tray icon updates, and auto-reset timers.
///
/// Also owns the stuck-state watchdog that auto-recovers if the pipeline
/// stays in "done" for >15 seconds.
///
/// Place this inside [WpServiceBootstrap] and wrap the main layout.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/language_cycle.dart' show languageChipLabelFor;
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
import '../core/data/database_startup_gate.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../services/audio/signal_loss_detector.dart'
    show micFallbackNoticeProvider, micSwitchOfferProvider;
import '../services/microphone_selection_service.dart';
import '../core/logging/app_logger.dart';
import '../core/recording/recording_helpers.dart';
import '../core/recording/recording_state.dart';
import '../services/clipboard_history/app_clipboard.dart';
import '../services/floating_overlay/download_pill_progress.dart';
import '../services/floating_overlay/overlay_notice_rules.dart'
    show kPipelineBusyNoticeId, kStillProcessingNoticeId;
import '../services/floating_overlay/pill_hint.dart' show showOverlayPillHint;
import '../services/hotkey_heal_notice.dart';
import '../services/hotkey_observer_health.dart';
import '../services/model_download_service.dart';
import '../services/pending_audio/pending_audio_queue.dart';
import '../services/stt_parakeet/parakeet_download_service.dart'
    show parakeetDownloadProvider;
import '../services/transcription/language_mismatch_hint.dart';
import '../services/stt_parakeet/parakeet_language_support.dart';
import '../services/stt_parakeet/parakeet_script_guard.dart';
import '../services/desktop_paste/desktop_paste_controller_interface.dart';
import '../services/paste/paste_capability_notifier.dart';
import '../services/paste/clipboard_unsaved_notifier.dart';
import '../services/paste/paste_failure_notifier.dart';
import '../services/paste/paste_notice_mute.dart';
import '../services/paste/paster.dart';
import '../services/paste/repaste_service.dart';
import '../services/paste/secure_input_notice.dart';
import '../services/pending_audio/pending_audio_notice.dart';
import '../services/permissions/input_monitoring_grant.dart';
import '../services/permissions/mic_permission_notifier.dart';
import '../services/app_restart_service.dart';
import '../services/audio_service.dart' show RecordingStartFailure;
import '../services/recording_orchestrator.dart';
import '../services/sound_feedback_service.dart';
import '../services/stt/recovery_toast_notifier.dart';
import '../services/stt/stt_bundle.dart';
import '../services/tray_service.dart';
import '../services/window_activation.dart';
import '../features/settings/search/settings_search_entry.dart'
    show settingsRowAreaLabelFor;
import 'oom_recovery_dialog.dart';
import 'dictation_message.dart';
import 'onboarding_hold.dart';
import '../core/config/settings_labels.dart';
import '../services/permissions/tcc_entry_reset_confirm.dart';
import '../services/system_speech/system_speech_channel.dart';
import '../services/system_speech/system_speech_status.dart';
import '../services/user_models/user_model.dart' show UserModelPurpose;
import '../services/user_models/user_model_use.dart';
import 'wp_error_notice.dart';
import 'parakeet_language_notice.dart';
import 'pending_retry_message.dart';
import 'system_speech_notice.dart';
import 'wp_banner.dart';
import 'wp_page_notice.dart';

// ---------------------------------------------------------------------------
// Localization helpers (error / info codes → human-readable messages)
// ---------------------------------------------------------------------------

// Wp naming — deliberate exception for everything in this file except
// [WpRecordingBehavior] itself: the `Wp` prefix marks the shared *component*
// vocabulary of lib/widgets/ (types you instantiate, plus the `showWp*`
// launchers that are a component's own public API, e.g. showWpFormDialog).
// The free functions below are neither — they are pure code→string mappings,
// pure gate predicates, and call sites that pour recording-specific content
// into the already-prefixed the overlay message. Prefixing them would claim they are
// components of the design system, which they are not.

/// Whether a refused recording is answered by the onboarding surface alone.
///
/// While onboarding is open, a press of the hotkey outside the practice page is
/// refused on purpose (no transcription before setup ends). The hotkey step
/// asks for that press and shows the reaction itself, so this refusal gets no
/// error toast and no error sound. The practice page wires its sandbox sink
/// and never sees this code.
bool isSilentOnboardingRefusal(
  String errorCode, {
  required bool onboardingActive,
}) => onboardingActive && errorCode == 'onboarding_not_completed';

/// Maps error codes from the recording orchestrator to localized messages.
///
/// [localModelInstalled] only changes the cloud network and timeout messages:
/// the offline hint (dictate with the local model) is shown only when a local
/// model is on disk to fall back to (UIA-FLW-05).
///
/// [provider] is the configured speech service. The key error names the
/// settings area its "Open Settings" lands in ([settingsRowForRecordingError]):
/// API keys for OpenAI and Deepgram, Speech recognition for an own endpoint
/// (#1616). Without it the API keys area is named.
String localizeRecordingError(
  L10n l10n,
  String errorCode, {
  bool localModelInstalled = false,
  SttProviderType? provider,
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
    // Edit selection by voice.
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
    // Smart Mode: write new text (#248).
    case 'smart_write_target_changed':
      return l10n.errorSmartWriteTargetChanged;
    case 'smart_write_target_unknown':
      return l10n.errorSmartWriteTargetUnknown;
    case 'smart_write_keys_failed':
      return l10n.errorSmartWriteKeysFailed;
    case 'smart_write_preview_timeout':
      return l10n.errorSmartWritePreviewTimeout;
    case 'smart_write_clipboard_failed':
      return l10n.errorSmartWriteClipboardFailed;
    case 'smart_write_missing_key':
      return l10n.errorCloudAuth(
        settingsRowAreaLabelFor(l10n, 'api-keys-openai')!,
      );
    case 'smart_write_keyring_locked':
      return l10n.dataKeyStatusLocked;
    case 'smart_write_failed':
      return l10n.errorSmartWriteFailed;
    case 'smart_write_timeout':
      return l10n.errorSmartWriteTimeout;
    case 'smart_write_empty':
      return l10n.errorSmartWriteEmpty;
    case 'smart_write_truncated':
      return l10n.errorSmartWriteTruncated;
    // Smart Mode write on OpenAI (#251).
    case 'smart_write_openai_invalid_key':
      return l10n.errorSmartWriteOpenAiInvalidKey(
        settingsRowAreaLabelFor(l10n, 'api-keys-openai')!,
      );
    case 'smart_write_openai_rate_limited':
      return l10n.errorSmartWriteOpenAiRateLimited;
    case 'smart_write_openai_timeout':
      return l10n.errorSmartWriteOpenAiTimeout;
    case 'smart_write_openai_incomplete':
      return l10n.errorSmartWriteOpenAiIncomplete;
    case 'smart_write_openai_network':
      return l10n.errorSmartWriteOpenAiNetwork;
    case 'smart_write_selection_unknown':
      return l10n.errorSmartWriteSelectionUnknown;
    case 'smart_write_paste_failed':
      return l10n.errorSmartWritePasteFailed;
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
    case 'audio_tool_missing':
      return l10n.errorAudioToolMissing;
    case 'cloud_auth_error':
      return l10n.errorCloudAuth(
        settingsRowAreaLabelFor(
          l10n,
          settingsRowForRecordingError(
            errorCode,
            provider ?? SttProviderType.openAI,
          )!,
        )!,
      );
    case 'custom_endpoint_unreachable':
      return l10n.errorCustomEndpointUnreachable;
    case 'custom_endpoint_not_configured':
      return l10n.errorCustomEndpointNotConfigured;
    case 'custom_model_missing':
      return l10n.errorCustomModelMissing;
    case 'custom_bad_response':
      return l10n.errorCustomBadResponse;
    case 'cloud_quota_exceeded':
      return l10n.errorCloudQuota;
    case 'quick_note_append_failed':
      return l10n.errorQuickNoteAppendFailed;
    case 'stt_model_corrupted':
      return l10n.errorSttModelCorrupted;
    case 'stt_engine_restart_needed':
      return l10n.errorSttEngineRestartNeeded;
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
  'info_still_processing' => l10n.infoStillProcessing,
  'info_late_dictation_saved' => l10n.infoLateDictationSaved,
  'info_late_dictation_discarded' => l10n.infoLateDictationDiscarded,
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
String doneToastLabel(L10n l10n, RecordingTarget target) => switch (target) {
  RecordingTarget.selectionEdit => l10n.statusSelectionEdited,
  RecordingTarget.smartWrite => l10n.overlayDoneSmartWrite,
  _ => l10n.statusTranscriptionDone,
};

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

  /// While the onboarding surface is open, the app's toasts stay away: the
  /// onboarding page answers the user itself (its practice step, its hotkey
  /// step). The event is still consumed, so it cannot replay once onboarding
  /// closes. Returns `true` when the toast must be dropped.
  bool _dropToastInOnboarding(VoidCallback consume) {
    if (!ref.read(onboardingSurfaceActiveProvider)) return false;
    _log.info('Toast dropped while onboarding is open');
    Future.microtask(consume);
    return true;
  }

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
      // An own model taken out of use at start (crash marker, #1789).
      final ownModel = ref.read(userModelFallbackNoticeProvider);
      if (ownModel != null) _showUserModelFallback(ownModel);
    });
  }

  /// An own model (#1789) failed and was taken out of use: says so, and
  /// what happens to the dictation.
  void _showUserModelFallback(UserModelFallbackNotice notice) {
    final l10n = L10n.of(context);
    final text = userModelFallbackMessage(l10n, notice);
    // A short headline (the card gives it one line next to a body); the
    // model's name, which can be long, and what happened to the dictation
    // follow below it. No "dictate again" hint: the recording was not lost.
    showWpDictationMessage(
      context,
      message: text.cause,
      body: WpErrorNotice(cause: text.cause, nextStep: text.nextStep),
      type: WpMessageType.warning,
      duration: const Duration(seconds: 8),
      testId: 'user-model-fallback-toast',
      offersNewDictation: false,
    );
    Future.microtask(
      () => ref.read(userModelFallbackNoticeProvider.notifier).clear(),
    );
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

  /// A retry on a smaller model failed too; silent while onboarding is open.
  void _showOomAttemptFailedToast(L10n l10n, String currentModelName) {
    if (ref.read(recordingOrchestratorProvider.notifier).oomAttemptCount == 0 ||
        ref.read(onboardingSurfaceActiveProvider)) {
      return;
    }
    showWpDictationMessage(
      context,
      message: l10n.oomRecoveryAttemptFailed(currentModelName),
      type: WpMessageType.warning,
      duration: const Duration(seconds: 4),
    );
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

    _showOomAttemptFailedToast(l10n, currentModelName);

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
          showWpDictationMessage(
            context,
            message: l10n.oomRecoveryDowngrading(nextModelName),
            type: WpMessageType.info,
            duration: const Duration(seconds: 4),
          );
          break;
        case WpOomRecoveryChoice.switchToCloud:
          final provider = await orchestrator.switchToConfiguredCloudStt();
          if (!mounted) break;
          if (provider != null) {
            showWpDictationMessage(
              context,
              message: l10n.oomRecoverySwitchingCloud,
              type: WpMessageType.info,
              duration: const Duration(seconds: 4),
            );
          } else {
            // No cloud service set up yet: the service choice is where it
            // starts (#1616).
            _openSettings('speech-provider');
          }
          break;
        case WpOomRecoveryChoice.openSettings:
          // "Switch to a cloud speech model in the settings": the service
          // choice, not the local engine row (#1616).
          _openSettings('speech-provider');
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
    // The message was on the overlay, the main window is usually hidden.
    unawaited(ref.read(windowActivatorProvider)());
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

  /// Starts the download of the selected speech model, or `null` when there is
  /// none to fetch or the onboarding flow owns the model step (#827).
  VoidCallback? _missingModelDownload(L10n l10n) {
    final model = ref.read(missingSelectedSpeechModelProvider);
    if (model == null || ref.read(onboardingSurfaceActiveProvider)) return null;
    return () => _downloadFromCard(model, l10n);
  }

  /// Starts [model]'s download from a card and follows its progress at the
  /// pill, since the card itself closes on the click (#877).
  void _downloadFromCard(SelectableSpeechModel model, L10n l10n) {
    ref
        .read(downloadPillProgressProvider.notifier)
        .follow(
          progressText: l10n.statusBarModelDownloading,
          readyText: l10n.settingsModelStatusReady,
        );
    unawaited(
      downloadSpeechModel(
        model: model,
        whisper: ref.read(modelDownloadProvider.notifier),
        parakeet: ref.read(parakeetDownloadProvider.notifier),
      ),
    );
  }

  /// The silent-microphone offer (#595): with a suggested input the button
  /// switches to it, without one it opens Settings at the microphone. The
  /// switch runs only on the press; a device the user chose is never replaced
  /// unasked. `null` for every other error.
  ({String label, String detail, String actionId, VoidCallback onPressed})?
  _silentMicrophoneSwitch(String code, L10n l10n) {
    if (code != 'recording_guard_failed') return null;
    final suggested = ref.read(micSwitchOfferProvider);
    if (suggested == null) {
      return (
        label: l10n.overlayNoticeChooseMicrophone,
        detail: '',
        actionId: 'change-microphone',
        onPressed: () => _openSettings('recording-microphone'),
      );
    }
    return (
      label: l10n.micSwitchOfferAction,
      // The whole device name on its own line: two similar devices must stay
      // apart, so it is neither cut nor left to the button.
      detail: l10n.micSwitchOfferDetail(suggested),
      actionId: 'use-microphone',
      onPressed: () {
        _log.info('Mic switch offer accepted: "$suggested"');
        ref.read(micSwitchOfferProvider.notifier).set(null);
        unawaited(
          ref.read(microphoneSelectionServiceProvider).select(suggested),
        );
        ref.read(recordingOrchestratorProvider.notifier).reset();
      },
    );
  }

  void _handleErrorState(BuildContext context, L10n l10n, RecordingState next) {
    final code = next.errorMessage!;
    if (isSilentOnboardingRefusal(
      code,
      onboardingActive: ref.read(onboardingSurfaceActiveProvider),
    )) {
      // The onboarding step that asked for the press shows its own feedback
      // (the key caps light up), so an error toast and sound would contradict it.
      _log.info('Recording refused while onboarding is open (no toast)');
      return;
    }
    try {
      ref.read(soundFeedbackProvider.notifier).playError();
    } catch (e) {
      _log.warning('Error sound playback failed (non-fatal)', e);
    }
    // A failed start has its own overlay card with retry and microphone.
    // Only the floating overlay draws it; with the overlay off the message
    // goes to the main window like every other one.
    final overlayOn =
        ref.read(settingsProvider).value?.effectiveOverlayMode !=
        OverlayMode.off;
    final hasStartCard =
        overlayOn &&
        (code == RecordingStartFailure.noMicrophone.errorCode ||
            code == RecordingStartFailure.startFailed.errorCode);
    if (!ref.read(onboardingSurfaceActiveProvider) && !hasStartCard) {
      showRecordingErrorToast(
        context: context,
        l10n: l10n,
        errorCode: code,
        onDismiss: () =>
            ref.read(recordingOrchestratorProvider.notifier).reset(),
        openMicrophoneSettings: _openMicrophoneSettings,
        openSettings: _settingsRecoveryAction(next.errorMessage!),
        downloadModel: _missingModelDownload(l10n),
        openNotes: () => _openPage('notes'),
        switchMicrophone: _silentMicrophoneSwitch(code, l10n),
        retry: isRepeatableTranscriptionError(next.errorMessage!)
            ? () => unawaited(_retryKeptDictation(l10n))
            : null,
        restart: () =>
            unawaited(ref.read(appRestartServiceProvider).requestRestart()),
        copyTranscript: next.transcript == null
            ? null
            : () => unawaited(AppClipboard.setText(next.transcript!)),
        localModelInstalled: ref.read(onboardingSttModelInstalledProvider),
        provider: ref.read(settingsProvider).value?.sttProviderType,
      );
    }
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

  /// "Try again" on a transcription error card (#826): transcribes the kept
  /// dictation again and pastes it like a normal dictation; a success lands in
  /// the history too. A failed paste is reported like the first one (the paste
  /// card comes back). When the transcription fails again the card says so and
  /// offers another try next to the Recordings page, where the kept audio is.
  Future<void> _retryKeptDictation(L10n l10n) => runKeptDictationRetry(
    context: context,
    ref: ref,
    l10n: l10n,
    run: () => ref
        .read(recordingOrchestratorProvider.notifier)
        .retryKeptDictationAndPaste(),
    openRecordings: _openRecordings,
    isMounted: () => mounted,
  );

  /// Opens the Recordings page, where a kept dictation can be tried again or
  /// deleted. The card was on the overlay, the main window is usually hidden.
  void _openRecordings() {
    if (ref.read(onboardingSurfaceActiveProvider)) {
      unawaited(leaveOnboardingSurface(ref));
    }
    ref.read(activePageProvider.notifier).setPage('history');
    unawaited(ref.read(windowActivatorProvider)());
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
    if (_dropToastInOnboarding(
      () => ref.read(recordingInfoProvider.notifier).clear(),
    )) {
      return;
    }
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
      WpMessageType type,
      Duration duration,
      WpMessageAction? action,
    ) = switch (next) {
      'info_model_missing' when missingModel != null => (
        WpMessageType.warning,
        const Duration(seconds: 10),
        WpMessageAction(
          label: l10n.infoModelMissingDownload,
          testId: 'download-model',
          // Whisper file or Parakeet bundle alike (UIA-MDL-GATE b).
          onPressed: () => _downloadFromCard(missingModel, l10n),
        ),
      ),
      // Inside the onboarding flow the model step is the place to fix this,
      // so the action goes there instead of out to Settings (UIA-RT-01).
      'info_model_missing' when ref.read(onboardingSurfaceActiveProvider) => (
        WpMessageType.info,
        const Duration(seconds: 6),
        WpMessageAction(
          label: l10n.onboardingReadyBackToModel,
          testId: 'back-to-model',
          onPressed: () =>
              ref.read(onboardingModelStepRequestProvider.notifier).request(),
        ),
      ),
      'info_model_missing' => (
        WpMessageType.info,
        const Duration(seconds: 6),
        WpMessageAction(
          label: l10n.pasteFailureOpenSettings,
          testId: 'open-settings',
          onPressed: () => _openSettings('stt-model'),
        ),
      ),
      // Trigger word matched but the snippet list is empty — the
      // transcript was pasted normally (see `_tryDispatchSnippetPicker`),
      // which without this warning is indistinguishable from "the
      // trigger didn't work".
      'info_snippet_picker_empty' => (
        WpMessageType.warning,
        const Duration(seconds: 6),
        WpMessageAction(
          label: l10n.infoSnippetPickerEmptyAction,
          testId: 'open-snippets',
          onPressed: () => _openPage('snippets'),
        ),
      ),
      'info_late_dictation_saved' => (
        WpMessageType.info,
        const Duration(seconds: 6),
        WpMessageAction(
          label: l10n.overviewRecentOpen,
          testId: 'open-history',
          onPressed: () => _openPage('history'),
        ),
      ),
      // Same reading time as the saved notice; nothing to open, the text
      // is gone on purpose (saving off, #487).
      'info_late_dictation_discarded' => (
        WpMessageType.info,
        const Duration(seconds: 6),
        null,
      ),
      _ => (WpMessageType.info, const Duration(seconds: 4), null),
    };
    showWpDictationMessage(
      context,
      message: missingModel != null
          ? l10n.infoModelMissingSelected(missingModel.sizeLabel)
          : localizeRecordingInfo(l10n, next),
      type: type,
      duration: duration,
      action: action,
      // The download runs in the background: say so at the pill (#781).
      actionConfirmation: missingModel != null
          ? l10n.settingsModelStatusDownloading
          : null,
      // The alternative to the download is the model choice in Settings.
      secondActionLabel: missingModel != null
          ? l10n.pasteFailureOpenSettings
          : null,
      onSecondAction: missingModel != null
          ? () => _openSettings('stt-model')
          : null,
      secondActionId: 'open-settings',
      // The busy cards carry a fixed id, so they close once the app is ready
      // again instead of outliving the state they describe (#1195).
      testId: switch (next) {
        'info_pipeline_busy' => kPipelineBusyNoticeId,
        'info_still_processing' => kStillProcessingNoticeId,
        _ => null,
      },
    );
    Future.microtask(() => ref.read(recordingInfoProvider.notifier).clear());
  }

  void _openPage(String page) {
    // Same reasoning as _openSettings above: this can fire from within the
    // onboarding test recording, and the overlay would otherwise swallow it.
    if (ref.read(onboardingSurfaceActiveProvider)) {
      unawaited(leaveOnboardingSurface(ref));
    }
    ref.read(activePageProvider.notifier).setPage(page);
    unawaited(ref.read(windowActivatorProvider)());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // ── Recording state transitions ──
    ref.listen<RecordingState>(
      recordingProvider,
      (prev, next) => _onRecordingStateChanged(context, l10n, prev, next),
    );

    // The device suggestion for a silent microphone may arrive after the
    // notice (#595); the same notice is shown again with the switch button.
    ref.listen<String?>(micSwitchOfferProvider, (prev, next) {
      final state = ref.read(recordingProvider);
      if (next == null ||
          !state.isError ||
          state.errorMessage != 'recording_guard_failed' ||
          ref.read(onboardingSurfaceActiveProvider)) {
        return;
      }
      showRecordingErrorToast(
        context: context,
        l10n: l10n,
        errorCode: 'recording_guard_failed',
        onDismiss: () =>
            ref.read(recordingOrchestratorProvider.notifier).reset(),
        switchMicrophone: _silentMicrophoneSwitch(
          'recording_guard_failed',
          l10n,
        ),
      );
    });

    // The start left a silent built-in microphone for another input (#846):
    // say which one is used now.
    ref.listen<String?>(micFallbackNoticeProvider, (prev, next) {
      if (next == null) return;
      Future.microtask(
        () => ref.read(micFallbackNoticeProvider.notifier).set(null),
      );
      if (ref.read(onboardingSurfaceActiveProvider)) return;
      showWpDictationMessage(
        context,
        message: l10n.micFallbackNotice(next),
        type: WpMessageType.info,
        duration: const Duration(seconds: 6),
        testId: 'mic-fallback-notice',
      );
    });

    // ── Info notifications (soft preflight, auto-download) ──
    ref.listen<String?>(
      recordingInfoProvider,
      (prev, next) => _onRecordingInfoChanged(context, l10n, next),
    );

    // ── Paste failures (silent before — now surfaced with action) ──
    ref.listen<PasteFailureEvent?>(pasteFailureNotifierProvider, (prev, next) {
      if (next == null) return;
      if (_dropToastInOnboarding(
        () => ref.read(pasteFailureNotifierProvider.notifier).clear(),
      )) {
        return;
      }
      _showPasteFailureToast(
        context,
        l10n,
        next.outcome,
        next.secureInputHolder,
        next.fieldType,
      );
      Future.microtask(
        () => ref.read(pasteFailureNotifierProvider.notifier).clear(),
      );
    });

    // ── Previous clipboard could not be kept (macOS pasteboard privacy) ──
    ref.listen<bool>(clipboardUnsavedNotifierProvider, (prev, next) {
      if (!next) return;
      if (_dropToastInOnboarding(
        () => ref.read(clipboardUnsavedNotifierProvider.notifier).clear(),
      )) {
        return;
      }
      _showClipboardUnsavedToast(context, l10n);
      Future.microtask(
        () => ref.read(clipboardUnsavedNotifierProvider.notifier).clear(),
      );
    });

    // ── Audio kept for a history save (save failed, or kept from an earlier start) ──
    ref.listen<PendingAudioNotice?>(pendingAudioNoticeProvider, (prev, next) {
      if (next == null) return;
      if (_dropToastInOnboarding(
        () => ref.read(pendingAudioNoticeProvider.notifier).clear(),
      )) {
        return;
      }
      _showPendingAudioToast(context, l10n, next);
      Future.microtask(
        () => ref.read(pendingAudioNoticeProvider.notifier).clear(),
      );
    });

    // ── Search index was missing or damaged and rebuilt at start (#668) ──
    ref.listen<AsyncValue<bool>>(indexRepairedOnOpenProvider, (prev, next) {
      if (next.value != true || prev?.value == true) return;
      showWpPageNotice(
        context,
        page: kWpAppNoticePage,
        notice: WpPageNotice(
          id: 'index-repaired',
          message: l10n.indexRepairedOnStartNotice,
          tone: WpBannerTone.info,
        ),
      );
    });

    // ── Hotkey could not be restored after repeated self-heal failures ──
    ref.listen<int>(hotkeyHealNoticeProvider, (prev, next) {
      if (prev == next) return;
      if (ref.read(onboardingSurfaceActiveProvider)) return;
      showWpHotkeyHealFailedCard(
        context: context,
        l10n: l10n,
        restart: () =>
            unawaited(ref.read(appRestartServiceProvider).requestRestart()),
      );
    });

    // ── The single-key hotkey was given up for the combination (#773) ──
    ref.listen<HotkeyObserverLoss?>(hotkeyObserverLostNoticeProvider, (
      prev,
      next,
    ) {
      if (next == null || identical(prev, next)) return;
      if (ref.read(onboardingSurfaceActiveProvider)) return;
      final revoked = next.reason == ObserverLossReason.permissionRevoked;
      showWpDictationMessage(
        context,
        message: revoked
            ? l10n.hotkeySingleKeyPermissionLost
            : l10n.hotkeySingleKeyLost,
        type: WpMessageType.warning,
        keepOpen: true,
        testId: 'hotkey-single-key-lost-toast',
        // The one notice for a withdrawn grant (#1200): the same "Grant
        // access" label and steps as the row in the permissions overview.
        actionLabel: revoked && defaultTargetPlatform == TargetPlatform.macOS
            ? l10n.permissionRowGrant
            : null,
        onAction: revoked && defaultTargetPlatform == TargetPlatform.macOS
            ? () => unawaited(grantInputMonitoring(read: ref.read, l10n: l10n))
            : null,
        actionId: 'hotkey-single-key-lost-grant',
      );
    });

    // ── Hotkey recorder ran out of its listening time: it closed (#113) ──
    ref.listen<int>(hotkeyCaptureTimeoutNoticeProvider, (prev, next) {
      if (prev == next) return;
      if (ref.read(onboardingSurfaceActiveProvider)) return;
      showWpDictationMessage(
        context,
        message: l10n.hotkeyCaptureTimedOut,
        type: WpMessageType.info,
        duration: const Duration(seconds: 6),
        testId: 'hotkey-capture-timeout-toast',
      );
    });

    // ── Server-binary recovery outcomes (issue #07 actionable toast) ──
    ref.listen<RecoveryToastEvent?>(recoveryToastNotifierProvider, (
      prev,
      next,
    ) {
      if (next == null) return;
      if (_dropToastInOnboarding(
        () => ref.read(recoveryToastNotifierProvider.notifier).clear(),
      )) {
        return;
      }
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
      if (_dropToastInOnboarding(
        () => ref.read(languageMismatchHintProvider.notifier).clear(),
      )) {
        return;
      }
      showLanguageMismatchToast(
        context: context,
        l10n: l10n,
        detected: next.detected,
        onSwitch: () => _switchLanguage(next.detected),
        onKeep: () =>
            ref.read(languageMismatchHintProvider.notifier).keep(next),
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
      if (_dropToastInOnboarding(
        () => ref.read(parakeetLanguageNoticeProvider.notifier).clear(),
      )) {
        return;
      }
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

    // ── Parakeet wrote a script the user's languages do not use (#2168) ──
    ref.listen<ParakeetScriptNotice?>(parakeetScriptNoticeProvider, (
      prev,
      next,
    ) {
      if (next == null) return;
      if (_dropToastInOnboarding(
        () => ref.read(parakeetScriptNoticeProvider.notifier).clear(),
      )) {
        return;
      }
      showWpParakeetScriptToast(
        context: context,
        l10n: l10n,
        languages: next.languages,
        handledByWhisper: next.handledByWhisper,
        onSwitch: _switchEngineToWhisper,
      );
      Future.microtask(
        () => ref.read(parakeetScriptNoticeProvider.notifier).clear(),
      );
    });

    // ── An own model failed and a checked one took over (#1789) ──
    ref.listen<UserModelFallbackNotice?>(userModelFallbackNoticeProvider, (
      prev,
      next,
    ) {
      if (next != null) _showUserModelFallback(next);
    });

    // ── Apple speech handed a recording to Whisper (calm, once per cause) ──
    ref.listen<SystemSpeechFallback?>(systemSpeechFallbackProvider, (
      prev,
      next,
    ) {
      if (next == null) return;
      showWpSystemSpeechFallbackToast(
        context: context,
        message: next == SystemSpeechFallback.languageUnsupported
            ? l10n.systemSpeechLanguageFallbackNotice
            : l10n.systemSpeechFailureFallbackNotice,
      );
      Future.microtask(
        () => ref.read(systemSpeechFallbackProvider.notifier).clear(),
      );
    });

    // ── CPU-fallback status (issue #01: surface the silent auto-degrade) ──
    ref.listen<SttStatus>(localSttBundleProvider, (prev, next) {
      if (shouldShowCpuFallbackToast(prev, next) &&
          !ref.read(onboardingSurfaceActiveProvider)) {
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
      restart: () =>
          unawaited(ref.read(appRestartServiceProvider).requestRestart()),
    );
  }

  void _showPendingAudioToast(
    BuildContext context,
    L10n l10n,
    PendingAudioNotice notice,
  ) {
    final saveLater = notice == PendingAudioNotice.saveLater;
    final discarded = notice == PendingAudioNotice.interruptedDiscarded;
    showWpDictationMessage(
      context,
      message: switch (notice) {
        PendingAudioNotice.saveLater => l10n.pendingAudioSaveLater,
        PendingAudioNotice.recovered => l10n.pendingAudioRecovered,
        PendingAudioNotice.interruptedDiscarded =>
          l10n.pendingAudioInterruptedDiscarded,
      },
      type: saveLater || discarded ? WpMessageType.warning : WpMessageType.info,
      keepOpen: discarded,
      testId: discarded
          ? 'pending-audio-discarded-toast'
          : 'pending-audio-toast',
    );
  }

  void _showPasteFailureToast(
    BuildContext context,
    L10n l10n,
    PasteOutcome outcome,
    SecureInputHolder? secureInputHolder,
    FocusedFieldType fieldType,
  ) {
    // Same three-way routing the failed-paste OS notification uses (see
    // `paste_result_notice.dart`). The OS notification only stands in where
    // this card cannot show (#1672), but both describe the same failure, so
    // offering different recoveries would be a bug.
    final capNotifier = ref.read(pasteCapabilityNotifierProvider.notifier);
    showPasteFailureToast(
      context: context,
      l10n: l10n,
      outcome: outcome,
      secureInputHolder: secureInputHolder,
      fieldType: fieldType,
      openAccessibilitySettings: _openAccessibilitySettings,
      openAutoPasteSettings: () => _openSettings('text-after-dictation-action'),
      repaste: () => unawaited(_repasteFromCard()),
      mute: () => _mutePasteNotice(outcome),
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

  /// "Don't show again" on a paste card (#1852): switches the notice off in
  /// the settings, where Settings › General shows it with "Show again".
  void _mutePasteNotice(PasteOutcome outcome) {
    final notice = mutableNoticeForPaste(outcome);
    if (notice == null) return;
    _log.info('Paste notice switched off by the user: ${notice.id}');
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              interface_: s.interface_.withNoticeMuted(notice, muted: true),
            ),
          ),
    );
  }

  /// "Paste text again" on a failed-paste card. A failure is reported like the
  /// first one (the card comes back), never silently dropped.
  Future<void> _repasteFromCard() async {
    try {
      _reportPasteOutcome(await ref.read(repasteServiceProvider).pasteLast());
    } on Object catch (e) {
      _log.warning('Repaste from the card failed: $e');
    }
  }

  /// Raises the paste card for a paste that did not land; silent for none,
  /// success, a blocked app and an unconfirmed paste without a bridge.
  void _reportPasteOutcome(PasteOutcome? outcome) {
    if (outcome == null ||
        outcome == PasteOutcome.success ||
        outcome == PasteOutcome.blocked ||
        outcome == PasteOutcome.unconfirmedNoBridge) {
      return;
    }
    ref.read(pasteFailureNotifierProvider.notifier).report(outcome);
  }

  /// Calm, non-blocking, shown once per session: the paste itself worked, only
  /// the previous clipboard content could not be kept.
  void _showClipboardUnsavedToast(BuildContext context, L10n l10n) {
    showWpDictationMessage(
      context,
      message: l10n.pasteClipboardUnsavedHint,
      type: WpMessageType.info,
      duration: const Duration(seconds: 8),
      action: WpMessageAction(
        label: l10n.pasteClipboardUnsavedAction,
        onPressed: () => unawaited(_openPrivacySettings()),
        testId: 'clipboard-unsaved-toast-action',
      ),
    );
  }

  Future<void> _openPrivacySettings() async {
    if (defaultTargetPlatform != TargetPlatform.macOS) return;
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
    if (defaultTargetPlatform != TargetPlatform.macOS) return;
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
  showWpDictationMessage(
    context,
    message: l10n.quickNoteToastSaved,
    type: WpMessageType.success,
    action: WpMessageAction(
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
// this and the toast helpers that follow are call sites of the overlay message,
// not components of their own.
// ---------------------------------------------------------------------------

/// One button of an error card: its text, its testID suffix and what it does.
typedef _CardAction = ({String label, String actionId, VoidCallback onPressed});

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
  VoidCallback? downloadModel,
  VoidCallback? openNotes,
  VoidCallback? restart,
  ({String label, String detail, String actionId, VoidCallback onPressed})?
  switchMicrophone,
  bool localModelInstalled = false,
  SttProviderType? provider,
}) {
  // The button must do what its label says, so it needs the callback.
  final offerSettings =
      errorCode == 'mic_permission_denied' &&
      defaultTargetPlatform == TargetPlatform.macOS &&
      openMicrophoneSettings != null;
  // The caller passes [openSettings] only for codes that have a settings row.
  final offerSettingsRecovery = openSettings != null;
  final offerCopy =
      copyTranscript != null && errorCode == 'quick_note_append_failed';
  final offerNotes =
      openNotes != null && errorCode == 'quick_note_append_failed';
  // A concrete selected model that is not on disk: the download itself leads
  // and Settings is its alternative (#827, E3).
  final offerDownload =
      downloadModel != null && errorCode == 'stt_model_not_found';
  final notice = recordingErrorNotice(l10n, errorCode);
  // A pair of one fix and "try again", or one of them. No text button "Close"
  // as a fallback: a card without a real action shows only its cross, which
  // hides the card (#781, #782).
  // The text of this error asks for a restart, so the button is the restart
  // (#825).
  final offerRestart =
      errorCode == 'stt_engine_restart_needed' && restart != null;
  final _CardAction? fix = offerRestart
      ? (label: l10n.actionRestartApp, actionId: 'restart', onPressed: restart)
      : offerDownload
      ? (
          label: l10n.infoModelMissingDownload,
          actionId: 'download-model',
          onPressed: downloadModel,
        )
      : switchMicrophone != null
      ? (
          label: switchMicrophone.label,
          actionId: switchMicrophone.actionId,
          onPressed: switchMicrophone.onPressed,
        )
      : offerSettings
      ? (
          // The operating system's settings, not WhisPaste's own.
          label: l10n.actionOpenSystemSettings,
          actionId: 'open-settings',
          onPressed: openMicrophoneSettings,
        )
      : offerSettingsRecovery
      ? (
          label: l10n.pasteFailureOpenSettings,
          actionId: 'open-settings',
          onPressed: openSettings,
        )
      : offerCopy
      ? (
          label: l10n.historyCopyText,
          actionId: 'copy-text',
          onPressed: copyTranscript,
        )
      : offerNotes
      ? (
          label: l10n.actionOpenNotes,
          actionId: 'open-notes',
          onPressed: openNotes,
        )
      : null;
  final _CardAction? again = retry != null
      ? (label: l10n.actionRetry, actionId: 'retry', onPressed: retry)
      : null;
  // [retry] comes only with a failure that repeats (a kept dictation); that
  // card says "try again", so it leads and the fix is its alternative.
  final _CardAction? first = again ?? fix;
  final _CardAction? second = again != null
      ? fix
      : offerDownload && openSettings != null
      ? (
          label: l10n.pasteFailureOpenSettings,
          actionId: 'open-settings',
          onPressed: openSettings,
        )
      : offerCopy && offerNotes
      ? (
          label: l10n.actionOpenNotes,
          actionId: 'open-notes',
          onPressed: openNotes,
        )
      : null;
  showWpDictationMessage(
    context,
    message: notice == null
        ? localizeRecordingError(
            l10n,
            errorCode,
            localModelInstalled: localModelInstalled,
            provider: provider,
          )
        : '${notice.cause} ${notice.nextStep}',
    body: notice == null
        ? null
        : WpErrorNotice(cause: notice.cause, nextStep: notice.nextStep),
    type: WpMessageType.error,
    actionLabel: first?.label,
    onAction: first?.onPressed,
    secondActionLabel: second?.label,
    onSecondAction: second?.onPressed,
    secondActionId: second?.actionId,
    // The id names the situation, so a notice that returns with a new button
    // is recognised as the same one (#613).
    testId: errorCode,
    actionId: first?.actionId,
    // The download runs in the background: say so at the pill (#781).
    actionConfirmation: offerDownload
        ? l10n.settingsModelStatusDownloading
        : null,
    detail: switchMicrophone?.detail ?? '',
  );
}

/// The card for a hotkey that stopped responding and could not be restored
/// (#825): it asks for a restart, so "Restart" (id `restart`) is its button.
/// It stays until it is closed. [restart] is injected so a test can spy on it.
void showWpHotkeyHealFailedCard({
  required BuildContext context,
  required L10n l10n,
  required VoidCallback restart,
}) {
  showWpDictationMessage(
    context,
    message: l10n.hotkeySelfHealFailed,
    type: WpMessageType.warning,
    keepOpen: true,
    actionLabel: l10n.actionRestartApp,
    actionId: 'restart',
    onAction: restart,
    testId: 'hotkey-heal-failed-toast',
  );
}

/// The card for a retry of a kept dictation that did not work (#826, E8).
/// [PendingRetryOutcome.failed] keeps the audio, so it offers "Try again"
/// first and the Recordings page as the alternative; an expired or missing
/// recording cannot be tried again, so the Recordings page is its only button.
/// The notice id is `retry-failed`, the buttons are `retry` and
/// `open-recordings`. It pours retry content into the already-prefixed
/// [showWpDictationMessage], so it carries no `Wp` infix itself.
void showPendingRetryFailedCard({
  required BuildContext context,
  required L10n l10n,
  required PendingRetryOutcome outcome,
  required VoidCallback retry,
  required VoidCallback openRecordings,
}) {
  final message = pendingRetryMessage(l10n, outcome);
  if (message == null) return;
  final canRetry = outcome == PendingRetryOutcome.failed;
  showWpDictationMessage(
    context,
    message: message,
    type: WpMessageType.error,
    testId: 'retry-failed',
    actionLabel: canRetry ? l10n.actionRetry : l10n.overviewRecentOpen,
    onAction: canRetry ? retry : openRecordings,
    actionId: canRetry ? 'retry' : 'open-recordings',
    secondActionLabel: canRetry ? l10n.overviewRecentOpen : null,
    onSecondAction: canRetry ? openRecordings : null,
    secondActionId: 'open-recordings',
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
  'smart_write_missing_key' ||
  'smart_write_keyring_locked' ||
  'smart_write_openai_invalid_key' => 'api-keys-openai',
  'cloud_auth_error' when provider == SttProviderType.deepgram =>
    'api-keys-deepgram',
  'cloud_auth_error' when provider == SttProviderType.customEndpoint =>
    'speech-custom-endpoint-key',
  'cloud_auth_error' => 'api-keys-openai',
  'custom_endpoint_unreachable' ||
  'custom_endpoint_not_configured' ||
  'custom_bad_response' => 'speech-custom-endpoint-url',
  'custom_model_missing' => 'speech-custom-endpoint-model',
  _ => null,
};

// ---------------------------------------------------------------------------
// Paste-failure toast — extracted the same way as [showRecoveryToast] /
// [showCpuFallbackToast] below, so widget tests can exercise the message
// selection directly without bootstrapping the full WpRecordingBehavior.
// ---------------------------------------------------------------------------

/// The one extra sentence an unconfirmed paste carries on macOS: password and
/// PIN fields refuse the paste (Secure Event Input) and the OS does not say
/// so. Only macOS is known to drop the paste there, so other platforms get
/// no such sentence. The sentence states the rule and the manual step; it does
/// not claim that this field caused the failure.
///
/// Once the field type is known ([FocusedFieldType.normal], #949) the hint is
/// dropped: a password field would have been caught before the paste.
String? pasteSecureFieldHint(
  L10n l10n, {
  required bool isMacOS,
  FocusedFieldType fieldType = FocusedFieldType.unknown,
}) => isMacOS && fieldType == FocusedFieldType.unknown
    ? l10n.pasteHintSecureField
    : null;

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
/// [mute] switches the notice off for good ("Don't show again", #1852). The
/// card offers it only for an outcome the user may mute
/// ([mutableNoticeForPaste]); a real failure never gets the button.
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
  VoidCallback? repaste,
  VoidCallback? mute,
  bool staleEntry = false,
  bool linuxNoDevice = false,
  SecureInputHolder? secureInputHolder,
  FocusedFieldType fieldType = FocusedFieldType.unknown,
}) {
  String message;
  // A headline of its own for the overlay card (#1617); null keeps the
  // message as the card's headline.
  String? headline;
  String? actionLabel;
  VoidCallback? onAction;
  var toastType = WpMessageType.warning;
  // The paste key the user must press is ⌘V on macOS and Ctrl+V elsewhere.
  // Decided by defaultTargetPlatform like the rest of the label code, so a
  // test that pins the macOS platform sees ⌘V on any host; in the app both are
  // the real OS.
  final shortcut = pasteShortcutLabel(l10n: l10n);

  switch (outcome) {
    case PasteOutcome.permissionMissing:
      // The transcript stays on the clipboard after a failed paste, so the
      // copy says so and names the shortcut for the manual paste.
      message = l10n.pasteFailureClipboardCopy(shortcut);
      if (defaultTargetPlatform == TargetPlatform.macOS) {
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
                '${l10n.pasteFailureClipboardCopy(shortcut)}';
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
            '${l10n.pasteFailureClipboardCopy(shortcut)} '
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
      final secureHint = pasteSecureFieldHint(
        l10n,
        isMacOS: defaultTargetPlatform == TargetPlatform.macOS,
        fieldType: fieldType,
      );
      message = [l10n.pasteFailureUnconfirmed(shortcut), ?secureHint].join(' ');
    case PasteOutcome.unconfirmedRestored:
      // The legacy restore put the previous clipboard back: the text is not on
      // the clipboard any more, so the message must not claim it (#1147).
      message = l10n.pasteFailureUnconfirmedRestored;
    case PasteOutcome.unconfirmedReceiptRefused:
      // Information, not a warning: the text is on the clipboard.
      message = l10n.pasteReceiptRefusedText;
      toastType = WpMessageType.info;
    case PasteOutcome.secureInput:
      // Another app, a password field or a macOS password prompt holds secure
      // input: no paste was attempted. The card shows the outcome as its
      // headline and the cause, the way out and the clipboard sentence below
      // it, so nothing is cut (F35-8, #1617).
      final text = secureInputNotice(
        l10n,
        shortcut: shortcut,
        holder: secureInputHolder,
      );
      headline = text.title;
      message = text.body;
    case PasteOutcome.passwordField:
      // #948: a password or PIN field has focus, no paste was attempted. The
      // text is on the clipboard for a manual paste.
      message = l10n.pastePasswordFieldText(shortcut);
    case PasteOutcome.unconfirmedNoBridge:
      // Never reported as a warning, see the orchestrator.
      return;
    case PasteOutcome.failed:
    case PasteOutcome.platformUnavailable:
    case PasteOutcome.blocked:
    case PasteOutcome.success:
      message = l10n.pasteFailureGeneric(shortcut);
  }

  // "Paste again" fits where the text is fine and only the target failed; not
  // where the user must first leave a secure field or a blocked app.
  // `unconfirmed` may already have landed (a second paste could double it),
  // and on Linux without uinput access it fails again until the setting is fixed.
  final repasteFits = switch (outcome) {
    PasteOutcome.elevationBlocked ||
    PasteOutcome.secureInput ||
    PasteOutcome.passwordField ||
    PasteOutcome.unconfirmed ||
    PasteOutcome.unconfirmedReceiptRefused => false,
    PasteOutcome.permissionMissing =>
      repaste != null && defaultTargetPlatform != TargetPlatform.linux,
    _ => repaste != null,
  };
  final hasFix = actionLabel != null && onAction != null;
  // Up to two buttons: the fix or "paste again" first, then "paste again"
  // as the alternative to a fix. "Don't show again" takes the first free
  // place on a notice the user may mute (#1852).
  String? firstLabel = hasFix
      ? actionLabel
      : (repasteFits ? l10n.pasteFailureRepaste : null);
  VoidCallback? firstAction = hasFix
      ? onAction
      : (repasteFits ? repaste : null);
  var firstId = hasFix ? 'paste-failure-toast-action' : 'paste-failure-repaste';
  String? firstConfirmation;
  String? secondLabel = hasFix && repasteFits ? l10n.pasteFailureRepaste : null;
  VoidCallback? secondAction = hasFix && repasteFits ? repaste : null;
  var secondId = 'paste-failure-repaste';
  String? secondConfirmation;
  if (mute != null && mutableNoticeForPaste(outcome) != null) {
    if (firstLabel == null || firstAction == null) {
      firstLabel = l10n.noticeMuteAction;
      firstAction = mute;
      firstId = kPasteNoticeMuteActionId;
      firstConfirmation = l10n.noticeMutedConfirmation;
    } else if (secondLabel == null || secondAction == null) {
      secondLabel = l10n.noticeMuteAction;
      secondAction = mute;
      secondId = kPasteNoticeMuteActionId;
      secondConfirmation = l10n.noticeMutedConfirmation;
    }
  }
  showWpDictationMessage(
    context,
    message: message,
    body: headline == null
        ? null
        : WpErrorNotice(cause: headline, nextStep: message),
    type: toastType,
    keepOpen: toastType == WpMessageType.warning,
    actionLabel: firstLabel,
    onAction: firstAction,
    actionId: firstId,
    actionConfirmation: firstConfirmation,
    secondActionLabel: secondLabel,
    onSecondAction: secondAction,
    secondActionId: secondId,
    secondActionConfirmation: secondConfirmation,
    // A paste can come from the snippet picker, side panel or re-paste, where
    // nothing was dictated: the card never offers "dictate again" (#1147).
    offersNewDictation: false,
  );
}

/// Button id of "Don't show again" on a paste card (#1852).
const kPasteNoticeMuteActionId = 'paste-notice-mute';

// ---------------------------------------------------------------------------
// Recovery toast — extracted so widget tests can exercise the action
// wiring directly without bootstrapping the full WpRecordingBehavior.
// ---------------------------------------------------------------------------

// camelCase enum name → kebab-case notice id.
final _upper = RegExp('[A-Z]');
String _dashLower(Match m) => '-${m[0]!.toLowerCase()}';

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
/// - [RecoveryToastKind.cudaLoadCrashDisabled], [RecoveryToastKind.gpuProbeFailed]
///   and [RecoveryToastKind.gpuLoadIncompatible] (#561) → the same warning
///   with the action targeting `'stt'`, where "Check again" lives.
/// - [RecoveryToastKind.modelFileRepair] (#561) → passive info toast while a
///   damaged model file downloads again.
///
/// Each notice carries the id `recovery-<kind>` (kebab case).
///
/// [openSettings] is injected so widget tests can substitute a spy and
/// assert that tapping the action fires the navigation request without
/// needing the full app shell (`activePageProvider` +
/// `settingsScrollTargetProvider` are private to the production wiring).
///
/// [installVcRuntime] is likewise injectable: it defaults to opening the
/// Microsoft VC++ Redistributable download in the browser, but tests pass
/// a spy to assert the action wiring without a real `launchUrl`.
///
/// [restart] (#825) is the "Restart" button of the [RecoveryToastKind.exhausted]
/// card (id `restart`), injected the same way; "Open settings" becomes its
/// second button.
void showRecoveryToast({
  required BuildContext context,
  required L10n l10n,
  required RecoveryToastKind kind,
  required void Function(String section) openSettings,
  VoidCallback? installVcRuntime,
  VoidCallback? restart,
}) {
  // Stable per kind, so a check can tell the recovery notices apart.
  final id = 'recovery-${kind.name.replaceAllMapped(_upper, _dashLower)}';
  switch (kind) {
    case RecoveryToastKind.exhausted:
      // The text asks for a restart, so the restart leads and the settings
      // (reload the model there) are the alternative (#825). Without a
      // restart callback the settings stay the only button.
      showWpDictationMessage(
        context,
        testId: id,
        message: l10n.recoveryExhaustedToast,
        type: WpMessageType.error,
        duration: const Duration(seconds: 8),
        actionLabel: restart != null
            ? l10n.actionRestartApp
            : l10n.recoveryExhaustedAction,
        actionId: restart != null ? 'restart' : 'open-settings',
        onAction: restart ?? () => openSettings('stt-model'),
        secondActionLabel: restart != null
            ? l10n.recoveryExhaustedAction
            : null,
        secondActionId: 'open-settings',
        onSecondAction: restart != null
            ? () => openSettings('stt-model')
            : null,
      );
    case RecoveryToastKind.vcRuntimeMissing:
      showWpDictationMessage(
        context,
        testId: id,
        message: l10n.recoveryVcRuntimeToast,
        type: WpMessageType.error,
        duration: const Duration(seconds: 10),
        action: WpMessageAction(
          label: l10n.recoveryVcRuntimeAction,
          testId: 'install-vc-runtime',
          onPressed: installVcRuntime ?? _openVcRuntimeDownload,
        ),
      );
    case RecoveryToastKind.abiInfo:
      showWpDictationMessage(
        context,
        testId: id,
        message: l10n.modelAbiInfoToast,
        type: WpMessageType.info,
        duration: const Duration(seconds: 5),
      );
    case RecoveryToastKind.gpuLoadCrashDisabled:
      showWpDictationMessage(
        context,
        testId: id,
        message: l10n.recoveryGpuDisabledToast,
        type: WpMessageType.warning,
        duration: const Duration(seconds: 8),
        action: WpMessageAction(
          label: l10n.recoveryOpenGpuSettings,
          testId: 'open-settings',
          onPressed: () => openSettings('speech-gpu'),
        ),
      );
    case RecoveryToastKind.cudaLoadCrashDisabled:
      showWpDictationMessage(
        context,
        testId: id,
        message: l10n.recoveryCudaDisabledToast,
        type: WpMessageType.warning,
        duration: const Duration(seconds: 8),
        action: WpMessageAction(
          label: l10n.recoveryOpenGpuSettings,
          testId: 'open-settings',
          onPressed: () => openSettings('speech-gpu'),
        ),
      );
    case RecoveryToastKind.gpuProbeFailed:
      showWpDictationMessage(
        context,
        testId: id,
        message: l10n.recoveryGpuProbeFailedToast,
        type: WpMessageType.warning,
        duration: const Duration(seconds: 8),
        action: WpMessageAction(
          label: l10n.recoveryOpenGpuSettings,
          testId: 'open-settings',
          onPressed: () => openSettings('speech-gpu'),
        ),
      );
    case RecoveryToastKind.gpuLoadIncompatible:
      showWpDictationMessage(
        context,
        testId: id,
        message: l10n.recoveryGpuLoadIncompatibleToast,
        type: WpMessageType.warning,
        duration: const Duration(seconds: 8),
        action: WpMessageAction(
          label: l10n.recoveryOpenGpuSettings,
          testId: 'open-settings',
          onPressed: () => openSettings('speech-gpu'),
        ),
      );
    case RecoveryToastKind.modelFileRepair:
      showWpDictationMessage(
        context,
        testId: id,
        message: l10n.recoveryModelFileRepairToast,
        type: WpMessageType.info,
        duration: const Duration(seconds: 8),
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
/// the overlay message, not a component of its own.
void showLanguageMismatchToast({
  required BuildContext context,
  required L10n l10n,
  required String detected,
  required VoidCallback onSwitch,
  VoidCallback? onKeep,
}) {
  showWpDictationMessage(
    context,
    message: l10n.languageMismatchHint,
    type: WpMessageType.info,
    duration: const Duration(seconds: 6),
    // Names the target and says it stays: the switch is permanent (#827, I5).
    actionLabel: l10n.languageMismatchSwitchTo(
      languageChipLabelFor(detected) ?? detected,
    ),
    onAction: onSwitch,
    actionId: 'switch-language',
    // The alternative: keep the fixed language and stop asking about it.
    secondActionLabel: onKeep == null ? null : l10n.languageMismatchKeep,
    onSecondAction: onKeep,
    secondActionId: 'keep-language',
  );
}

/// Renders the plain-language, dismissable info toast for the CPU-fallback
/// status. No action button: switching the GPU-acceleration setting cannot
/// undo a fallback that already happened for the current server process, so
/// no button is offered — a passive toast (like [RecoveryToastKind.abiInfo]
/// above) is all this needs.
void showCpuFallbackToast({required BuildContext context, required L10n l10n}) {
  showWpDictationMessage(
    context,
    message: '${l10n.errorNoticeCpuCause} ${l10n.errorNoticeCpuNext}',
    body: WpErrorNotice(
      cause: l10n.errorNoticeCpuCause,
      nextStep: l10n.errorNoticeCpuNext,
    ),
    type: WpMessageType.info,
    duration: const Duration(seconds: 5),
  );
}

/// "Try a smaller model" found no smaller model to switch to (UIA-SHL-06).
/// The dialog has already closed, so the reason and the next step stay on
/// screen as an error toast instead of the outcome being silent.
/// Wp naming: call site of showWpDictationMessage, not a component (see wp_prefix_consistency_test).
void showOomNoSmallerModelToast({
  required BuildContext context,
  required L10n l10n,
}) {
  showWpDictationMessage(
    context,
    message: l10n.oomRecoveryNoSmallerModel,
    type: WpMessageType.error,
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

/// What one "try again" of the error card reports back, see
/// `RecordingOrchestrator.retryKeptDictationAndPaste`.
typedef WpKeptDictationRetryResult = ({
  PendingRetryOutcome? outcome,
  PasteOutcome? paste,
});

/// Runs [run] (the retry of a kept dictation) and reports its result: the
/// failure card, the pill hint `retry-not-pasted` when the text is saved but
/// was not pasted, and the paste card for a paste that did not land (#839).
Future<void> runKeptDictationRetry({
  required BuildContext context,
  required WidgetRef ref,
  required L10n l10n,
  required Future<WpKeptDictationRetryResult> Function() run,
  required VoidCallback openRecordings,
  required bool Function() isMounted,
}) async {
  final result = await run();
  if (!isMounted() || !context.mounted) return;
  final message = pendingRetryMessage(l10n, result.outcome);
  if (message != null) {
    showPendingRetryFailedCard(
      context: context,
      l10n: l10n,
      outcome: result.outcome!,
      retry: () => unawaited(
        runKeptDictationRetry(
          context: context,
          ref: ref,
          l10n: l10n,
          run: run,
          openRecordings: openRecordings,
          isMounted: isMounted,
        ),
      ),
      openRecordings: openRecordings,
    );
  }
  if (result.outcome == PendingRetryOutcome.saved && result.paste == null) {
    // A dictation runs by now: the text is saved, a paste would miss.
    showOverlayPillHint(
      context,
      id: 'retry-not-pasted',
      text: l10n.overlayDoneNotPasted,
    );
  }
  final paste = result.paste;
  if (paste != null &&
      paste != PasteOutcome.success &&
      paste != PasteOutcome.blocked &&
      paste != PasteOutcome.unconfirmedNoBridge) {
    ref.read(pasteFailureNotifierProvider.notifier).report(paste);
  }
}

/// The words of a [UserModelFallbackNotice].
({String cause, String nextStep}) userModelFallbackMessage(
  L10n l10n,
  UserModelFallbackNotice notice,
) {
  final name = notice.modelName;
  return (
    cause: l10n.userModelFallbackTitle,
    nextStep: switch ((notice.purpose, notice.replaced)) {
      (UserModelPurpose.speech, true) => l10n.userModelFallbackSpeech(name),
      (UserModelPurpose.speech, false) => l10n.userModelFallbackSpeechNone(
        name,
      ),
      (UserModelPurpose.smartMode, true) => l10n.userModelFallbackSmartMode(
        name,
      ),
      (UserModelPurpose.smartMode, false) =>
        l10n.userModelFallbackSmartModeNone(name),
    },
  );
}
