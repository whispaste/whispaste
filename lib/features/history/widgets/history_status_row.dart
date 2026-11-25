import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/audio/import/audio_import_providers.dart';
import '../../../services/audio/import/audio_import_queue.dart';
import '../../../services/audio/recovery/recording_recovery.dart';
import '../../../widgets/wp_count_badge.dart';
import '../../../widgets/wp_icon_button.dart';
import 'audio_import_panel.dart';
import 'history_head.dart';
import 'history_helpers.dart';
import 'recovery_banner.dart';

/// Open imports: waiting, running or failed. A finished import is already a
/// row of the list and a cancelled one was the user's own choice.
final historyOpenImportCountProvider = Provider<int>(
  (ref) => ref
      .watch(audioImportQueueProvider)
      .where(
        (job) =>
            job.status != ImportStatus.done &&
            job.status != ImportStatus.cancelled,
      )
      .length,
);

/// Interrupted recordings waiting to be recovered.
final historyInterruptedCountProvider = Provider<int>(
  (ref) =>
      ref.watch(interruptedRecordingsProvider).value?.recordings.length ?? 0,
);

/// Whether [HistoryStatusRow] has anything to show; the toolbar only adds it
/// then, so an empty group leaves no gap in the row.
final historyStatusPendingProvider = Provider<bool>(
  (ref) =>
      ref.watch(historyOpenImportCountProvider) > 0 ||
      ref.watch(historyInterruptedCountProvider) > 0,
);

/// The Recordings toolbar's status buttons for everything the header can
/// expand: interrupted recordings and the import queue. They stand in the
/// search row as icon buttons with a count, like the filter button, never
/// as a line of their own above the search. Each topic is one target with a
/// stable test id. On a tall window a target opens its section
/// inline; on a short window it opens a dialog, so the header stays one line
/// high (UX-097, UX-098). Closing the dialog returns focus to its target.
class HistoryStatusRow extends ConsumerStatefulWidget {
  const HistoryStatusRow({super.key});

  @override
  ConsumerState<HistoryStatusRow> createState() => _HistoryStatusRowState();
}

class _HistoryStatusRowState extends ConsumerState<HistoryStatusRow> {
  final _recoveryFocus = FocusNode(debugLabel: 'history-recovery-summary');
  final _importFocus = FocusNode(debugLabel: 'history-import-summary');

  @override
  void dispose() {
    _recoveryFocus.dispose();
    _importFocus.dispose();
    super.dispose();
  }

  Future<void> _activate(HistoryHeadSection section) async {
    if (!historyHeadIsShort(context)) {
      ref.read(historyHeadOpenProvider.notifier).toggle(section);
      return;
    }
    if (section == HistoryHeadSection.recovery) {
      await showRecoveryDialog(context, ref);
    } else {
      await showImportDialog(context, ref);
    }
    if (!mounted) return;
    (section == HistoryHeadSection.recovery ? _recoveryFocus : _importFocus)
        .requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final recordings = ref.watch(historyInterruptedCountProvider);
    final jobs = ref.watch(historyOpenImportCountProvider);
    if (recordings == 0 && jobs == 0) {
      return const SizedBox.shrink();
    }
    final open = ref.watch(historyHeadOpenProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (recordings > 0)
          _StatusTarget(
            testId: 'history-recovery-summary',
            focusNode: _recoveryFocus,
            label: l10n.historyStatusRecovery(recordings),
            count: recordings,
            icon: LucideIcons.rotateCcw,
            isOpen: open.contains(HistoryHeadSection.recovery),
            onPressed: () => _activate(HistoryHeadSection.recovery),
          ),
        if (recordings > 0 && jobs > 0) const SizedBox(width: WpSpacing.xs),
        if (jobs > 0)
          _StatusTarget(
            testId: 'history-import-summary',
            focusNode: _importFocus,
            label: l10n.historyStatusImport(jobs),
            count: jobs,
            icon: LucideIcons.fileClock,
            isOpen: open.contains(HistoryHeadSection.import),
            onPressed: () => _activate(HistoryHeadSection.import),
          ),
      ],
    );
  }
}

class _StatusTarget extends StatelessWidget {
  const _StatusTarget({
    required this.testId,
    required this.focusNode,
    required this.label,
    required this.count,
    required this.icon,
    required this.isOpen,
    required this.onPressed,
  });

  final String testId;
  final FocusNode focusNode;
  final String label;
  final int count;
  final IconData icon;
  final bool isOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // The same bordered icon button as every tool in the row, its count as
    // the filter button's badge; the label is the tooltip and the name.
    return Semantics(
      expanded: isOpen,
      child: WpCountBadge(
        count: count,
        child: WpIconButton(
          key: ValueKey(testId),
          testId: testId,
          focusNode: focusNode,
          icon: icon,
          tooltip: label,
          selected: isOpen,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
