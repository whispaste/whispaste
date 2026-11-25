import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/media_pause/media_pause_backends.dart';
import 'package:whispaste/services/media_pause/media_pause_controller.dart';
import 'package:whispaste/services/media_pause/media_pause_providers.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/memory_pressure.dart';

import 'fixtures/semantics_tree_recorder.dart';

/// Runs before every test file under test/.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Per-test time limit (global test-strategy.md §3b), also for testWidgets: it reads the binding
  // default (10 min) when the test registers, so the binding must exist and
  // carry the limit before testMain. It is the semantics recording binding
  // with recording off, so the semantics tests can still turn it on.
  SemanticsRecordingBinding.install().defaultTestTimeout = const Timeout(
    Duration(seconds: 10),
  );
  // The test binding answers every dart:io HttpClient request with 400 (it
  // installs HttpOverrides). Installing it for every file broke the loopback
  // tests that talk to a real server socket (automation API, hooks, CLI).
  // Unit tests never reach the internet, so the override is removed again.
  HttpOverrides.global = null;
  // Every app-data path goes to a scratch folder. Without this, code that
  // sweeps or erases app data (note image folders) would act on the real
  // app data directory of whoever runs the tests.
  final sandbox = Directory.systemTemp.createTempSync('whispaste_test_data_');
  paths.appDataDirOverride = sandbox.path;
  // Tests stay silent (#1491): the app logger mirrors every line to the
  // terminal through debugPrint, which added up to 91 MB per full run. The
  // binding above installs the silent callback itself
  // (SemanticsRecordingBinding.debugPrintOverride), so its per-test check
  // of the foundation debug variables holds. A failing test's exception
  // report goes out through debugPrint as well, so the reporter prints loud
  // for that one call; otherwise the log only says "see exception logs
  // above" with nothing above.
  final reportQuietly = reportTestException;
  reportTestException = (details, description) {
    final quiet = debugPrint;
    debugPrint = debugPrintSynchronously;
    try {
      reportQuietly(details, description);
    } finally {
      debugPrint = quiet;
    }
  };
  // Tests open many in-memory databases of the same class on purpose; drift
  // printed a warning with a stack trace for each one (84 per run of the
  // snippets and dictionary pages alone), bypassing debugPrint.
  // A test that changes the view (size, pixel ratio, padding) and resets only
  // part of it leaves the next file a different screen: in a lab bundle a
  // pixel ratio of 1 left behind turned 800x600 into 2400x1800 and moved the
  // onboarding page into its wide layout (lab run 2854). Every test starts
  // with the binding's default view.
  tearDown(() {
    for (final view
        in TestWidgetsFlutterBinding.instance.platformDispatcher.views) {
      view.reset();
    }
  });
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  // Free RAM differs per host (CI runners are small), so the RAM precheck
  // must not read the real machine. Tests that exercise the precheck inject
  // their own reader.
  defaultMemorySnapshotReader = () async => null;
  // Never open the real media-control channel from widget tests.
  mediaPauseBackendFactory = () => const UnavailableMediaPauseBackend();
  mediaDuckBackendFactory = () => const UnavailableMediaDuckBackend();
  duckJournalFactory = MemoryDuckJournal.new;
  try {
    await testMain();
  } finally {
    paths.appDataDirOverride = null;
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  }
}
