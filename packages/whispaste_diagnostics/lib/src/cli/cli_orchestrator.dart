/// CLI orchestration for WhisPaste-Diagnose.
///
/// Provides the testable `buildAndWriteReport` function that wires
/// gather → write .txt → bundle .zip into the given output directory.
/// The thin `main()` in `bin/whispaste_diagnose.dart` calls this with
/// the real Desktop path and the live `gatherDiagnosticsReport` producer.
///
/// All dependencies are injected so tests can drive the flow against a
/// temp directory without touching the real Desktop or requiring the
/// WhisPaste app to be installed.
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Timestamp-based report file stem, e.g. `WhisPaste-Diagnose-20260609-143022`.
String _buildFileStem(DateTime now) {
  final y = now.year.toString().padLeft(4, '0');
  final mo = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final h = now.hour.toString().padLeft(2, '0');
  final mi = now.minute.toString().padLeft(2, '0');
  final s = now.second.toString().padLeft(2, '0');
  return 'WhisPaste-Diagnose-$y$mo$d-$h$mi$s';
}

/// Gathers the report, writes a `.txt` file and a `.zip` bundle to
/// [outputDir] (created if absent).
///
/// [reportProducer] is an injectable seam — in production this is
/// `() async => gatherDiagnosticsReport(...)`, in tests a simple stub.
///
/// [clock] is an injectable seam for the timestamp (defaults to `DateTime.now`).
///
/// Returns the path to the written `.zip` file.
Future<String> buildAndWriteReport({
  required String outputDir,
  required Future<String> Function() reportProducer,
  DateTime Function()? clock,
}) async {
  final now = (clock ?? DateTime.now)();
  final stem = _buildFileStem(now);

  final dir = Directory(outputDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  final txtPath = p.join(outputDir, '$stem.txt');
  final zipPath = p.join(outputDir, '$stem.zip');

  // 1. Gather report content.
  final content = await reportProducer();

  // 2. Write .txt.
  File(txtPath).writeAsStringSync(content);

  // 3. Bundle into .zip (pure-Dart, no native dependency).
  final archive = Archive();
  final txtBytes = File(txtPath).readAsBytesSync();
  archive.addFile(ArchiveFile('$stem.txt', txtBytes.length, txtBytes));
  final zipBytes = ZipEncoder().encode(archive);
  File(zipPath).writeAsBytesSync(zipBytes!);

  return zipPath;
}

/// Returns the platform-appropriate Desktop path.
///
/// [environment] and [platformOverride] are injectable for testing;
/// production code omits both and relies on [Platform.environment] /
/// [Platform.operatingSystem].
String resolveDesktopPath({
  Map<String, String>? environment,
  String? platformOverride,
}) {
  final env = environment ?? Platform.environment;
  final platform = platformOverride ?? Platform.operatingSystem;

  if (platform == 'windows') {
    final userProfile = env['USERPROFILE'] ?? env['HOME'] ?? '';
    return p.join(userProfile, 'Desktop');
  }
  // macOS and Linux both put the Desktop under $HOME/Desktop.
  final home = env['HOME'] ?? '';
  return p.join(home, 'Desktop');
}
