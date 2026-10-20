/// Daily retention sweeps: the history trash purge and the expiry of retained
/// audio. The two run independently, so a disabled trash purge still lets the
/// audio sweep run, and a failure in one does not stop the other.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/data/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../services/path_service.dart';
import '../import/audio_import_providers.dart';
import '../recovery/recording_journal_provider.dart';
import 'audio_retention.dart';
import 'pending_wipe.dart';

final _log = AppLogger('RetentionSchedule');

const Duration kRetentionSweepInterval = Duration(hours: 24);

/// Runs the sweeps once now and then every [interval]. The returned timer lets
/// a caller stop the schedule.
Timer startRetentionSchedule(
  ProviderContainer container, {
  Duration interval = kRetentionSweepInterval,
}) {
  Future<void> sweep() async {
    final db = container.read(historyDatabaseProvider);
    try {
      await applyPendingWipe(referencedPaths: () => _attachmentPaths(db));
    } on Object catch (e) {
      _log.warning('Pending wipe cleanup failed: $e');
    }
    final trashDays =
        container.read(settingsProvider).value?.historyAutoTrashDays ?? 0;
    if (trashDays > 0) {
      try {
        await db.purgeTrash(days: trashDays);
      } on Object catch (e) {
        _log.warning('Trash purge failed: $e');
      }
    }
    try {
      final now = DateTime.now();
      await sweepRetainedAudio(db: db, now: now);
      await sweepOrphanedRetainedWavs(
        directory: retainedAudioDir(),
        referencedPaths: await _referencedWavPaths(container, db),
        now: now,
      );
      await sweepOrphanedImportWork(
        workDir: importWorkDir(),
        liveJobIds: _liveImportJobIds(container),
        now: now,
      );
    } on Object catch (e) {
      _log.warning('Audio retention sweep failed: $e');
    }
  }

  unawaited(sweep());
  return Timer.periodic(interval, (_) => unawaited(sweep()));
}

/// Audio files named by an attachment row. Only these protect a queued wipe.
Future<Set<String>> _attachmentPaths(HistoryDatabase db) async {
  final rows = await db.listAudioAttachments();
  return {for (final row in rows) row.filepath};
}

/// Import jobs still queued or running. Their work folders are never swept.
Set<String> _liveImportJobIds(ProviderContainer container) => {
  for (final job in container.read(audioImportQueueProvider))
    if (!job.isFinished) job.id,
};

/// WAV paths that must survive the orphan sweep: those linked to an attachment
/// row and those named by an open journal entry (a recording in progress or
/// one awaiting recovery).
Future<Set<String>> _referencedWavPaths(
  ProviderContainer container,
  HistoryDatabase db,
) async {
  final rows = await db.listAudioAttachments();
  final scan = await container.read(recordingJournalProvider).scan();
  return {
    for (final row in rows) row.filepath,
    for (final recording in scan.recordings)
      if (recording.wavPath != null) recording.wavPath!,
  };
}
