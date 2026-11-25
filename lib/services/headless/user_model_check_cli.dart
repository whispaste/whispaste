/// `whispaste --check-user-model <id> --out <report.json>`: the child side of
/// a user model's check (#1789, `user_model_checker.dart`).
///
/// Runs before crash reporting, the single-instance guard and any window, like
/// the other headless modes, and never touches the settings or the history
/// database. It only reads `user_models.json` and the model's own folder, runs
/// the format check and the short test, writes the report and exits. A native
/// crash of the model ends this child only; the parent then finds no report.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

import '../stt/stt_benchmark.dart' show SttBenchmark;
import '../user_models/user_model.dart';
import '../user_models/user_model_check.dart';
import '../user_models/user_model_checker.dart' show kCheckUserModelFlag;
import '../user_models/user_model_inspector.dart';
import '../user_models/user_model_store.dart';
import 'headless_cli.dart' show headlessExitUsage;

/// Whether [args] ask for a user model check.
bool isUserModelCheckRequested(List<String> args) =>
    args.contains(kCheckUserModelFlag);

/// Runs the check for [args] and returns the process exit code.
Future<int> runUserModelCheckCli(List<String> args) async {
  final at = args.indexOf(kCheckUserModelFlag);
  final outAt = args.indexOf('--out');
  if (at < 0 ||
      at + 1 >= args.length ||
      outAt < 0 ||
      outAt + 1 >= args.length) {
    stderr.writeln(
      'Usage: whispaste $kCheckUserModelFlag <model id> --out <report.json>',
    );
    return headlessExitUsage;
  }
  final id = args[at + 1];
  final out = File(args[outAt + 1]);
  WidgetsFlutterBinding.ensureInitialized();
  final store = UserModelStore();
  final model = store.readSync().byId(id);
  final UserModelCheckReport report;
  if (model == null) {
    report = const UserModelCheckReport(
      inspection: InspectionResult.failed(UserModelFailure.missingFiles),
    );
  } else {
    report = await runUserModelCheck(
      model,
      store.modelDir(id),
      clip: SttBenchmark.referenceWav,
    );
  }
  await out.writeAsString(jsonEncode(report.toJson()), flush: true);
  return report.ok ? 0 : 1;
}
