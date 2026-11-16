import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/dialog.dart';

/// The two collapsible sections of the history header.
enum HistoryHeadSection { recovery, import }

/// Which sections are expanded. On a tall window an expanded section shows its
/// rows inline; on a short window it opens as a dialog instead (see
/// `historyHeadIsShort`).
class HistoryHeadOpenNotifier extends Notifier<Set<HistoryHeadSection>> {
  @override
  Set<HistoryHeadSection> build() => const {};

  void toggle(HistoryHeadSection section) {
    state = state.contains(section)
        ? ({...state}..remove(section))
        : {...state, section};
  }
}

final historyHeadOpenProvider =
    NotifierProvider.autoDispose<
      HistoryHeadOpenNotifier,
      Set<HistoryHeadSection>
    >(HistoryHeadOpenNotifier.new);

/// Shows an expanded header section as a dialog. Escape closes it, the
/// content gets focus when it opens, and the close button stays in the actions.
Future<void> showHistoryHeadDialog({
  required BuildContext context,
  required String title,
  required Widget content,
  required String closeLabel,
}) {
  return showWpDialog<void>(
    context: context,
    title: title,
    content: CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(autofocus: true, child: content),
    ),
    actions: [
      WpDialogAction(
        label: closeLabel,
        testId: 'history-head-close',
        role: WpDialogActionRole.primary,
      ),
    ],
  );
}
