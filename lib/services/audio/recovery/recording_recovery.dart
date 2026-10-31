/// Startup recovery of interrupted recordings: transcribes the audio of each
/// one, keeps it for a retry when the failure can be fixed later, or discards
/// it. Recovery runs once per interrupted recording at startup (see
/// [recoverInterruptedRecordings]); the banner only shows what is left.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/config/settings_provider.dart';
import '../../pending_audio/pending_audio_providers.dart';
import '../../pending_audio/pending_audio_notice.dart';
import '../../pending_audio/pending_audio_queue.dart';
import '../../recording_store.dart';
import '../../transcription/slice_manifest.dart';
import '../capture/capture_dir.dart';
import '../import/audio_import_providers.dart';
import '../../path_service.dart';
import '../import/audio_import_queue.dart';
import '../retention/pending_wipe.dart';
import 'recording_journal.dart';
import 'recording_journal_provider.dart';

final _log = AppLogger('RecordingRecovery');

/// The notice the user gets for a recovery outcome, if any. A recording that
/// had to be deleted is the only one the user has to hear about.
PendingAudioNotice? pendingNoticeForRecovery(RecoveryOutcome outcome) =>
    outcome == RecoveryOutcome.discarded
    ? PendingAudioNotice.interruptedDiscarded
    : null;

/// Error code of a recovered recording that could not be imported or saved
/// to history, and has no engine code of its own.
const String kSaveFailedErrorCode = 'save_failed';

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
  /// The audio was transcribed and saved to history; audio and entry are gone.
  recovered,

  /// The journal says audio was not kept (retention off), or no audio was
  /// captured before the interruption. Only the journal entry is removed.
  noAudio,

  /// The transcription failed with an error that a later try can fix. The
  /// audio is kept in the retry queue, for [pendingAudioMaxAge] at most.
  parked,

  /// The transcription failed for good (key, quota, missing model, or no
  /// error code). The audio is deleted and not kept.
  discarded,

  /// Keeping the audio failed. The audio and the journal entry stay for a
  /// retry.
  failed,
}

/// Result of transcribing one recovered WAV. [errorCode] is the engine's code
/// of a failure (see [isRepeatableTranscriptionError]); null when the audio
/// could not be imported for another reason.
class RecoveryTranscription {
  const RecoveryTranscription.ok() : succeeded = true, errorCode = null;

  const RecoveryTranscription.failed({this.errorCode}) : succeeded = false;

  final bool succeeded;
  final String? errorCode;
}

/// Keeps [wavPath] in the retry queue. [expiresAt] is when it is deleted.
typedef RecoveryPark =
    Future<void> Function({
      required String wavPath,
      required String errorCode,
      required DateTime capturedAt,
      required Duration audioDuration,
      required DateTime expiresAt,
    });

final recordingRecoveryProvider = Provider<RecordingRecovery>(
  (ref) => RecordingRecovery(
    audioDir: retainedAudioDir(),
    captureDir: currentCaptureDir,
    retainAudio: () =>
        ref.read(settingsProvider).value?.privacy.retainRecentAudio ?? false,
    parkWindow: () =>
        ref.read(settingsProvider).value?.privacy.failedAudioKeepDuration ??
        kDefaultParkWindow,
    entryExists: (id) async =>
        (await ref.read(historyDatabaseProvider).getEntry(id)) != null,
    park:
        ({
          required wavPath,
          required errorCode,
          required capturedAt,
          required audioDuration,
          required expiresAt,
        }) => ref
            .read(pendingAudioQueueProvider)
            .parkForRetry(
              wavPath,
              entryId: newRecordingEntryId(capturedAt),
              capturedAt: capturedAt,
              audioDuration: audioDuration,
              errorCode: errorCode,
              expiresAt: expiresAt,
            ),
    transcribe: (wavPath) async {
      final notifier = ref.read(audioImportQueueProvider.notifier);
      // The slices a crashed run finished are kept in the manifest beside the
      // WAV, so only the rest is sent.
      final result = await notifier.addFiles([
        wavPath,
      ], sliceManifestPath: SliceManifest.beside(wavPath).path);
      // Only the jobs this call created count; another import with the same
      // file name must not make this recording look recovered.
      final ownIds = result.jobIds.toSet();
      final own = ref
          .read(audioImportQueueProvider)
          .where((j) => ownIds.contains(j.id))
          .toList();
      if (own.isNotEmpty && own.every((j) => j.status == ImportStatus.done)) {
        return const RecoveryTranscription.ok();
      }
      return RecoveryTranscription.failed(
        errorCode: own.isEmpty ? null : own.first.transcriptionErrorCode,
      );
    },
  ),
);

/// Recovers every interrupted recording once, at startup. Never throws.
Future<void> recoverInterruptedRecordings(ProviderContainer container) async {
  try {
    final scan = await container.read(interruptedRecordingsProvider.future);
    final recovery = container.read(recordingRecoveryProvider);
    final journal = container.read(recordingJournalProvider);
    for (final recording in scan.recordings) {
      // A journal that a live recording or transcription owns is not
      // interrupted. The journal file also vanishes when its recording ended
      // after the scan; its audio then belongs to the live pipeline.
      if (journal.isLive(recording.id) ||
          !await File(recording.journalPath).exists()) {
        _log.info('Interrupted recording ${recording.id}: owned by a live run');
        continue;
      }
      // One failing recording must not stop the others from being recovered.
      try {
        final outcome = await recovery.recover(recording);
        _log.info('Interrupted recording ${recording.id}: ${outcome.name}');
        final notice = pendingNoticeForRecovery(outcome);
        if (notice != null) {
          container.read(pendingAudioNoticeProvider.notifier).report(notice);
        }
      } on Object catch (e) {
        _log.error('Recovering interrupted recording ${recording.id}: $e');
      }
    }
  } on Object catch (e) {
    _log.error('Recovering interrupted recordings failed: $e');
  } finally {
    container.invalidate(interruptedRecordingsProvider);
  }
}

