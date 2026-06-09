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
///
/// After the ZIP is written, `buildAndWriteReport` optionally calls the
/// delivery step (reveal + prefilled mail) via [DeliveryStep] — also
/// injectable so the orchestration remains fully unit-testable.
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'delivery.dart';

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

/// Injectable delivery step: receives the ZIP path and performs the
/// post-report actions (reveal in file manager + open prefilled mail client).
///
/// In production: [deliverReport].
/// In tests: a fake that captures the call without spawning real processes.
typedef DeliveryStep = Future<void> Function(String zipPath);

/// Gathers the report, writes a `.txt` file and a `.zip` bundle to
/// [outputDir] (created if absent), then optionally runs [deliveryStep].
///
/// [reportProducer] is an injectable seam — in production this is
/// `() async => gatherDiagnosticsReport(...)`, in tests a simple stub.
///
/// [clock] is an injectable seam for the timestamp (defaults to `DateTime.now`).
///
/// [deliveryStep] is an injectable seam for the post-report delivery
/// (reveal + mail). Pass `null` or omit to skip delivery (e.g. in CI).
///
/// Returns the path to the written `.zip` file.
Future<String> buildAndWriteReport({
  required String outputDir,
  required Future<String> Function() reportProducer,
  DateTime Function()? clock,
  DeliveryStep? deliveryStep,
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

  // 4. Post-report delivery: reveal ZIP + open prefilled mail client.
  //    Skipped when deliveryStep is null (e.g. CI smoke runs).
  await deliveryStep?.call(zipPath);

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
