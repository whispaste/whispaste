import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/audio/import/audio_import_providers.dart';
import '../../../services/audio/recovery/recording_recovery.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_icon_button.dart';
import 'audio_import_panel.dart';
import 'history_head.dart';
import 'history_helpers.dart';
import 'recovery_banner.dart';

/// One compact line above the history list for everything the header can
/// expand: interrupted recordings and the import queue. Each topic is one
/// target with a stable test id. On a tall window a target opens its section
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
    final recordings =
        ref.watch(interruptedRecordingsProvider).value?.recordings.length ?? 0;
    final jobs = ref.watch(audioImportQueueProvider).length;
    final short = historyHeadIsShort(context);
    // On a short window the add action lives here, so the status line stays
    // even when nothing is pending.
    if (recordings == 0 && jobs == 0 && !short) {
      return const SizedBox.shrink();
    }
    final open = ref.watch(historyHeadOpenProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.md,
        WpSpacing.xxs,
        WpSpacing.md,
        0,
      ),
      child: Wrap(
        spacing: WpSpacing.sm,
        runSpacing: WpSpacing.xs,
        children: [
          if (recordings > 0)
            _StatusTarget(
              testId: 'history-recovery-summary',
              focusNode: _recoveryFocus,
              label: l10n.historyStatusRecovery(recordings),
              icon: LucideIcons.rotateCcw,
              isOpen: open.contains(HistoryHeadSection.recovery),
              onPressed: () => _activate(HistoryHeadSection.recovery),
            ),
          if (jobs > 0)
            _StatusTarget(
              testId: 'history-import-summary',
              focusNode: _importFocus,
              label: l10n.historyStatusImport(jobs),
              icon: LucideIcons.filePlus,
              isOpen: open.contains(HistoryHeadSection.import),
              onPressed: () => _activate(HistoryHeadSection.import),
            ),
          // Tooltip and semantics label come from the button (44 px target,
          // focus ring); the file dialog opens through the panel's pick request.
          if (short)
            WpIconButton(
              key: const ValueKey('history-import-add-compact'),
              testId: 'history-import-add-compact',
              icon: LucideIcons.filePlus,
              tooltip: l10n.historyImportAddFiles,
              onPressed: () =>
                  ref.read(audioImportPickRequestProvider.notifier).request(),
            ),
        ],
      ),
    );
  }
}

class _StatusTarget extends StatelessWidget {
  const _StatusTarget({
    required this.testId,
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.isOpen,
    required this.onPressed,
  });

  final String testId;
  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final bool isOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      expanded: isOpen,
      child: WpButton(
        testId: testId,
        focusNode: focusNode,
        label: label,
        variant: WpButtonVariant.secondary,
        tone: WpButtonTone.neutral,
        icon: icon,
        size: WpButtonSize.dense,
        onPressed: onPressed,
      ),
    );
  }
}
