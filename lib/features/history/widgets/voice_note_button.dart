/// Voice note button — records a short voice clip in the history detail panel,
/// transcribes it, and dispatches the result as a note, tag, or correction.
///
/// Reuses [AudioServiceNotifier] and [SttServiceNotifier] for the recording
/// pipeline. The button shows recording/transcribing state inline.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/audio_service.dart';
import '../../../services/stt_service.dart';
import '../../../services/voice_action_service.dart';
import '../../../widgets/toast.dart';
import '../data/history_detail_provider.dart';

// ---------------------------------------------------------------------------
// Voice note button state
// ---------------------------------------------------------------------------

enum _VoiceNotePhase { idle, recording, transcribing }

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Mic button that starts a mini voice-recording session in the detail panel.
///
/// On completion the transcription is parsed via [parseVoiceAction] and
/// dispatched to the entry's [HistoryDetailNotifier]:
/// - **note** → `addNote`
/// - **tag** → `addTag`
/// - **correction** → `updateContent`
class VoiceNoteButton extends ConsumerStatefulWidget {
  const VoiceNoteButton({
    super.key,
    required this.entryId,
    required this.isDark,
  });

  final String entryId;
  final bool isDark;

  @override
  ConsumerState<VoiceNoteButton> createState() => _VoiceNoteButtonState();
}

class _VoiceNoteButtonState extends ConsumerState<VoiceNoteButton> {
  static final _log = AppLogger('VoiceNoteButton');

  _VoiceNotePhase _phase = _VoiceNotePhase.idle;

  Color get _accent =>
      widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
  Color get _textMuted =>
      widget.isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
  Color get _error => widget.isDark ? WpColorsDark.error : WpColorsLight.error;

  bool get _isBusy => _phase != _VoiceNotePhase.idle;

  // ── Recording pipeline ──────────────────────────────────────────────────

  Future<void> _startVoiceNote() async {
    if (_isBusy) return;

    // Prevent voice note while a main dictation is in progress.
    final mainAudio = ref.read(audioServiceProvider);
    if (mainAudio.isRecording) return;

    setState(() => _phase = _VoiceNotePhase.recording);

    try {
      final audio = ref.read(audioServiceProvider.notifier);
      await audio.startRecording();

      // Verify recording started.
      final status = ref.read(audioServiceProvider);
      if (status.captureState == AudioCaptureState.error) {
        _fail(status.errorMessage ?? 'recording_failed');
        return;
      }

      _log.info('Voice note recording started for entry ${widget.entryId}');
    } on Exception catch (e) {
      _fail('$e');
    }
  }

  Future<void> _stopAndTranscribe() async {
    if (_phase != _VoiceNotePhase.recording) return;

    // Capture context dependencies before async gap.
    final l10n = L10n.of(context);

    setState(() => _phase = _VoiceNotePhase.transcribing);

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
      final stt = ref.read(sttServiceProvider.notifier);
      await stt.ensureRunning().timeout(const Duration(seconds: 30));

      final sttStatus = ref.read(sttServiceProvider);
      if (!sttStatus.isReady) {
        _fail(sttStatus.errorMessage ?? 'stt_not_ready');
        return;
      }

      // Transcribe.
      final transcript = await stt
          .transcribeBytes(wavBytes)
          .timeout(const Duration(seconds: 45));

      if (transcript.trim().isEmpty) {
        _showSnackBar(l10n.voiceNoteEmpty, isError: true);
        _reset();
        return;
      }

      // Parse voice action and dispatch.
      await _dispatchAction(transcript, l10n);
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

  Future<void> _dispatchAction(String transcript, L10n l10n) async {
    final action = parseVoiceAction(transcript);
    if (action == null) {
      _showSnackBar(l10n.voiceNoteEmpty, isError: true);
      _reset();
      return;
    }

    final notifier = ref.read(historyDetailProvider(widget.entryId).notifier);

    switch (action.type) {
      case VoiceActionType.note:
        await notifier.addNote(action.payload);
        _showSnackBar(l10n.voiceNoteAdded);
      case VoiceActionType.tag:
        await notifier.addTag(action.payload);
        _showSnackBar(l10n.voiceTagAdded(action.payload));
      case VoiceActionType.correction:
        await notifier.updateContent(action.payload);
        _showSnackBar(l10n.voiceCorrectionApplied);
    }

    _log.info(
      'Voice action dispatched: ${action.type.name} → "${action.payload}"',
    );
    _reset();
  }

  void _fail(String reason) {
    _log.warning('Voice note failed: $reason');
    if (mounted) {
      _showSnackBar(L10n.of(context).voiceNoteError, isError: true);
    }
    _reset();
  }

  void _reset() {
    if (mounted) {
      setState(() => _phase = _VoiceNotePhase.idle);
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
      case _VoiceNotePhase.idle:
        await _startVoiceNote();
      case _VoiceNotePhase.recording:
        await _stopAndTranscribe();
      case _VoiceNotePhase.transcribing:
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
      case _VoiceNotePhase.idle:
        icon = LucideIcons.mic;
        tooltip = l10n.voiceNoteButton;
        color = _accent;
      case _VoiceNotePhase.recording:
        icon = LucideIcons.square;
        tooltip = l10n.voiceNoteRecording;
        color = _error;
      case _VoiceNotePhase.transcribing:
        icon = LucideIcons.loader;
        tooltip = l10n.voiceNoteTranscribing;
        color = _textMuted;
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: _phase == _VoiceNotePhase.transcribing ? null : _onTap,
        borderRadius: WpRadius.borderSm,
        child: Padding(
          padding: const EdgeInsets.all(WpSpacing.xxs),
          child: _phase == _VoiceNotePhase.transcribing
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
    );
  }
}
