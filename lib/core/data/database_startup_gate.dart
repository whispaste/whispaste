/// Startup check that runs before the app shell reads from the database.
///
/// [HistoryDatabase] refuses a file written by a newer schema inside its
/// migration, before any write happens, and rolls back an upgrade that stops
/// on a transient SQLite error. An encrypted file whose data key the system
/// hands out only after consent fails with [HistoryKeyUnavailableException]
/// (#1427). A launch whose single-instance check could not run keeps the
/// file closed with [InstanceCheckUnavailableException] (#1647). This gate
/// turns all four into a start screen, so the shell never starts against a
/// database it cannot use (and never shows the onboarding over settings it
/// could not read).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/startup/data_key_locked_screen.dart';
import '../../features/startup/database_too_new_screen.dart';
import '../../features/startup/database_upgrade_interrupted_screen.dart';
import '../../features/startup/instance_check_unavailable_screen.dart';
import 'database.dart';
import 'instance_write_gate.dart';

/// Opens the history database once. The shell is only built after this
/// completes, so no other provider can touch the file first.
///
/// Riverpod retries failed providers by default. A refused newer file would
/// then be reopened ten times with back-off and the gate would sit on its
/// blank state for seconds, so this probe never retries.
final databaseStartupProbeProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(historyDatabaseProvider);
  await db.customSelect('SELECT 1').get();
}, retry: (_, _) => null);

/// True once the database has opened and its start-path self-heal rebuilt a
/// missing or damaged search index; the shell tells the user once (#668).
/// Open errors are left to [DatabaseStartupGate].
final indexRepairedOnOpenProvider = FutureProvider<bool>((ref) async {
  await ref.watch(databaseStartupProbeProvider.future);
  return ref.read(historyDatabaseProvider).indexesRepairedOnOpen;
}, retry: (_, _) => null);

/// Shows [child] once the database opens. A file from a newer build shows
/// [DatabaseTooNewScreen] instead, an interrupted upgrade shows
/// [DatabaseUpgradeInterruptedScreen] with a retry, a data key that needs
/// consent shows [DataKeyLockedScreen], an unverified single-instance check
/// shows [InstanceCheckUnavailableScreen]. Other open errors keep the
/// earlier behaviour: the shell is shown and its own error handling applies.
class DatabaseStartupGate extends ConsumerWidget {
  const DatabaseStartupGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(databaseStartupProbeProvider)
        .when(
          loading: () =>
              ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          error: (error, _) => switch (error) {
            DatabaseTooNewException() => DatabaseTooNewScreen(exception: error),
            DatabaseUpgradeInterruptedException() =>
              const DatabaseUpgradeInterruptedScreen(),
            HistoryKeyUnavailableException() => const DataKeyLockedScreen(),
            InstanceCheckUnavailableException() =>
              const InstanceCheckUnavailableScreen(),
            _ => child,
          },
          data: (_) => child,
        );
  }
}
