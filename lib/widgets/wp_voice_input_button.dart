/// Voice input button — records a short voice clip inline, transcribes it,
/// and hands the raw transcript to the caller.
///
/// Reuses [AudioServiceNotifier] and [SttServerStateNotifier] for the
/// recording pipeline. The button shows recording/transcribing state inline.
///
/// The button owns the *pipeline* (start lock, WAV flush wait, STT timeouts,
/// error toasts) and nothing else: what happens with the finished transcript
/// is entirely the caller's business. History routes it through
/// `parseVoiceAction`'s prefix dispatch, notes insert it at the cursor — two
/// sinks, one button.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/audio_service.dart';
import '../services/recording_orchestrator.dart';
import '../services/stt/stt_bundle.dart';
import 'toast.dart';

// ---------------------------------------------------------------------------
// Voice input button state
// ---------------------------------------------------------------------------

enum _VoicePhase { idle, recording, transcribing }

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Mic button that starts a mini voice-recording session next to a text
/// surface.
///
/// On completion the raw, non-empty transcript is delivered via
/// [onTranscript]; the button returns to idle once that callback settles.
class WpVoiceInputButton extends ConsumerStatefulWidget {
  const WpVoiceInputButton({super.key, required this.onTranscript});

  /// Called with the raw, non-empty transcript once transcription succeeds.
  /// May be async — the button stays in its transcribing state until the
  /// returned future completes, so a slow sink cannot be re-triggered.
  final FutureOr<void> Function(String transcript) onTranscript;

  /// Stuck-guard budgets on the two STT calls in [_stopAndTranscribe]. Mutable
  /// + [visibleForTesting] so tests can shrink them (mirrors
  /// `SttServerStateNotifier.stuckGuardTimeout`); production keeps these
  /// defaults.
  @visibleForTesting
  static Duration ensureRunningTimeout = const Duration(seconds: 30);

  @visibleForTesting
  static Duration transcribeTimeout = const Duration(seconds: 45);

  @override
  ConsumerState<WpVoiceInputButton> createState() => _WpVoiceInputButtonState();
}

class _WpVoiceInputButtonState extends ConsumerState<WpVoiceInputButton> {
  static final _log = AppLogger('WpVoiceInputButton');

  _VoicePhase _phase = _VoicePhase.idle;

  Color get _accent => WpColorsDark.accent;
  Color get _textMuted => WpColorsDark.textMuted;
  Color get _error => WpColorsDark.error;

  bool get _isBusy => _phase != _VoicePhase.idle;

  String _labelFor(_VoicePhase phase) {
    final l10n = L10n.of(context);
    return switch (phase) {
      _VoicePhase.idle => l10n.voiceNoteButton,
      _VoicePhase.recording => l10n.voiceNoteRecording,
      _VoicePhase.transcribing => l10n.voiceNoteTranscribing,
    };
  }

  /// Updates [_phase] and announces the new phase to screen readers — mirrors
  /// the recording-state announcement in [WpStatusBar]'s `_SttChip`.
  void _setPhase(_VoicePhase phase) {
    setState(() => _phase = phase);
    SemanticsService.sendAnnouncement(
      View.of(context),
      _labelFor(phase),
      Directionality.of(context),
    );
  }

  // ── Recording pipeline ──────────────────────────────────────────────────

  Future<void> _startVoiceInput() async {
    if (_isBusy) return;

    // Acquire the orchestrator's _startInFlight lock so that all entry points
    // (tray, hotkey, floating button, this button) share the same concurrency
    // gate — eliminates the TOCTOU race from a one-shot phase read.
    //
    // The lock is released in the finally block below, after audio.startRecording()
    // returns, mirroring exactly how RecordingOrchestrator.startRecording() uses it.
    // Same reasoning as in _stopAndTranscribe: startRecording() crosses a
    // platform channel and can sit behind a mic-permission prompt, so the
    // status read below is on the far side of a real gap. Reads go through the
    // container, which outlives the button.
    final container = ProviderScope.containerOf(context, listen: false);
    final orch = container.read(recordingOrchestratorProvider.notifier);
    if (!orch.tryAcquireStartLock()) {
      _log.debug(
        'Voice input suppressed — orchestrator lock not acquired '
        '(already in flight or not idle)',
      );
      return;
    }

    _setPhase(_VoicePhase.recording);

    try {
      final audio = container.read(audioServiceProvider.notifier);
      await audio.startRecording();

      // Verify recording started.
      final status = container.read(audioServiceProvider);
      if (status.captureState == AudioCaptureState.error) {
        _fail(status.errorMessage ?? 'recording_failed');
        return;
      }

      _log.info('Voice input recording started');
    } on Exception catch (e) {
      _fail('$e');
    } finally {
      // Release the start lock now that the audio capture start-up window is
      // complete — same timing as RecordingOrchestrator.startRecording() finally.
      orch.releaseStartLock();
    }
  }

