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
///
/// After an encryption switch (#1022) the gate also holds the shell while the
/// data is converted: the history before it opens, the recordings right
/// after, both shown on [EncryptionConversionScreen].
library;

import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/path_service.dart' as paths;

import '../../features/startup/data_key_locked_screen.dart';
import '../../features/startup/encryption_conversion_screen.dart';
import '../../services/audio/encryption/recording_migration.dart';
import '../../features/startup/database_too_new_screen.dart';
import '../../features/startup/database_upgrade_interrupted_screen.dart';
import '../../features/startup/instance_check_unavailable_screen.dart';
import 'database.dart';
import 'encryption_preference.dart';
import 'instance_write_gate.dart';

/// Opens the history database once. The shell is only built after this
/// completes, so no other provider can touch the file first.
///
/// Riverpod retries failed providers by default. A refused newer file would
/// then be reopened ten times with back-off and the gate would sit on its
/// blank state for seconds, so this probe never retries.
///
/// The real database runs on a background isolate, so drift hands an open
/// error over as [DriftRemoteException]. The probe rethrows the original
/// cause, so the gate sees the typed exception: before, a file from a newer
/// build fell through to the shell, which showed the first-run onboarding
/// (#1925).
final databaseStartupProbeProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(historyDatabaseProvider);
  try {
    await db.customSelect('SELECT 1').get();
  } on DriftRemoteException catch (e, stack) {
    Error.throwWithStackTrace(
      unwrapDriftRemote(e),
      e.remoteStackTrace ?? stack,
    );
  }
}, retry: (_, _) => null);

/// The original error behind any number of [DriftRemoteException] layers
/// (one per isolate hop).
Object unwrapDriftRemote(Object error) {
  var current = error;
  while (current is DriftRemoteException) {
    current = current.remoteCause;
  }
  return current;
}

/// True once the database has opened and its start-path self-heal rebuilt a
/// missing or damaged search index; the shell tells the user once (#668).
/// Open errors are left to [DatabaseStartupGate].
final indexRepairedOnOpenProvider = FutureProvider<bool>((ref) async {
  await ref.watch(databaseStartupProbeProvider.future);
  return ref.read(historyDatabaseProvider).indexesRepairedOnOpen;
}, retry: (_, _) => null);

/// Whether this start has recordings to convert after an encryption switch
/// (#1022). Read once; the conversion clears the marker itself.
final encryptionSwitchPendingProvider = Provider<bool>((ref) {
  try {
    return EncryptionPreference(paths.appDataDir()).switchPending;
  } on Object {
    return false;
  }
});

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
    final blank = ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
    return ref
        .watch(databaseStartupProbeProvider)
        .when(
          loading: () => EncryptionConversionListener(idle: blank),
          error: (error, _) => switch (error) {
            DatabaseTooNewException() => DatabaseTooNewScreen(exception: error),
            DatabaseUpgradeInterruptedException() =>
              const DatabaseUpgradeInterruptedScreen(),
            HistoryKeyUnavailableException() => const DataKeyLockedScreen(),
            InstanceCheckUnavailableException() =>
              const InstanceCheckUnavailableScreen(),
            _ => child,
          },
          data: (_) => ref.watch(encryptionSwitchPendingProvider)
              ? ref
                    .watch(recordingConversionAtStartProvider)
                    .when(
                      loading: () => EncryptionConversionListener(idle: blank),
                      error: (_, _) => child,
                      data: (_) => child,
                    )
              : child,
        );
  }
}
