import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../widgets/wp_page_notice.dart';
import '../settings/data_key/data_key_flows.dart';

/// Tells the user what went wrong while the history database opened (#602):
/// a failed move out of the old folder, a safety copy that could not be
/// written. Each problem stands as an app notice until it is closed, with the
/// cause, the state that stays in use and the next step. Call once after the
/// start-up gate; the problems are taken, so a second call shows nothing.
///
/// A lost data key (#1023) is one of them: the encrypted history was set
/// aside unchanged and the app started empty. That notice says so and offers
/// the restore dialog (recovery code or backup file); the old history comes
/// back on the next start once its key is restored. When that happened, a
/// second notice says the history is back and where the interim one went.
void showHistoryStartupProblems(BuildContext context) {
  final problems = takeHistoryStartupProblems();
  if (problems.isEmpty) return;
  final l10n = L10n.of(context);
  for (final problem in problems) {
    final restore = problem == HistoryStartupProblem.keyLostStartedEmpty;
    showWpAppError(
      context,
      id: historyStartupNoticeId(problem),
      message: switch (problem) {
        HistoryStartupProblem.moveFailed => l10n.startupHistoryMoveFailed,
        HistoryStartupProblem.backupFailed => l10n.startupHistoryBackupFailed,
        HistoryStartupProblem.keyLostStartedEmpty => l10n.startupHistoryKeyLost,
        HistoryStartupProblem.setAsideHistoryRestored =>
          l10n.startupHistorySetAsideRestored,
      },
      actionLabel: restore ? l10n.dataKeyRestore : null,
      actionTestId: restore ? 'history-key-lost-restore' : null,
      onAction: restore ? () => _openRestore(context) : null,
    );
  }
}

/// Notice id (and testID suffix, `page-notice-<id>`) of [problem].
String historyStartupNoticeId(HistoryStartupProblem problem) =>
    switch (problem) {
      HistoryStartupProblem.moveFailed => 'history-move-failed',
      HistoryStartupProblem.backupFailed => 'history-backup-failed',
      HistoryStartupProblem.keyLostStartedEmpty => 'history-key-lost',
      HistoryStartupProblem.setAsideHistoryRestored =>
        'history-set-aside-restored',
    };

void _openRestore(BuildContext context) {
  if (!context.mounted) return;
  final flow = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(dataKeyRestoreFlowProvider);
  unawaited(flow(context));
}
