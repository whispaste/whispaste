/// Command-line entry point for the WhisPaste automation API (WP-38 / 8.2).
///
/// Run with `dart run tool/whispaste.dart <command>`. See `--help`.
library;

import 'dart:io';

import 'package:whispaste/services/automation_api/automation_cli.dart';

Future<void> main(List<String> args) async {
  final code = await runAutomationCli(
    args,
    environment: Platform.environment,
    out: stdout,
    err: stderr,
  );
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
