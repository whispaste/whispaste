import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/audio/recovery/recording_journal.dart';
import '../../../services/audio/recovery/recording_recovery.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_banner.dart';
import '../../../widgets/wp_button.dart';

/// Offers to recover the audio of recordings that were interrupted (crash,
/// kill, power loss) before they stopped cleanly. Without retained audio it
/// only states that, and the entry can be discarded.
class RecoveryBanner extends ConsumerStatefulWidget {
  const RecoveryBanner({super.key});

  @override
  ConsumerState<RecoveryBanner> createState() => _RecoveryBannerState();
}

class _RecoveryBannerState extends ConsumerState<RecoveryBanner> {
  final Map<String, RecoveryOutcome> _outcomes = {};
  final Set<String> _busy = {};

  Future<void> _recover(InterruptedRecording recording) async {
    setState(() => _busy.add(recording.id));
    final outcome = await ref
        .read(recordingRecoveryProvider)
        .recover(recording);
    if (!mounted) return;
    setState(() {
      _busy.remove(recording.id);
      _outcomes[recording.id] = outcome;
    });
    // A recovered or empty entry leaves the list; a failed one stays so the
    // user can retry or discard it.
    if (outcome != RecoveryOutcome.failed) {
      ref.invalidate(interruptedRecordingsProvider);
    }
  }

  Future<void> _discard(InterruptedRecording recording) async {
    final l10n = L10n.of(context);
    final confirmed = await confirmDestructive(
      context: context,
      title: l10n.recoveryDiscardConfirm,
      message: l10n.recoveryDiscardConfirmMessage,
      confirmLabel: l10n.recoveryDiscard,
      cancelLabel: l10n.actionCancel,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy.add(recording.id));
    try {
      await ref.read(recordingRecoveryProvider).discard(recording);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy.remove(recording.id));
      WpToast.show(
        context,
        message: l10n.errorGeneric,
        type: WpToastType.error,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy.remove(recording.id);
      _outcomes.remove(recording.id);
    });
    ref.invalidate(interruptedRecordingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final scan = ref.watch(interruptedRecordingsProvider).value;
    if (scan == null || (scan.recordings.isEmpty && scan.skippedCorrupt == 0)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.md,
        WpSpacing.xs,
        WpSpacing.md,
        WpSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final recording in scan.recordings)
            Padding(
              key: ValueKey('recovery-row-${recording.id}'),
              padding: const EdgeInsets.only(bottom: WpSpacing.xs),
              child: _row(l10n, recording),
            ),
          if (scan.skippedCorrupt > 0)
            WpBanner(
              tone: WpBannerTone.info,
              message: l10n.recoverySkippedCorrupt(scan.skippedCorrupt),
            ),
        ],
      ),
    );
  }

  Widget _row(L10n l10n, InterruptedRecording recording) {
    final busy = _busy.contains(recording.id);
    final outcome = _outcomes[recording.id];
    final hasAudio = recording.wavPath != null;

    final message = switch (outcome) {
      RecoveryOutcome.failed => l10n.recoveryFailed,
      RecoveryOutcome.noAudio => l10n.recoveryNoAudioCaptured,
      _ when !hasAudio => l10n.recoveryNoAudioKept,
      _ => l10n.recoveryOffer,
    };
    final showRestore = hasAudio && outcome != RecoveryOutcome.noAudio;
    final tone = outcome == RecoveryOutcome.failed
        ? WpBannerTone.warning
        : WpBannerTone.info;

    return WpBanner(
      tone: tone,
      message: message,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showRestore)
            WpButton(
              key: ValueKey('recovery-restore-${recording.id}'),
              label: l10n.recoveryRestore,
              variant: WpButtonVariant.secondary,
              icon: LucideIcons.rotateCcw,
              size: WpButtonSize.dense,
              isLoading: busy,
              onPressed: busy ? null : () => _recover(recording),
            ),
          const SizedBox(width: WpSpacing.xs),
          WpButton(
            key: ValueKey('recovery-discard-${recording.id}'),
            label: l10n.recoveryDiscard,
            variant: WpButtonVariant.ghost,
            icon: LucideIcons.trash2,
            size: WpButtonSize.dense,
            onPressed: busy ? null : () => _discard(recording),
          ),
        ],
      ),
    );
  }
}
