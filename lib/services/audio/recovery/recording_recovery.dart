/// Startup recovery of interrupted recordings: lists them, recovers the audio
/// through the import queue, or discards them.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/logging/app_logger.dart';
import '../import/audio_import_providers.dart';
import '../../path_service.dart';
import '../import/audio_import_queue.dart';
import '../retention/pending_wipe.dart';
import 'recording_journal.dart';
import 'recording_journal_provider.dart';

final _log = AppLogger('RecordingRecovery');

/// Smallest WAV that holds any audio: the 44-byte header plus one sample.
const int _minWavBytes = 46;

/// Interrupted recordings and the count of corrupt journal files, read at
/// startup. Invalidate after a recover or discard action.
///
/// Journal entries left by an interruption. Queued wipe leftovers are removed
/// first, so a journal entry of a forgotten recording is never offered again.
final interruptedRecordingsProvider = FutureProvider<RecordingJournalScan>((
  ref,
) async {
  final db = ref.read(historyDatabaseProvider);
  try {
    await applyPendingWipe(
      referencedPaths: () async => {
        for (final row in await db.listAudioAttachments()) row.filepath,
      },
    );
  } on Object catch (e) {
    _log.warning('Pending wipe cleanup before recovery failed: $e');
  }
  return ref.watch(recordingJournalProvider).scan();
});

/// What a recover action achieved.
enum RecoveryOutcome {
  /// The audio was handed to the import queue and transcribed.
  recovered,

  /// The journal says audio was not kept (retention off), or no audio was
  /// captured before the interruption. Only the journal entry is removed.
  noAudio,

  /// The import failed. The audio and the journal entry stay for a retry.
  failed,
}

final recordingRecoveryProvider = Provider<RecordingRecovery>(
  (ref) => RecordingRecovery(
    audioDir: retainedAudioDir(),
    transcribe: (wavPath) async {
      final notifier = ref.read(audioImportQueueProvider.notifier);
      final result = await notifier.addFiles([wavPath]);
      // Only the jobs this call created count; another import with the same
      // file name must not make this recording look recovered.
      final ownIds = result.jobIds.toSet();
      final own = ref
          .read(audioImportQueueProvider)
          .where((j) => ownIds.contains(j.id));
      return own.isNotEmpty && own.every((j) => j.status == ImportStatus.done);
    },
  ),
);

class RecordingRecovery {
  RecordingRecovery({required this.audioDir, required this.transcribe});

  /// The only folder whose WAV files recovery may import or delete.
  final String audioDir;

  /// Imports and transcribes one WAV. Returns true only when it succeeded.
  final Future<bool> Function(String wavPath) transcribe;

  /// Transcribes the audio of [recording] and removes its journal entry and
  /// scratch audio. Retention decides whether the import keeps the audio.
  Future<RecoveryOutcome> recover(InterruptedRecording recording) async {
    final wav = _ownAudio(recording);
    if (wav == null || !await _hasAudio(wav)) {
      await _removeJournal(recording);
      return RecoveryOutcome.noAudio;
    }
    // The audio stays on disk when the import fails, so a retry is possible.
    if (!await transcribe(wav)) {
      return RecoveryOutcome.failed;
    }
    await _removeAudio(wav);
    await _removeJournal(recording);
    return RecoveryOutcome.recovered;
  }

  /// Removes the journal entry and any audio of [recording] without importing.
  Future<void> discard(InterruptedRecording recording) async {
    final wav = _ownAudio(recording);
    if (wav != null) await _removeAudio(wav);
    await _removeJournal(recording);
  }

  /// The journal's WAV path, but only when it lies inside [audioDir]. A path
  /// outside it is treated as no audio and is never touched.
  String? _ownAudio(InterruptedRecording recording) {
    final wav = recording.wavPath;
    return isContainedAudioPath(wav, audioDir) ? wav : null;
  }

  Future<bool> _hasAudio(String wavPath) async {
    final file = File(wavPath);
    if (!await file.exists()) return false;
    return await file.length() >= _minWavBytes;
  }

  Future<void> _removeAudio(String wavPath) async {
    final file = File(wavPath);
    if (await file.exists()) await file.delete();
  }

  Future<void> _removeJournal(InterruptedRecording recording) async {
    final file = File(recording.journalPath);
    if (await file.exists()) await file.delete();
  }
}