  Future<void> _stopAndTranscribe() async {
    if (_phase != _VoicePhase.recording) return;

    // Everything context- or ref-bound is captured before the first await.
    // Transcription can run for up to transcribeTimeout, and `ref` throws once
    // the element is deactivated — reading a provider late would blow up in
    // the finally block below and leak the temp WAV. The container outlives
    // the button, so reads through it stay valid after an unmount.
    final l10n = L10n.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final audio = container.read(audioServiceProvider.notifier);
    final stt = container.read(localSttBundleProvider.notifier);

    _setPhase(_VoicePhase.transcribing);

    String? wavPath;
    try {
      // Stop recording.
      wavPath = await audio.stopRecording();

      if (wavPath == null) {
        _fail('no_audio');
        return;
      }

      // Wait for WAV flush on Windows.
      final wavFile = File(wavPath);
      if (!wavFile.existsSync()) {
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (wavFile.existsSync()) break;
        }
      }
      if (!wavFile.existsSync()) {
        _fail('wav_not_created');
        return;
      }

      final wavBytes = await wavFile.readAsBytes();
      if (wavBytes.isEmpty) {
        _fail('wav_empty');
        return;
      }

      // Ensure STT is ready.
      await stt.ensureRunning().timeout(
        WpVoiceInputButton.ensureRunningTimeout,
      );

      final sttStatus = container.read(localSttBundleProvider);
      if (!sttStatus.isReady) {
        _fail(sttStatus.errorMessage ?? 'stt_not_ready');
        return;
      }

      // Transcribe.
      final transcript = await stt
          .transcribeBytes(wavBytes)
          .timeout(WpVoiceInputButton.transcribeTimeout);

      if (transcript.trim().isEmpty) {
        _showToast(l10n.voiceNoteEmpty, isError: true);
        _reset();
        return;
      }

      // Hand off — what the transcript becomes is the caller's business.
      //
      // Guarded because transcription may take up to transcribeTimeout, and
      // the surface around the button can be gone by then (panel closed,
      // entry deleted, another item selected). Both sinks reach for `context`
      // and `ref` the moment they are called, so handing a transcript into a
      // dead tree throws rather than doing anything useful.
      if (!mounted) return;
      await widget.onTranscript(transcript);
      _reset();
    } on TimeoutException {
      _fail('timeout');
    } on Exception catch (e) {
      _fail('$e');
    } finally {
      // Cleanup temp WAV — runs even when the button is already gone.
      if (wavPath != null) {
        await audio.cleanupFile(wavPath);
      }
    }
  }

  void _fail(String reason) {
    _log.warning('Voice input failed: $reason');
    if (mounted) {
      _showToast(L10n.of(context).voiceNoteError, isError: true);
    }
    _reset();
  }

  void _reset() {
    if (mounted) {
      _setPhase(_VoicePhase.idle);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    WpToast.show(
      context,
      message: message,
      type: isError ? WpToastType.error : WpToastType.success,
      duration: const Duration(seconds: 2),
    );
  }

  // ── Tap handler ─────────────────────────────────────────────────────────

  Future<void> _onTap() async {
    switch (_phase) {
      case _VoicePhase.idle:
        await _startVoiceInput();
      case _VoicePhase.recording:
        await _stopAndTranscribe();
      case _VoicePhase.transcribing:
        break; // no-op while transcribing
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    final IconData icon;
    final String tooltip;
    final Color color;

    switch (_phase) {
      case _VoicePhase.idle:
        icon = LucideIcons.mic;
        tooltip = l10n.voiceNoteButton;
        color = _accent;
      case _VoicePhase.recording:
        icon = LucideIcons.square;
        tooltip = l10n.voiceNoteRecording;
        color = _error;
      case _VoicePhase.transcribing:
        icon = LucideIcons.loader;
        tooltip = l10n.voiceNoteTranscribing;
        color = _textMuted;
    }

    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: _phase == _VoicePhase.transcribing ? null : _onTap,
          borderRadius: WpRadius.borderSm,
          child: Padding(
            padding: const EdgeInsets.all(WpSpacing.xxs),
            child: _phase == _VoicePhase.transcribing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}
