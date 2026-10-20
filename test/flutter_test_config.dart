import 'dart:async';
import 'dart:io';

import 'package:whispaste/services/path_service.dart' as paths;

/// Runs before every test file under test/.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Every app-data path goes to a scratch folder. Without this, code that
  // sweeps or erases app data (note image folders) would act on the real
  // app data directory of whoever runs the tests.
  final sandbox = Directory.systemTemp.createTempSync('whispaste_test_data_');
  paths.appDataDirOverride = sandbox.path;
  try {
    await testMain();
  } finally {
    paths.appDataDirOverride = null;
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  }
}
