/// Voice input button — records a short voice clip in the note editor
/// toolbar, transcribes it, and hands the raw transcript to the caller.
///
/// Reuses [AudioServiceNotifier] and [SttServerStateNotifier] for the
/// recording pipeline. The button shows recording/transcribing state inline.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/audio_service.dart';
import '../../../services/recording_orchestrator.dart';
import '../../../services/stt/stt_bundle.dart';
import '../../../widgets/toast.dart';

// ---------------------------------------------------------------------------
// Voice input button state
// ---------------------------------------------------------------------------

enum _VoicePhase { idle, recording, transcribing }

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Mic button that starts a mini voice-recording session in the note editor.
///
/// On completion the raw transcript is delivered via [onTranscript] — this
/// widget knows nothing about the note's content or the text controller.
class NoteVoiceInputButton extends ConsumerStatefulWidget {
  const NoteVoiceInputButton({
    super.key,
    required this.isDark,
    required this.onTranscript,
  });

  final bool isDark;

  /// Called with the raw, non-empty transcript once transcription succeeds.
  /// The caller (NoteEditorPanel → _NotesPageState) inserts it at the
  /// current cursor position — this widget knows nothing about the note's
  /// content or the text controller.
  final ValueChanged<String> onTranscript;

  /// Stuck-guard budgets on the two STT calls in [_stopAndTranscribe]. Mutable
  /// + [visibleForTesting] so tests can shrink them (mirrors
  /// `SttServerStateNotifier.stuckGuardTimeout`); production keeps these
  /// defaults.
  @visibleForTesting
  static Duration ensureRunningTimeout = const Duration(seconds: 30);

  @visibleForTesting
  static Duration transcribeTimeout = const Duration(seconds: 45);

  @override
  ConsumerState<NoteVoiceInputButton> createState() =>
      _NoteVoiceInputButtonState();
}

class _NoteVoiceInputButtonState extends ConsumerState<NoteVoiceInputButton> {
  static final _log = AppLogger('NoteVoiceInputButton');

  _VoicePhase _phase = _VoicePhase.idle;

  Color get _accent =>
      widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
  Color get _textMuted =>
      widget.isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
  Color get _error => widget.isDark ? WpColorsDark.error : WpColorsLight.error;

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
    // (tray, hotkey, floating button, voice-note button, this button) share
    // the same concurrency gate — eliminates the TOCTOU race from a one-shot
    // phase read.
    //
    // The lock is released in the finally block below, after audio.startRecording()
    // returns, mirroring exactly how RecordingOrchestrator.startRecording() uses it.
    final orch = ref.read(recordingOrchestratorProvider.notifier);
    if (!orch.tryAcquireStartLock()) {
      _log.debug(
        'Voice input suppressed — orchestrator lock not acquired '
        '(already in flight or not idle)',
      );
      return;
    }

    _setPhase(_VoicePhase.recording);

    try {
      final audio = ref.read(audioServiceProvider.notifier);
      await audio.startRecording();

      // Verify recording started.
      final status = ref.read(audioServiceProvider);
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

    // Capture context dependencies before async gap.
    final l10n = L10n.of(context);

    _setPhase(_VoicePhase.transcribing);

    String? wavPath;
    try {
      // Stop recording.
      final audio = ref.read(audioServiceProvider.notifier);
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
      final stt = ref.read(localSttBundleProvider.notifier);
      await stt.ensureRunning().timeout(
        NoteVoiceInputButton.ensureRunningTimeout,
      );

      final sttStatus = ref.read(localSttBundleProvider);
      if (!sttStatus.isReady) {
        _fail(sttStatus.errorMessage ?? 'stt_not_ready');
        return;
      }

      // Transcribe.
      final transcript = await stt
          .transcribeBytes(wavBytes)
          .timeout(NoteVoiceInputButton.transcribeTimeout);

      if (transcript.trim().isEmpty) {
        _showSnackBar(l10n.voiceNoteEmpty, isError: true);
        _reset();
        return;
      }

      // Hand off — the caller inserts the transcript at the cursor position.
      widget.onTranscript(transcript);
      _reset();
    } on TimeoutException {
      _fail('timeout');
    } on Exception catch (e) {
      _fail('$e');
    } finally {
      // Cleanup temp WAV.
      if (wavPath != null) {
        await ref.read(audioServiceProvider.notifier).cleanupFile(wavPath);
      }
    }
  }

  void _fail(String reason) {
    _log.warning('Voice input failed: $reason');
    if (mounted) {
      _showSnackBar(L10n.of(context).voiceNoteError, isError: true);
    }
    _reset();
  }

  void _reset() {
    if (mounted) {
      _setPhase(_VoicePhase.idle);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
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