class RecordingRecovery {
  RecordingRecovery({
    required this.audioDir,
    required this.transcribe,
    this.captureDir,
    this.park,
    this.retainAudio,
    this.parkWindow,
    this.entryExists,
  });

  /// The retained-audio folder. Recovery may import or delete WAV files here.
  final String audioDir;

  /// The private capture folder. A recording made without retention writes
  /// its WAV here, so recovery may use it too. Null when there is none.
  final Future<String> Function()? captureDir;

  /// Imports and transcribes one WAV.
  final Future<RecoveryTranscription> Function(String wavPath) transcribe;

  /// Keeps a WAV for a retry after a repeatable failure. Null: such audio is
  /// kept as [RecoveryOutcome.failed] instead.
  final RecoveryPark? park;

  /// Whether retained audio is on; it sets how long a parked WAV is kept.
  final bool Function()? retainAudio;

  /// Park window without retained audio (Settings → Privacy).
  final Duration Function()? parkWindow;

  /// Whether history already has the entry with this id. A recording whose
  /// entry exists was saved before the interruption: only its audio and
  /// journal entry are removed, nothing is transcribed again.
  final Future<bool> Function(String entryId)? entryExists;

  /// Transcribes the audio of [recording] and removes its journal entry.
  Future<RecoveryOutcome> recover(InterruptedRecording recording) async {
    final entryId = recording.entryId;
    final exists = entryExists;
    if (entryId != null && exists != null && await exists(entryId)) {
      // The audio of a saved recording with retention on belongs to its
      // history entry and stays. Only a private capture WAV is removed here.
      final wav = recording.wavPath;
      final capture = captureDir;
      if (wav != null &&
          capture != null &&
          isContainedAudioPath(wav, await capture())) {
        await _removeAudio(wav);
      }
      await _removeJournal(recording);
      return RecoveryOutcome.recovered;
    }
    final wav = await _ownAudio(recording);
    if (wav == null || !await _hasAudio(wav)) {
      // A file too short to hold audio is removed with its journal entry.
      if (wav != null) await _removeAudio(wav);
      await _removeJournal(recording);
      return RecoveryOutcome.noAudio;
    }
    final result = await _transcribeSafely(wav);
    if (result.succeeded) {
      await _removeAudio(wav);
      await _removeJournal(recording);
      return RecoveryOutcome.recovered;
    }
    // A failure without an engine code (copy, decode, history save) is kept
    // for a retry: the dictation must not be lost silently.
    final code = result.errorCode ?? kSaveFailedErrorCode;
    final maxAge = pendingAudioMaxAge(
      retainAudio: retainAudio?.call() ?? false,
      parkWindow: parkWindow?.call() ?? kDefaultParkWindow,
    );
    final expiresAt = recording.startedAt.add(maxAge);
    // Past its retry window the audio is not kept: a recording that keeps
    // failing would otherwise hold its WAV on disk for every later start.
    if (!isRepeatableTranscriptionError(code) ||
        !expiresAt.isAfter(DateTime.now())) {
      await _removeAudio(wav);
      await _removeJournal(recording);
      return RecoveryOutcome.discarded;
    }
    final park = this.park;
    if (park == null) return RecoveryOutcome.failed;
    try {
      await park(
        wavPath: wav,
        errorCode: code,
        capturedAt: recording.startedAt,
        audioDuration: Duration(
          milliseconds: (((await File(wav).length()) - 44) / 32).round(),
        ),
        expiresAt: expiresAt,
      );
    } on Object catch (e) {
      _log.error('Could not keep interrupted audio for a retry: $e');
      return RecoveryOutcome.failed;
    }
    await _removeJournal(recording);
    return RecoveryOutcome.parked;
  }

  /// Runs [transcribe]; an exception counts as a failure without an engine
  /// code, so the audio is kept for a retry instead of leaving the journal
  /// entry behind to fail again at every start.
  Future<RecoveryTranscription> _transcribeSafely(String wavPath) async {
    try {
      return await transcribe(wavPath);
    } on Object catch (e) {
      _log.error('Transcribing interrupted audio failed: $e');
      return const RecoveryTranscription.failed();
    }
  }

  /// Removes the journal entry and any audio of [recording] without importing.
  Future<void> discard(InterruptedRecording recording) async {
    final wav = await _ownAudio(recording);
    if (wav != null) await _removeAudio(wav);
    await _removeJournal(recording);
  }

  /// The journal's WAV path, but only when it lies inside an audio folder.
  /// A path outside them is treated as no audio and is never touched.
  Future<String?> _ownAudio(InterruptedRecording recording) async {
    final wav = recording.wavPath;
    if (wav == null) return null;
    if (isContainedAudioPath(wav, audioDir)) return wav;
    final capture = captureDir;
    if (capture != null && isContainedAudioPath(wav, await capture())) {
      return wav;
    }
    return null;
  }

  Future<bool> _hasAudio(String wavPath) async {
    final file = File(wavPath);
    if (!await file.exists()) return false;
    return await file.length() >= _minWavBytes;
  }

  /// Removes the WAV and its slice manifest, which holds transcript text, so
  /// the manifest goes first.
  Future<void> _removeAudio(String wavPath) async {
    await SliceManifest.beside(wavPath).delete();
    final file = File(wavPath);
    if (await file.exists()) await file.delete();
  }

  Future<void> _removeJournal(InterruptedRecording recording) async {
    final file = File(recording.journalPath);
    if (await file.exists()) await file.delete();
  }
}
