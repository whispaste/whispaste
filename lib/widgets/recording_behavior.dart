/// Listens to recording state changes and triggers side effects:
/// sound feedback, toasts, tray icon updates, and auto-reset timers.
///
/// Also owns the stuck-state watchdog that auto-recovers if the pipeline
/// stays in "done" for >15 seconds.
///
/// Place this inside [ServiceBootstrapWidget] and wrap the main layout.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart' show activePageProvider, settingsScrollTargetProvider;
import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/recording/recording_helpers.dart';
import '../core/recording/recording_state.dart';
import '../services/paste/paste_failure_notifier.dart';
import '../services/paste/paster.dart';
import '../services/recording_orchestrator.dart';
import '../services/sound_feedback_service.dart';
import '../services/stt/recovery_toast_notifier.dart';
import '../services/tray_service.dart';
import 'oom_recovery_dialog.dart';
import 'toast.dart';

// ---------------------------------------------------------------------------
// Localization helpers (error / info codes → human-readable messages)
// ---------------------------------------------------------------------------

/// Maps error codes from the recording orchestrator to localized messages.
String localizeRecordingError(L10n l10n, String errorCode) {
  switch (errorCode) {
    case 'stt_server_not_found':
      return l10n.errorSttServerNotFound;
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
String localizeRecordingInfo(L10n l10n, String infoCode) {
  switch (infoCode) {
    case 'info_engine_auto_download':
      return l10n.infoEngineAutoDownload;
    case 'info_engine_downloading':
      return l10n.infoEngineDownloading;
    case 'info_model_missing':
      return l10n.infoModelMissing;
    case 'info_stt_cuda_oom_model':
      return l10n.infoSttCudaOomFallbackModel;
    case 'info_stt_cuda_oom_cpu':
      return l10n.infoSttCudaOomFallbackCpu;
    default:
      return infoCode;
  }
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Invisible wrapper that reacts to [RecordingState] transitions.
class RecordingBehaviorWidget extends ConsumerStatefulWidget {
  const RecordingBehaviorWidget({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RecordingBehaviorWidget> createState() =>
      _RecordingBehaviorState();
}

class _RecordingBehaviorState extends ConsumerState<RecordingBehaviorWidget> {
  static final _log = AppLogger('RecordingBehavior');

  Timer? _doneResetTimer;
  Timer? _watchdogTimer;
  DateTime? _doneEnteredAt;
  bool _oomDialogOpen = false;

  @override
  void initState() {
    super.initState();
    // Watchdog: detect and auto-recover if state stuck in "done" for >15s.
    _watchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkStuckDone();
    });
  }

  @override
  void dispose() {
    _doneResetTimer?.cancel();
    _watchdogTimer?.cancel();
    super.dispose();
  }

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
    } catch (_) {
      // Provider may not be ready yet during startup.
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
      final choice = await showOomRecoveryDialog(
        context: context,
        l10n: l10n,
        modelName: nextModelName,
        hasCloudConfigured: pending.hasCloudConfigured,
        isPermanentFail: pending.isPermanentFail,
      );

      if (!mounted) return;

      final orchestrator = ref.read(recordingOrchestratorProvider.notifier);
      switch (choice ?? OomRecoveryChoice.cancel) {
        case OomRecoveryChoice.trySmallerModel:
          if (pending.nextModelId == null || nextModelName == null) break;
          final didSwitch = await orchestrator.applyOomModelFallback(
            pending.nextModelId!,
          );
          if (!mounted || !didSwitch) break;
          WpToast.show(
            context,
            message: l10n.oomRecoveryDowngrading(nextModelName),
            type: WpToastType.info,
            duration: const Duration(seconds: 4),
          );
          break;
        case OomRecoveryChoice.switchToCloud:
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
            _openSettings('stt');
          }
          break;
        case OomRecoveryChoice.openSettings:
          _openSettings('stt');
          break;
        case OomRecoveryChoice.cancel:
          break;
      }
    } finally {
      _oomDialogOpen = false;
    }
  }

  void _openSettings(String target) {
    ref.read(settingsScrollTargetProvider.notifier).set(target);
    ref.read(activePageProvider.notifier).setPage('settings');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // ── Recording state transitions ──
    ref.listen<RecordingState>(recordingProvider, (prev, next) {
      final tray = ref.read(trayServiceProvider.notifier);
      tray.updateRecordingState(next, l10n: l10n);

      if (next.isError && next.errorMessage != null) {
        try {
          ref.read(soundFeedbackProvider.notifier).playError();
        } catch (e) {
          _log.warning('Error sound playback failed (non-fatal)', e);
        }
        WpToast.show(
          context,
          message: localizeRecordingError(l10n, next.errorMessage!),
          type: WpToastType.error,
          duration: const Duration(seconds: 5),
          actionLabel: l10n.actionDismiss,
          onAction: () {
            ref.read(recordingOrchestratorProvider.notifier).reset();
          },
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
      } else if (next.isRecording && (prev == null || !prev.isRecording)) {
        try {
          ref.read(soundFeedbackProvider.notifier).playRecordStart();
        } catch (e) {
          _log.warning('Record-start sound failed (non-fatal)', e);
        }
      } else if (next.isTranscribing &&
          (prev == null || !prev.isTranscribing)) {
        try {
          ref.read(soundFeedbackProvider.notifier).playRecordStop();
        } catch (e) {
          _log.warning('Record-stop sound failed (non-fatal)', e);
        }
      } else if (next.isDone && next.transcript != null) {
        _log.debug('State → done, scheduling sound + toast + 2s reset');
        try {
          ref.read(soundFeedbackProvider.notifier).playTranscriptionComplete();
        } catch (e) {
          _log.error('Success sound playback failed (non-fatal)', e);
        }
        WpToast.show(
          context,
          message:
              '${l10n.statusTranscriptionDone} — ${next.transcript!.length > 80 ? '${next.transcript!.substring(0, 80)}…' : next.transcript!}',
          type: WpToastType.success,
        );
        // Auto-reset after a short delay so the FAB returns to idle.
        _doneResetTimer?.cancel();
        _doneResetTimer = Timer(const Duration(seconds: 2), () {
          try {
            _log.debug('Done reset timer fired — calling reset()');
            if (mounted) {
              ref.read(recordingOrchestratorProvider.notifier).reset();
              _log.debug('Done reset completed');
            }
          } catch (e, st) {
            _log.error('Done reset timer error', e, st);
          }
        });
      } else if (next.isIdle && prev != null && !prev.isIdle) {
        _log.debug('State → idle (from ${prev.phase})');
        _doneResetTimer?.cancel();
        Future.microtask(() => _showPendingOomRecovery(l10n));
      }
    });

    // ── Info notifications (soft preflight, auto-download) ──
    ref.listen<String?>(recordingInfoProvider, (prev, next) {
      if (next != null) {
        // Recovery hints that tell the user to "download in Settings" must
        // carry the last logical step — a one-tap jump to the STT settings
        // section — instead of leaving them to hunt for it.
        final bool needsSettingsAction =
            next == 'info_model_missing' || next == 'info_engine_auto_download';
        WpToast.show(
          context,
          message: localizeRecordingInfo(l10n, next),
          type: WpToastType.info,
          duration: needsSettingsAction
              ? const Duration(seconds: 6)
              : const Duration(seconds: 4),
          action: needsSettingsAction
              ? WpToastAction(
                  label: l10n.pasteFailureOpenSettings,
                  onPressed: () => _openSettings('stt'),
                )
              : null,
        );
        Future.microtask(
          () => ref.read(recordingInfoProvider.notifier).clear(),
        );
      }
    });

    // ── Paste failures (silent before — now surfaced with action) ──
    ref.listen<PasteFailureEvent?>(pasteFailureNotifierProvider, (prev, next) {
      if (next == null) return;
      _showPasteFailureToast(context, l10n, next.outcome);
      Future.microtask(
        () => ref.read(pasteFailureNotifierProvider.notifier).clear(),
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

  void _showPasteFailureToast(
    BuildContext context,
    L10n l10n,
    PasteOutcome outcome,
  ) {
    String message;
    String? actionLabel;
    VoidCallback? onAction;

    switch (outcome) {
      case PasteOutcome.permissionMissing:
        message = l10n.pasteFailurePermissionMissing;
        if (Platform.isMacOS) {
          actionLabel = l10n.pasteFailureOpenSettings;
          onAction = _openAccessibilitySettings;
        }
      case PasteOutcome.noTarget:
        message = l10n.pasteFailureNoTarget;
      case PasteOutcome.failed:
      case PasteOutcome.platformUnavailable:
      case PasteOutcome.blocked:
      case PasteOutcome.success:
        message = l10n.pasteFailureGeneric;
    }

    WpToast.show(
      context,
      message: message,
      type: WpToastType.warning,
      duration: const Duration(seconds: 6),
      actionLabel: actionLabel,
      onAction: onAction,
    );
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
}

// ---------------------------------------------------------------------------
// Recovery toast — extracted so widget tests can exercise the action
// wiring directly without bootstrapping the full RecordingBehaviorWidget.
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
  }
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
