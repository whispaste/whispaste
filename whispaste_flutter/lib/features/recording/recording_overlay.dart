import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_labels.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../core/recording/recording_state.dart';
import '../../services/recording_orchestrator.dart';
import '../../widgets/recording_pill.dart';

// ---------------------------------------------------------------------------
// Recording overlay -- thin Riverpod wrapper around shared RecordingPill
// ---------------------------------------------------------------------------

/// In-window recording overlay that reads Riverpod state and delegates all
/// rendering to [RecordingPill].
///
/// Keeps the AnimatedSwitcher for pill visibility transitions and the
/// auto-dismiss timer for the done phase. All visual rendering is shared
/// with the floating overlay via [RecordingPill].
class RecordingOverlay extends ConsumerStatefulWidget {
  const RecordingOverlay({super.key});

  @override
  ConsumerState<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends ConsumerState<RecordingOverlay> {
  // Auto-dismiss timer for the "done" phase.
  Timer? _doneTimer;

  @override
  void dispose() {
    _doneTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(recordingPhaseProvider);

    // Schedule auto-dismiss when entering the done phase (fast, subtle).
    ref.listen<RecordingPhase>(recordingPhaseProvider, (prev, next) {
      _doneTimer?.cancel();
      if (next == RecordingPhase.done) {
        _doneTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) ref.read(recordingOrchestratorProvider.notifier).reset();
        });
      }
    });

    if (phase == RecordingPhase.idle) return const SizedBox.shrink();

    // Read all state that RecordingPill needs from Riverpod.
    final state = ref.watch(recordingProvider);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final elapsed = ref.watch(recordingElapsedProvider);
    final audioLevel = ref.watch(audioLevelProvider);

    return AnimatedSwitcher(
      duration: WpMotion.smooth,
      switchInCurve: WpMotion.defaultCurve,
      switchOutCurve: WpMotion.defaultCurve,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(animation);
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: KeyedSubtree(
        key: const ValueKey('recording-overlay-visible'),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: RecordingPill(
          phase: phase,
          elapsed: elapsed,
          audioLevel: audioLevel,
          maxDurationSeconds: settings.maxRecordDuration,
          isLocalStt: settings.sttProviderType.isLocal,
          aiMode: null, // TODO: wire AI mode when available
          transcript: state.transcript,
          errorMessage: state.errorMessage,
          afterAction: settings.afterTranscriptionAction.value,
          hotkeyLabel: formatHotkeyShortcut(
            settings.hotkeyModifiers,
            settings.hotkeyKey,
            l10n: L10n.of(context),
          ),
          showBackdropFilter: true,
          onStop: () =>
              ref.read(recordingOrchestratorProvider.notifier).stopRecording(),
          onCancel: () =>
              ref.read(recordingOrchestratorProvider.notifier).reset(),
        ),
        ),
      ),
    );
  }
}
