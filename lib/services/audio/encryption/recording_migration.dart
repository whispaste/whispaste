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
///
/// With encryption switched off (#1022) the same run goes the other way and
/// turns sealed recordings back into plain WAVs. Right after a switch the
/// start runs it once in front of the app with a progress screen
/// ([convertRecordingsAfterSwitch]); the delayed run here then only finds
/// what that run could not do (no key yet, a file in use).
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/data/database.dart';
import '../../../core/data/encryption_preference.dart';
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
      toPlain: !encryptionOnThisSession(),
    );
  } on Object catch (e) {
    _log.warning('Recording migration skipped: $e');
  }
}

/// Converts the recordings right after an encryption switch (#1022), in
/// front of the app, while [encryptionConversionProgress] shows how far it
/// is. Runs only while the switch marker is set and removes it at the end; a
/// run cut off keeps the marker and is repeated at the next start, where
/// files already converted only cost a header read. Never throws.
Future<void> convertRecordingsAfterSwitch({
  required HistoryDatabase db,
  required RecordingVault vault,
  required EncryptionPreference preference,
  required bool toPlain,
  required String audioDir,
  String? pendingDir,
}) async {
  if (!preference.switchPending) return;
  encryptionConversionProgress.value = EncryptionConversionProgress(
    toPlain: toPlain,
    step: EncryptionConversionStep.recordings,
  );
  try {
    await migrateRetainedRecordings(
      db: db,
      vault: vault,
      audioDir: audioDir,
      pendingDir: pendingDir,
      toPlain: toPlain,
      onProgress: (done, total) =>
          encryptionConversionProgress.value = EncryptionConversionProgress(
            toPlain: toPlain,
            step: EncryptionConversionStep.recordings,
            done: done,
            total: total,
          ),
    );
    // Files left over (no key yet, a failure) are kept as they are and
    // picked up by the delayed run of every start.
    preference.clearSwitchPending();
  } on Object catch (e) {
    _log.warning('Recording conversion after the switch stopped: $e');
  } finally {
    encryptionConversionProgress.value = null;
  }
}

/// The start-time run of [convertRecordingsAfterSwitch], awaited by the
/// start gate after the history opened. Never fails.
final recordingConversionAtStartProvider = FutureProvider<void>((ref) async {
  try {
    await convertRecordingsAfterSwitch(
      db: ref.read(historyDatabaseProvider),
      vault: ref.read(recordingVaultProvider),
      preference: EncryptionPreference(appDataDir()),
      toPlain: !encryptionOnThisSession(),
      audioDir: retainedAudioDir(),
      pendingDir: pendingAudioDir(),
    );
  } on Object catch (e) {
    _log.warning('Recording conversion at start skipped: $e');
  }
}, retry: (_, _) => null);

/// Seals the recordings linked in [db] and the parked ones in [pendingDir]
/// that are still plain (with [toPlain]: opens the sealed ones back), after
/// removing temp files an aborted run left in [audioDir] and [pendingDir].
Future<Map<ProtectOutcome, int>> migrateRetainedRecordings({
  required HistoryDatabase db,
  required RecordingVault vault,
  required String audioDir,
  String? pendingDir,
  bool toPlain = false,
  void Function(int done, int total)? onProgress,
}) async {
  final attachments = await db.listAudioAttachments();
  return vault.migrate(
    [
      for (final a in attachments) a.filepath,
      if (pendingDir != null) ...await _parkedRecordings(pendingDir),
    ],
    directories: [audioDir, ?pendingDir],
    toPlain: toPlain,
    onProgress: onProgress,
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
