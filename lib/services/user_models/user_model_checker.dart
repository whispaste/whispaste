/// Where a user model's check runs (#1789, decision 2a):
///
/// - Outside the Mac App Store build: in a child process of the app
///   (`whispaste --check-user-model <id> --out <report>`). A native crash of
///   an unknown model ends only the child; the app reads that as a failed
///   check.
/// - Inside the Mac App Store build, which may not start child processes on
///   the speech path: the format check runs in an isolate, the short test in
///   this process behind a crash marker. Should the model take the app down,
///   the next start finds the marker and takes the model out of use.
///
/// Lives outside `lib/services/stt/` on purpose (see
/// `test/services/stt/mas_symbol_scan_test.dart`); the child is never
/// started in the MAS build ([kIsMasBuild]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../core/config/build_config.dart' show kIsMasBuild;
import '../../core/logging/app_logger.dart';
import 'user_model.dart';
import 'user_model_check.dart';
import 'user_model_inspector.dart';
import 'user_model_store.dart';

final _log = AppLogger('UserModelChecker');

/// Command-line flag of the check child.
const String kCheckUserModelFlag = '--check-user-model';

/// Environment marker of the check child, so it never spawns one itself.
const String kUserModelCheckChildEnv = 'WHISPASTE_USER_MODEL_CHECK_CHILD';

/// How long the whole check may take. Smart Mode models are larger and load
/// slower than speech models.
Duration userModelCheckTimeout(UserModelPurpose purpose) =>
    purpose == UserModelPurpose.smartMode
    ? const Duration(minutes: 6)
    : const Duration(minutes: 3);

/// Runs the check of one model and reports what it found.
abstract interface class UserModelChecker {
  Future<UserModelCheckReport> check(UserModel model);
}

/// Picks the checker for this build.
UserModelChecker defaultUserModelChecker({
  required UserModelStore store,
  required Future<Uint8List> Function() clip,
}) => kIsMasBuild
    ? InProcessUserModelChecker(store: store, clip: clip)
    : ChildProcessUserModelChecker(store: store);

/// The Mac App Store way: isolate for the format check, this process for the
/// short test, guarded by the crash marker.
class InProcessUserModelChecker implements UserModelChecker {
  InProcessUserModelChecker({
    required this.store,
    required this.clip,
    this.shortTest = runUserModelShortTest,
  });

  final UserModelStore store;
  final Future<Uint8List> Function() clip;
  final UserModelShortTest shortTest;

  @override
  Future<UserModelCheckReport> check(UserModel model) async {
    store.markInFlight(model.id);
    try {
      return await runUserModelCheck(
        model,
        store.modelDir(model.id),
        clip: clip,
        shortTest: shortTest,
      ).timeout(
        userModelCheckTimeout(model.purpose),
        onTimeout: () => const UserModelCheckReport(
          inspection: InspectionResult.ok(),
          testFailure: UserModelFailure.shortTestFailed,
        ),
      );
    } finally {
      store.clearInFlight();
    }
  }
}

/// The default way: a child process of the app.
class ChildProcessUserModelChecker implements UserModelChecker {
  ChildProcessUserModelChecker({required this.store, this.executable});

  final UserModelStore store;

  /// The app binary; [Platform.resolvedExecutable] when null.
  final String? executable;

  @override
  Future<UserModelCheckReport> check(UserModel model) async {
    final report = File(p.join(store.modelDir(model.id), 'check-report.json'));
    try {
      if (report.existsSync()) report.deleteSync();
    } on FileSystemException catch (e) {
      // Overwritten by the child anyway.
      _log.debug('Old check report not removed', e);
    }
    final Process process;
    try {
      process = await Process.start(
        executable ?? Platform.resolvedExecutable,
        [kCheckUserModelFlag, model.id, '--out', report.path],
        environment: {...Platform.environment, kUserModelCheckChildEnv: '1'},
      );
    } on Object catch (e) {
      _log.warning('Cannot start the check child: $e');
      return const UserModelCheckReport(
        inspection: InspectionResult.failed(UserModelFailure.checkUnavailable),
      );
    }
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    var timedOut = false;
    final exitCode = await process.exitCode.timeout(
      userModelCheckTimeout(model.purpose),
      onTimeout: () {
        timedOut = true;
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    if (timedOut) {
      _log.warning('Check of ${model.id} timed out');
      return const UserModelCheckReport(
        inspection: InspectionResult.ok(),
        testFailure: UserModelFailure.shortTestFailed,
      );
    }
    if (!report.existsSync()) {
      // The child died before it could write: a native crash while loading
      // or running the model.
      _log.warning(
        'Check child of ${model.id} ended with $exitCode, no report',
      );
      return const UserModelCheckReport(
        inspection: InspectionResult.ok(),
        testFailure: UserModelFailure.crashed,
      );
    }
    try {
      return UserModelCheckReport.fromJson(
        jsonDecode(report.readAsStringSync()),
      );
    } on Object {
      return const UserModelCheckReport(
        inspection: InspectionResult.failed(UserModelFailure.checkUnavailable),
      );
    } finally {
      try {
        report.deleteSync();
      } on FileSystemException catch (e) {
        // Left behind; removed with the model folder.
        _log.debug('Check report left behind', e);
      }
    }
  }
}
