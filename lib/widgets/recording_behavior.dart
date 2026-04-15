/// Listens to recording state changes and triggers side effects:
/// sound feedback, toasts, tray icon updates, and auto-reset timers.
///
/// Also owns the stuck-state watchdog that auto-recovers if the pipeline
/// stays in "done" for >15 seconds.
///
/// Place this inside [ServiceBootstrapWidget] and wrap the main layout.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/recording/recording_state.dart';
import '../services/recording_orchestrator.dart';
import '../services/sound_feedback_service.dart';
import '../services/tray_service.dart';
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
      }
    });

    // ── Info notifications (soft preflight, auto-download) ──
    ref.listen<String?>(recordingInfoProvider, (prev, next) {
      if (next != null) {
        WpToast.show(
          context,
          message: localizeRecordingInfo(l10n, next),
          type: WpToastType.info,
        );
        Future.microtask(
          () => ref.read(recordingInfoProvider.notifier).clear(),
        );
      }
    });

    return widget.child;
  }
}
