import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/theme.dart' show kWpFontFallback, kWpUiFont;
import '../../../core/theme/tokens.dart';
import '../../../services/audio/recovery/recording_journal.dart';
import '../../../services/audio/recovery/recording_recovery.dart';
import '../../../services/pending_audio/pending_audio_notice.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_banner.dart';
import '../../../widgets/wp_button.dart';
import 'history_head.dart';
import 'history_helpers.dart';

/// Outcome of the last attempt per recording and the rows with an action in
/// flight. Shared by the inline rows and the "all" dialog, so both show the
/// same state.
class RecoveryRowState {
  const RecoveryRowState({this.outcomes = const {}, this.busy = const {}});

  final Map<String, RecoveryOutcome> outcomes;
  final Set<String> busy;
}

class RecoveryRowStateNotifier extends Notifier<RecoveryRowState> {
  @override
  RecoveryRowState build() => const RecoveryRowState();

  void setBusy(String id, {required bool busy}) {
    final next = {...state.busy};
    if (busy) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = RecoveryRowState(outcomes: state.outcomes, busy: next);
  }

  void setOutcome(String id, RecoveryOutcome outcome) {
    state = RecoveryRowState(
      outcomes: {...state.outcomes, id: outcome},
      busy: state.busy,
    );
  }

  void clearOutcome(String id) {
    final next = {...state.outcomes}..remove(id);
    state = RecoveryRowState(outcomes: next, busy: state.busy);
  }
}

final recoveryRowStateProvider =
    NotifierProvider.autoDispose<RecoveryRowStateNotifier, RecoveryRowState>(
      RecoveryRowStateNotifier.new,
    );

/// Offers to recover the audio of recordings that were interrupted (crash,
/// kill, power loss) before they stopped cleanly. The summary line sits in
/// `HistoryStatusRow`. On a tall window the expanded rows show here; with no
/// recordings left, the note about damaged entries shows alone.
class RecoveryBanner extends ConsumerWidget {
  const RecoveryBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final scan = ref.watch(interruptedRecordingsProvider).value;
    if (scan == null) return const SizedBox.shrink();
    final recordings = scan.recordings;
    if (recordings.isEmpty && scan.skippedCorrupt == 0) {
      return const SizedBox.shrink();
    }
    final open = ref
        .watch(historyHeadOpenProvider)
        .contains(HistoryHeadSection.recovery);
    final inline =
        recordings.isNotEmpty && open && !historyHeadIsShort(context);
    if (recordings.isNotEmpty && !inline) return const SizedBox.shrink();

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
          if (inline) ...[
            for (final recording in recordings.take(kHistoryInlineRows))
              Padding(
                key: ValueKey('recovery-row-${recording.id}'),
                padding: const EdgeInsets.only(top: WpSpacing.xs),
                child: _RecoveryRow(recording: recording),
              ),
            if (recordings.length > kHistoryInlineRows)
              Padding(
                padding: const EdgeInsets.only(top: WpSpacing.xs),
                child: WpButton(
                  key: const ValueKey('history-recovery-show-all'),
                  label: l10n.historyShowAll,
                  variant: WpButtonVariant.ghost,
                  size: WpButtonSize.dense,
                  onPressed: () => showRecoveryDialog(context, ref),
                ),
              ),
          ],
          if (scan.skippedCorrupt > 0) _CorruptNote(count: scan.skippedCorrupt),
        ],
      ),
    );
  }
}

/// Informational only, so a caption line rather than a banner.
class _CorruptNote extends StatelessWidget {
  const _CorruptNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: WpSpacing.xxs),
      child: Text(
        L10n.of(context).recoverySkippedCorrupt(count),
        style: TextStyle(
          fontSize: WpTypography.caption,
          color: WpColors.textMuted,
        ),
      ),
    );
  }
}

/// Every interrupted recording in a dialog, for a short window or "Show all".
Future<void> showRecoveryDialog(BuildContext context, WidgetRef ref) {
  final l10n = L10n.of(context);
  return showHistoryHeadDialog(
    context: context,
    title: l10n.historyRecoverySummary(
      ref.read(interruptedRecordingsProvider).value?.recordings.length ?? 0,
    ),
    content: const RecoveryAllRows(),
    closeLabel: l10n.actionClose,
  );
}

