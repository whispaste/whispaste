import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/path_service.dart' as paths;
import '../logging/app_logger.dart';
import 'database.dart';

final _log = AppLogger('HistoryVacuum');

/// VACUUM runs only up to this file size (AR-19: no external tools, the
/// same rule on every platform, including the MAS sandbox and MSIX).
const int historyVacuumMaxBytes = 512 * 1024 * 1024;

/// Failed attempts after which the VACUUM is given up for good.
const int historyVacuumMaxAttempts = 3;

/// Outcome of one [HistoryVacuum.runOnce] call.
enum HistoryVacuumOutcome {
  /// The one-time run already happened (or was given up) on this installation.
  alreadyDone,

  /// The file has no free pages, so there is nothing to reclaim.
  nothingToReclaim,

  /// The file is larger than [historyVacuumMaxBytes], or its size is unknown.
  tooLarge,

  /// VACUUM ran and the flag is set.
  vacuumed,

  /// VACUUM failed; counted, the flag stays open for a later start.
  failed,

  /// The last allowed attempt failed; the run is given up.
  gaveUp,
}

/// Persistent state of the one-time VACUUM.
abstract class HistoryVacuumFlag {
  Future<bool> isDone();
  Future<int> failedAttempts();
  Future<void> recordFailure();
  Future<void> markDone();
}

/// [HistoryVacuumFlag] in SharedPreferences. Read or write failures count as
/// "not done" and "no attempts yet".
class SharedPrefsHistoryVacuumFlag implements HistoryVacuumFlag {
  static const _doneKey = 'history.vacuum_after_v27_done';
  static const _attemptsKey = 'history.vacuum_after_v27_failed_attempts';

  @override
  Future<bool> isDone() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_doneKey) ?? false;
    } on Exception {
      return false;
    }
  }

  @override
  Future<int> failedAttempts() async {
    try {
      return (await SharedPreferences.getInstance()).getInt(_attemptsKey) ?? 0;
    } on Exception {
      return 0;
    }
  }

  @override
  Future<void> recordFailure() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_attemptsKey, (prefs.getInt(_attemptsKey) ?? 0) + 1);
    } on Exception catch (e) {
      _log.warning('Could not persist the VACUUM attempt counter: $e');
    }
  }

  @override
  Future<void> markDone() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_doneKey, true);
    } on Exception catch (e) {
      _log.warning('Could not persist the VACUUM flag: $e');
    }
  }
}

/// Size in bytes of the file at [path], or null when it cannot be read. A seam
/// for tests; the default is plain file I/O and identical on every platform.
typedef FileSizeReader = Future<int?> Function(String path);

Future<int?> defaultFileSizeReader(String path) async {
  try {
    return await File(path).length();
  } on FileSystemException {
    return null;
  }
}

/// One-time VACUUM after the v27 upgrade (GS-017). It rewrites the file so
/// freed pages from before secure_delete are gone. Runs only for files up to
/// [historyVacuumMaxBytes], because a VACUUM needs room for a copy.
class HistoryVacuum {
  HistoryVacuum({
    required this.database,
    required this.databasePath,
    required this.flag,
    this.fileSize = defaultFileSizeReader,
    Future<void> Function()? vacuumAction,
  }) : _vacuumAction = vacuumAction ?? database.vacuum;

  final HistoryDatabase database;
  final String databasePath;
  final HistoryVacuumFlag flag;
  final FileSizeReader fileSize;
  final Future<void> Function() _vacuumAction;

  Future<HistoryVacuumOutcome> runOnce() async {
    if (await flag.isDone()) return HistoryVacuumOutcome.alreadyDone;
    try {
      if (await _pragma('freelist_count') == 0) {
        await flag.markDone();
        return HistoryVacuumOutcome.nothingToReclaim;
      }
      final bytes = await fileSize(databasePath);
      if (bytes == null || bytes > historyVacuumMaxBytes) {
        _log.info('VACUUM skipped: file size $bytes bytes');
        return HistoryVacuumOutcome.tooLarge;
      }
      await _vacuumAction();
      await flag.markDone();
      return HistoryVacuumOutcome.vacuumed;
    } on Exception catch (e, st) {
      await flag.recordFailure();
      final attempts = await flag.failedAttempts();
      _log.warning('VACUUM after upgrade failed (attempt $attempts)', e, st);
      if (attempts >= historyVacuumMaxAttempts) {
        await flag.markDone();
        return HistoryVacuumOutcome.gaveUp;
      }
      return HistoryVacuumOutcome.failed;
    }
  }

  Future<int> _pragma(String name) async {
    final row = await database.customSelect('PRAGMA $name').getSingle();
    return row.data.values.single as int;
  }
}

/// Starts the one-time VACUUM [delay] after launch, in the background. Launch
/// is never blocked (DEV-71). The timer belongs to the provider and is
/// cancelled when the container is disposed (DEV-87).
final historyVacuumSchedulerProvider = Provider<Timer>((ref) {
  final timer = Timer(const Duration(seconds: 30), () {
    final db = ref.read(historyDatabaseProvider);
    unawaited(
      HistoryVacuum(
        database: db,
        databasePath: p.join(paths.appDataDir(), 'history.db'),
        flag: SharedPrefsHistoryVacuumFlag(),
      ).runOnce(),
    );
  });
  ref.onDispose(timer.cancel);
  return timer;
});
