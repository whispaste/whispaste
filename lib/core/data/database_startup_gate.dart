/// Startup check that runs before the app shell reads from the database.
///
/// [HistoryDatabase] refuses a file written by a newer schema inside its
/// migration, before any write happens. This gate turns that refusal into a
/// start screen, so the shell never starts against a database it cannot use.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/startup/database_too_new_screen.dart';
import 'database.dart';

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

/// Shows [child] once the database opens. A file from a newer build shows
/// [DatabaseTooNewScreen] instead. Other open errors keep the earlier
/// behaviour: the shell is shown and its own error handling applies.
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
            _ => child,
          },
          data: (_) => child,
        );
  }
}
