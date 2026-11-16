/// One-time encryption of the recordings retained before #1021.
///
/// Runs on every start, delayed so it never competes with startup and the
/// first dictation. After the first full run it only reads one header per
/// recording, so it needs no "done" marker, and a run that was aborted
/// (app quit, crash, power loss) simply continues at the next start. It goes
/// by the attachment rows, not by the folder: a recording still being
/// written into the folder is not touched.
///
/// Parked dictations (`PendingAudioQueue`) are sealed when they are parked;
/// the run here catches the ones whose sealing failed or that were parked
/// before #1021. Only a WAV with its `<id>.json` beside it counts as parked.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/data/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../path_service.dart';
import 'recording_vault.dart';

final _log = AppLogger('RecordingMigration');

/// How long after start the migration waits.
const recordingMigrationDelay = Duration(seconds: 20);

/// Encrypts every plain retained recording after [delay]. Never throws.
Future<void> scheduleRecordingMigration(
  ProviderContainer container, {
  Duration delay = recordingMigrationDelay,
}) async {
  await Future<void>.delayed(delay);
  try {
    await migrateRetainedRecordings(
      db: container.read(historyDatabaseProvider),
      vault: container.read(recordingVaultProvider),
      audioDir: retainedAudioDir(),
      pendingDir: pendingAudioDir(),
    );
  } on Object catch (e) {
    _log.warning('Recording migration skipped: $e');
  }
}

/// Seals the recordings linked in [db] and the parked ones in [pendingDir]
/// that are still plain, after removing temp files an aborted run left in
/// [audioDir] and [pendingDir].
Future<Map<ProtectOutcome, int>> migrateRetainedRecordings({
  required HistoryDatabase db,
  required RecordingVault vault,
  required String audioDir,
  String? pendingDir,
}) async {
  final attachments = await db.listAudioAttachments();
  return vault.migrate(
    [
      for (final a in attachments) a.filepath,
      if (pendingDir != null) ...await _parkedRecordings(pendingDir),
    ],
    directories: [audioDir, ?pendingDir],
  );
}

/// The WAVs in [dir] whose record is written, so a park still in progress
/// is left alone.
Future<List<String>> _parkedRecordings(String dir) async {
  final paths = <String>[];
  try {
    final d = Directory(dir);
    if (!await d.exists()) return paths;
    await for (final entity in d.list(followLinks: false)) {
      if (entity is! File || p.extension(entity.path) != '.wav') continue;
      if (await File(p.setExtension(entity.path, '.json')).exists()) {
        paths.add(entity.path);
      }
    }
  } on Object catch (e) {
    _log.warning('Parked recordings could not be listed: $e');
  }
  paths.sort();
  return paths;
}