/// Every interrupted recording, with the damaged-entries note. Scrolls inside
/// the dialog, which is a separate layer over the page.
class RecoveryAllRows extends ConsumerWidget {
  const RecoveryAllRows({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(interruptedRecordingsProvider).value;
    final recordings = scan?.recordings ?? const <InterruptedRecording>[];
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final recording in recordings)
              Padding(
                padding: const EdgeInsets.only(bottom: WpSpacing.xs),
                child: _RecoveryRow(recording: recording),
              ),
            if ((scan?.skippedCorrupt ?? 0) > 0)
              _CorruptNote(count: scan!.skippedCorrupt),
          ],
        ),
      ),
    );
  }
}

Future<void> _recover(
  BuildContext context,
  WidgetRef ref,
  InterruptedRecording recording,
) async {
  final rows = ref.read(recoveryRowStateProvider.notifier);
  rows.setBusy(recording.id, busy: true);
  final outcome = await ref.read(recordingRecoveryProvider).recover(recording);
  if (!context.mounted) return;
  final notice = pendingNoticeForRecovery(outcome);
  if (notice != null) {
    ref.read(pendingAudioNoticeProvider.notifier).report(notice);
  }
  rows
    ..setBusy(recording.id, busy: false)
    ..setOutcome(recording.id, outcome);
  // A recovered or empty entry leaves the list; a failed one stays so the
  // user can retry or discard it.
  if (outcome != RecoveryOutcome.failed) {
    ref.invalidate(interruptedRecordingsProvider);
  }
}

Future<void> _discard(
  BuildContext context,
  WidgetRef ref,
  InterruptedRecording recording,
) async {
  final l10n = L10n.of(context);
  final confirmed = await showWpConfirmDialog(
    context: context,
    title: l10n.recoveryDiscardConfirm,
    message: l10n.recoveryDiscardConfirmMessage,
    confirmLabel: l10n.recoveryDiscard,
    cancelLabel: l10n.actionCancel,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  final rows = ref.read(recoveryRowStateProvider.notifier);
  rows.setBusy(recording.id, busy: true);
  try {
    await ref.read(recordingRecoveryProvider).discard(recording);
  } catch (_) {
    if (!context.mounted) return;
    rows.setBusy(recording.id, busy: false);
    WpToast.show(context, message: l10n.errorGeneric, type: WpToastType.error);
    return;
  }
  if (!context.mounted) return;
  rows
    ..setBusy(recording.id, busy: false)
    ..clearOutcome(recording.id);
  ref.invalidate(interruptedRecordingsProvider);
}

/// One interrupted recording: its message and the restore and discard actions.
class _RecoveryRow extends ConsumerWidget {
  const _RecoveryRow({required this.recording});

  final InterruptedRecording recording;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final rowState = ref.watch(recoveryRowStateProvider);
    final busy = rowState.busy.contains(recording.id);
    final outcome = rowState.outcomes[recording.id];
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

    // Built on the banner surface rather than WpBanner's action slot: that slot
    // is a single Row, and at text scale 2.0 the two buttons outgrow a 388 px
    // pane (RenderFlex overflow). Here the buttons wrap below the message when
    // they no longer fit beside it; at smaller scales the layout is unchanged.
    final look = wpBannerLook(tone);
    return WpBannerSurface(
      tone: tone,
      child: Row(
        children: [
          Icon(look.icon, size: WpIconSize.md, color: look.iconColor),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: WpSpacing.sm,
              runSpacing: WpSpacing.xs,
              children: [
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: WpColors.textPrimary,
                    fontFamily: kWpUiFont,
                    fontFamilyFallback: kWpFontFallback,
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: WpSpacing.xs,
                  runSpacing: WpSpacing.xs,
                  children: [
                    if (showRestore)
                      WpButton(
                        key: ValueKey('recovery-restore-${recording.id}'),
                        label: l10n.recoveryRestore,
                        variant: WpButtonVariant.secondary,
                        icon: LucideIcons.rotateCcw,
                        size: WpButtonSize.dense,
                        isLoading: busy,
                        onPressed: busy
                            ? null
                            : () => _recover(context, ref, recording),
                      ),
                    WpButton(
                      key: ValueKey('recovery-discard-${recording.id}'),
                      label: l10n.recoveryDiscard,
                      variant: WpButtonVariant.ghost,
                      tone: WpButtonTone.danger,
                      icon: LucideIcons.trash2,
                      size: WpButtonSize.dense,
                      onPressed: busy
                          ? null
                          : () => _discard(context, ref, recording),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
