import 'package:flutter/widgets.dart';

import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../widgets/wp_page_notice.dart';

/// Tells the user what went wrong while the history database opened (#602):
/// a failed move out of the old folder, a safety copy that could not be
/// written. Each problem stands as an app notice until it is closed, with the
/// cause, the state that stays in use and the next step. Call once after the
/// start-up gate; the problems are taken, so a second call shows nothing.
void showHistoryStartupProblems(BuildContext context) {
  final problems = takeHistoryStartupProblems();
  if (problems.isEmpty) return;
  final l10n = L10n.of(context);
  for (final problem in problems) {
    showWpAppError(
      context,
      id: switch (problem) {
        HistoryStartupProblem.moveFailed => 'history-move-failed',
        HistoryStartupProblem.backupFailed => 'history-backup-failed',
      },
      message: switch (problem) {
        HistoryStartupProblem.moveFailed => l10n.startupHistoryMoveFailed,
        HistoryStartupProblem.backupFailed => l10n.startupHistoryBackupFailed,
      },
    );
  }
}
