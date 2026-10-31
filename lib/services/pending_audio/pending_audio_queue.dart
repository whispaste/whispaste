import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/utils/word_count.dart';
import '../audio/retention/audio_retention.dart';
import '../audio/user_audio_dirs.dart';
import '../dictation_text_steps.dart';
import '../recording_store.dart';
import '../text_transforms.dart';
import '../transcription/slice_manifest.dart';
import '../transcription/transcriber_exception.dart';

final _log = AppLogger('PendingAudio');

/// Default for how long the audio of a failed transcription is kept for a retry
/// when audio retention is off (UIA-FLW-01). The user sets the real value in
/// Settings → Privacy (`PrivacySettings.failedAudioKeepDays`).
const Duration kDefaultParkWindow = Duration(days: 7);

/// Shape of an entry ID as [newRecordingEntryId] makes it: milliseconds, a
/// dash and a four-digit suffix. Every path built from an ID is checked
/// against it first, so a tampered ID cannot leave the folder.
final _entryIdPattern = RegExp(r'^\d{13}-\d{4}$');

bool isValidPendingEntryId(String id) => _entryIdPattern.hasMatch(id);

/// Age after which a WAV without a record counts as an orphan.
const Duration orphanGrace = Duration(hours: 1);

/// How long a parked dictation may wait, counted from when it was dictated.
/// With retained audio on, the retained-audio window applies; otherwise
/// [parkWindow]. The one rule for the live path, the recovery, the queue and
/// the Settings date, so a change of the setting applies to parked audio too.
Duration pendingAudioMaxAge({
  required bool retainAudio,
  required Duration parkWindow,
}) => retainAudio ? kRetainedAudioMaxAge : parkWindow;

/// Transcription failures that a later try can fix: the server or the network
/// was down or busy, or the GPU ran out of memory. The audio itself is fine.
/// Not included: an empty recording, a missing or invalid key, a model that is
/// not on disk, or a rejected request. A retry would fail the same way.
const _repeatableTranscriptionErrors = {
  'save_failed',
  'stt_server_failed',
  'stt_cuda_oom',
  'transcription_timeout',
  'stt_server_connection_lost',
  'cloud_network_error',
  'custom_endpoint_unreachable',
  'cloud_timeout',
  'cloud_rate_limited',
  'cloud_server_error',
};

/// Whether a failed transcription with [code] is worth keeping its audio for
/// a retry (see [pendingAudioMaxAge]).
bool isRepeatableTranscriptionError(String code) =>
    _repeatableTranscriptionErrors.contains(code);

/// Result of [PendingAudioQueue.retry].
enum PendingRetryOutcome {
  /// The text was saved to history; audio and record are gone or retained.
  saved,

  /// Transcription or save failed again; audio and record are kept.
  failed,

  /// The transcript was empty (silence); audio and record were deleted.
  empty,

  /// The audio or its record no longer exists.
  missing,

  /// The keep period is over. The audio and record were deleted, as the purge
  /// deletes them; nothing was transcribed.
  expired,
}

/// A kept recording whose transcription failed, as the retry UI lists it.
class PendingRetry {
  const PendingRetry({
    required this.entryId,
    required this.capturedAt,
    required this.errorCode,
    required this.expiresAt,
  });

  final String entryId;
  final DateTime capturedAt;
  final String errorCode;

  /// When the audio is deleted: the stored time [purgeExpired] deletes by, so
  /// the date shown to the user is the one that really applies.
  final DateTime expiresAt;
}

/// Keeps the audio of dictations whose history save failed, so the history
/// entry can be written again on a later start.
///
/// Each parked dictation is two files in [directory]: `<entryId>.wav` (the
/// audio) and `<entryId>.json` (everything [RecordingInput] needs to write
/// the same entry again, plus the retry counter). Both use the entry ID the
/// first save was given, so a retry that finds the entry already in the
/// history removes the files instead of writing a duplicate.
///
/// A retry runs once per start. A recording that keeps failing stops after
/// [maxAttempts] tries and is then only removed by the [maxEntries] cap, which
/// evicts the oldest files. This keeps the retry loop finite.
class PendingAudioQueue {
  PendingAudioQueue({
    required this.directory,
    required this.save,
    required this.entryExists,
    this.retainAudio,
    this.applyReplacements = _noReplacements,
    this.maxEntries = 20,
    this.maxAttempts = 5,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  static Future<String> _noReplacements(String text) async => text;

  /// Folder that holds the parked audio and records.
  final String Function() directory;

  /// The user's dictionary, for a parked raw transcript whose text steps
  /// include the replacements; the same function the live pipeline uses.
  final Future<String> Function(String text) applyReplacements;

  /// Writes an entry to history; the same save as the first attempt.
  final Future<SavedRecording> Function(RecordingInput input) save;

  /// Whether the history already has the entry with this ID.
  final Future<bool> Function(String entryId) entryExists;

  /// Keeps a recovered WAV in retained audio (rotation and link included).
  /// When `null`, or when retention is off, the WAV is deleted after a save.
  final Future<void> Function(String entryId, String wavPath)? retainAudio;

  /// Upper bound for parked dictations; the oldest are evicted beyond it.
  final int maxEntries;

  /// Failed retries after which a parked dictation is no longer retried.
  final int maxAttempts;

  /// Moves [wavPath] into the queue and records [input] next to it.
  ///
  /// Throws when the audio cannot be moved or the record cannot be written.
  /// In that case [wavPath] is back in place when the throw happens, so the
  /// caller's cleanup still applies.
  ///
  /// [rawTextSteps] marks [RecordingInput.transcript] as the raw transcript
  /// of a dictation stopped before its text steps ran; the recovery runs
  /// those steps, as the live pipeline would have. Smart Mode is not among
  /// them: a background recovery never refines the text.
  ///
  /// With [keepAudio] false (the user does not keep audio) only the text is
  /// parked: [wavPath] is deleted and the later save runs from the text alone.
  Future<void> park(
    String wavPath,
    RecordingInput input, {
    DictationTextSteps? rawTextSteps,
    bool keepAudio = true,
  }) async {
    final id = input.entryId;
    if (id == null) {
      throw ArgumentError.value(input, 'input', 'entryId is required');
    }
    final record = _PendingRecord.fromInput(
      input,
      attempts: 0,
      rawTextSteps: rawTextSteps,
      hasAudio: keepAudio,
    );
    if (!keepAudio) {
      await _parkTextOnly(wavPath, id, record);
      _log.warning('Kept the text of entry $id for a later history save');
      return;
    }
    await _parkRecord(wavPath, id, record);
    _log.warning('Kept audio of entry $id for a later history save');
  }

  /// Writes [record] without audio and deletes [wavPath]. The record goes
  /// first: if it cannot be written, the WAV stays for the pipeline's cleanup.
  Future<void> _parkTextOnly(
    String wavPath,
    String id,
    _PendingRecord record,
  ) async {
    if (!isValidPendingEntryId(id)) {
      throw ArgumentError('entryId has an unexpected format');
    }
    final dir = Directory(directory());
    await userAudioDirs.ensure(dir.path);
    await _writeRecord(p.join(dir.path, '$id.json'), record);
    await _deleteIfExists(wavPath);
    await _enforceCap(dir);
  }

  /// Keeps the audio of a dictation whose transcription failed with a
  /// repeatable error, so it can be transcribed again (UIA-FLW-01).
  ///
  /// [expiresAt] is stored for display only (Settings → Privacy and the
  /// history detail). Deletion never reads it: [purgeExpired] and
  /// [sweepExpired] count from [capturedAt] with the current keep period, so
  /// a changed period applies to records parked earlier.
  /// [completedParts] are the texts of the upload slices that finished before
  /// the failure. They are kept beside the audio (see [_writeSliceParts]), so a
  /// retry sends only the remaining slices instead of paying for all of them.
  Future<void> parkForRetry(
    String wavPath, {
    required String entryId,
    required DateTime capturedAt,
    required Duration audioDuration,
    required String errorCode,
    required DateTime expiresAt,
    List<String> completedParts = const [],
  }) async {
    await _parkRecord(
      wavPath,
      entryId,
      _PendingRecord.retry(
        entryId: entryId,
        capturedAt: capturedAt,
        audioDuration: audioDuration,
        errorCode: errorCode,
        expiresAt: expiresAt,
      ),
    );
    // The manifest the upload wrote beside the WAV moves with it. Its texts are
    // already current: each finished slice was saved as it finished.
    final dir = Directory(directory());
    await SliceManifest.beside(
      wavPath,
    ).moveTo(_sliceManifestPath(dir, entryId));
    if (completedParts.isNotEmpty) {
      await _writeSliceParts(dir, entryId, completedParts);
    }
    _log.warning('Kept audio of entry $entryId after a failed transcription');
  }

  /// The manifest of a kept recording, for a retry to save each finished slice
  /// into. [wavLength] is the length of the audio the retry transcribes.
  SliceManifest sliceManifestFor(String entryId) =>
      SliceManifest(_sliceManifestPath(Directory(directory()), entryId));

  /// Moves [wavPath] into the queue as `<id>.wav` and writes [record] as
  /// `<id>.json`. On a failed record write the audio goes back to [wavPath].
  Future<void> _parkRecord(
    String wavPath,
    String id,
    _PendingRecord record,
  ) async {
    if (!isValidPendingEntryId(id)) {
      throw ArgumentError('entryId has an unexpected format');
    }
    final dir = Directory(directory());
    // Creates the folder with mode 0700 (user audio).
    await userAudioDirs.ensure(dir.path);
    final wavDest = p.join(dir.path, '$id.wav');
    await _moveFile(wavPath, wavDest);
    await restrictPrivateFile(wavDest);
    try {
      await _writeRecord(p.join(dir.path, '$id.json'), record);
    } on Object {
      try {
        await _moveFile(wavDest, wavPath);
      } on Object catch (rollbackError) {
        _log.error(
          'Could not move audio back after failed park: $rollbackError',
        );
      }
      rethrow;
    }
    await _enforceCap(dir);
  }

  /// Kept recordings of failed transcriptions, oldest first.
  Future<List<PendingRetry>> retryEntries({
    bool retainAudio = false,
    Duration parkWindow = kDefaultParkWindow,
  }) async {
    final dir = Directory(directory());
    if (!await dir.exists()) return const [];
    final window = pendingAudioMaxAge(
      retainAudio: retainAudio,
      parkWindow: parkWindow,
    );
    final clock = _clock();
    return [
      for (final r in await _records(dir))
        // Past the keep period an entry is not offered for retry; the purge
        // deletes it.
        if (r.retryErrorCode != null && clock.isBefore(r.createdAt.add(window)))
          PendingRetry(
            entryId: r.entryId,
            capturedAt: r.createdAt,
            errorCode: r.retryErrorCode!,
            // Counted from the dictation, like the purge below.
            expiresAt: r.createdAt.add(window),
          ),
    ];
  }

  /// Deletes the kept retries whose time is over, by the same rule as
  /// [retryEntries] and [sweepExpired]. Returns how many went.
  Future<int> purgeExpired({
    bool retainAudio = false,
    Duration parkWindow = kDefaultParkWindow,
    DateTime? now,
  }) async {
    final dir = Directory(directory());
    if (!await dir.exists()) return 0;
    final clock = now ?? _clock();
    final window = pendingAudioMaxAge(
      retainAudio: retainAudio,
      parkWindow: parkWindow,
    );
    var removed = 0;
    for (final record in await _records(dir)) {
      if (record.retryErrorCode == null) continue;
      if (clock.isBefore(record.createdAt.add(window))) continue;
      _log.warning('Deleting unretried audio of entry ${record.entryId}');
      await _removeFiles(dir, record.entryId);
      removed++;
    }
    return removed;
  }

  /// Transcribes a kept recording again with [transcribe] and saves the text
  /// to history with [buildInput]. The audio is then retained or deleted, as
  /// after a normal save. Failures keep audio and record for another try.
  Future<PendingRetryOutcome> retry(
    String entryId, {
    required Future<String> Function(
      List<int> wavBytes,
      List<String> completedParts,
    )
    transcribe,
    required RecordingInput Function(String text, Duration audio) buildInput,
    required bool retainAudio,
    Duration parkWindow = kDefaultParkWindow,
  }) async {
    final dir = Directory(directory());
    _PendingRecord? record;
    for (final candidate in await _records(dir)) {
      if (candidate.entryId == entryId && candidate.retryErrorCode != null) {
        record = candidate;
      }
    }
    if (record == null) return PendingRetryOutcome.missing;
    // The keep period the user set is final: past it the audio is deleted
    // here, as the purge would, and nothing is transcribed or saved.
    final window = pendingAudioMaxAge(
      retainAudio: retainAudio,
      parkWindow: parkWindow,
    );
    if (!_clock().isBefore(record.createdAt.add(window))) {
      _log.info('Kept audio $entryId is past its keep period; deleting it');
      await _removeFiles(dir, entryId);
      return PendingRetryOutcome.expired;
    }
    final wavPath = p.join(dir.path, '$entryId.wav');
    final jsonPath = p.join(dir.path, '$entryId.json');
    if (!await File(wavPath).exists()) {
      await _removeFiles(dir, entryId);
      return PendingRetryOutcome.missing;
    }

    final completed = await _readSliceParts(
      dir,
      entryId,
      await File(wavPath).length(),
    );
    final String text;
    try {
      text = await transcribe(await File(wavPath).readAsBytes(), completed);
    } on Object catch (e) {
      _log.warning('Retry of kept audio $entryId failed: $e');
      if (e is TranscriberException && e.completedParts.isNotEmpty) {
        await _writeSliceParts(dir, entryId, e.completedParts);
      }
      await _writeRecord(jsonPath, record.withAttempts(record.attempts + 1));
      return PendingRetryOutcome.failed;
    }
    if (text.trim().isEmpty) {
      _log.info('Kept audio $entryId has no speech; deleting it');
      await _removeFiles(dir, entryId);
      return PendingRetryOutcome.empty;
    }

    try {
      await save(
        buildInput(text, Duration(milliseconds: record.audioDurationMs)),
      );
    } on Object catch (e) {
      _log.warning('Saving retried audio $entryId failed: $e');
      await _writeRecord(jsonPath, record.withAttempts(record.attempts + 1));
      return PendingRetryOutcome.failed;
    }

    if (retainAudio && this.retainAudio != null) {
      try {
        await this.retainAudio!(entryId, wavPath);
      } on Object catch (e) {
        _log.warning('Could not retain audio of $entryId; deleting it: $e');
        await _deleteIfExists(wavPath);
      }
    } else {
      await _deleteIfExists(wavPath);
    }
    await _deleteIfExists(jsonPath);
    await SliceManifest(_sliceManifestPath(dir, entryId)).delete();
    _log.info('Saved retried dictation $entryId to history');
    return PendingRetryOutcome.saved;
  }

  /// Deletes a kept recording without saving it.
  Future<void> discard(String entryId) async {
    if (!isValidPendingEntryId(entryId)) {
      _log.warning(
        'Ignoring discard for an entry ID with an unexpected format',
      );
      return;
    }
    await _removeFiles(Directory(directory()), entryId);
  }

  /// Retries every parked dictation once. Returns the counts; never throws.
  Future<PendingRecovery> recoverAll({
    required bool retainAudio,
    Duration parkWindow = kDefaultParkWindow,
    DateTime? now,
  }) async {
    try {
      return await _recoverAll(
        retainAudio: retainAudio,
        parkWindow: parkWindow,
        now: now,
      );
    } on Object catch (e) {
      _log.error('Recovering parked audio stopped: ${errorKind(e)}');
      return const PendingRecovery();
    }
  }

  Future<PendingRecovery> _recoverAll({
    required bool retainAudio,
    required Duration parkWindow,
    DateTime? now,
  }) async {
    var saved = 0;
    var failed = 0;
    var skipped = 0;
    final dir = Directory(directory());
    if (!await dir.exists()) return const PendingRecovery();
    // Kept retries past their time are deleted here, so an app that was
    // closed for longer than 24 h does not keep the audio around.
    await purgeExpired(
      retainAudio: retainAudio,
      parkWindow: parkWindow,
      now: now,
    );
    await sweepExpired(
      retainAudio: retainAudio,
      parkWindow: parkWindow,
      now: now,
    );
    await _removeOrphans(dir, now ?? _clock());

    for (final record in await _records(dir)) {
      final id = record.entryId;
      final wavPath = p.join(dir.path, '$id.wav');
      // Retries have no transcript yet; they wait for the user's choice.
      if (record.retryErrorCode != null) continue;
      try {
        if (record.attempts >= maxAttempts) {
          skipped++;
          continue;
        }
        if (await entryExists(id)) {
          // The entry was written after all (a save that outlived its
          // timeout). The audio belongs to that entry: it goes to retention
          // when retention is on, otherwise the files are stale.
          // A late save with retention on may have moved the WAV already.
          if (retainAudio &&
              this.retainAudio != null &&
              await File(wavPath).exists()) {
            await this.retainAudio!(id, wavPath);
          }
          await _removeFiles(dir, id);
          continue;
        }
        if (record.hasAudio && !await File(wavPath).exists()) {
          _log.error('Audio of entry $id is missing; dropping its record');
          await _removeFiles(dir, id);
          skipped++;
          continue;
        }
        await save(await record.toInput(applyReplacements));
        // A record parked without audio has no WAV to keep or delete.
        if (record.hasAudio) {
          if (retainAudio && this.retainAudio != null) {
            await this.retainAudio!(id, wavPath);
          } else {
            await _deleteIfExists(wavPath);
          }
        }
        await _deleteIfExists(p.join(dir.path, '$id.json'));
        saved++;
        _log.info('Saved parked dictation $id to history');
      } on Object catch (e) {
        failed++;
        _log.warning('Retry of parked dictation $id failed: ${errorKind(e)}');
        try {
          await _writeRecord(
            p.join(dir.path, '$id.json'),
            record.withAttempts(record.attempts + 1),
          );
        } on Object catch (writeError) {
          _log.error(
            'Could not record a failed retry of $id: ${errorKind(writeError)}',
          );
        }
      }
    }
    return PendingRecovery(saved: saved, failed: failed, skipped: skipped);
  }

  /// Removes parked dictations older than [pendingAudioMaxAge]. Returns the
  /// number removed. Never throws.
  Future<int> sweepExpired({
    required bool retainAudio,
    Duration parkWindow = kDefaultParkWindow,
    DateTime? now,
  }) async {
    final dir = Directory(directory());
    if (!await dir.exists()) return 0;
    final cutoff = (now ?? _clock()).subtract(
      pendingAudioMaxAge(retainAudio: retainAudio, parkWindow: parkWindow),
    );
    var removed = 0;
    try {
      for (final record in await _records(dir)) {
        if (!record.createdAt.isBefore(cutoff)) continue;
        await _removeFiles(dir, record.entryId);
        removed++;
        _log.info('Dropped parked dictation ${record.entryId}: too old');
      }
    } on Object catch (e) {
      _log.warning('Expiry sweep of parked audio failed: ${errorKind(e)}');
    }
    return removed;
  }

  /// Removes leftovers that no record refers to: temp records from an
  /// interrupted write, and WAVs without a record, such as partial copies.
  /// A WAV is only removed after [orphanGrace], because a dictation being
  /// parked right now has its WAV in place before its record exists.
  Future<void> _removeOrphans(Directory dir, DateTime now) async {
    final entries = await dir.list().toList();
    final names = {for (final e in entries) p.basename(e.path)};
    for (final entity in entries) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      try {
        if (name.endsWith('.json.tmp') || name.endsWith('.slices.tmp')) {
          await entity.delete();
        } else if (name.endsWith('.wav')) {
          final recordName = '${p.basenameWithoutExtension(name)}.json';
          final old = now.difference(entity.lastModifiedSync()) > orphanGrace;
          if (!names.contains(recordName) && old) await entity.delete();
        } else if (name.endsWith('.slices') &&
            !names.contains('${p.basenameWithoutExtension(name)}.wav')) {
          // A slice manifest never outlives its audio.
          await entity.delete();
        }
      } on Object catch (e) {
        _log.warning(
          'Could not remove an orphaned pending file: ${errorKind(e)}',
        );
      }
    }
  }

  /// Records of every parseable entry, oldest first. A record that cannot be
  /// read is skipped and kept, so a bad file never blocks the others.
  Future<List<_PendingRecord>> _records(Directory dir) async {
    final records = <_PendingRecord>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString());
        records.add(_PendingRecord.fromJson(json));
      } on Object catch (e) {
        // The error type only: a FormatException can quote part of the file.
        _log.warning('Ignoring unreadable pending record (${e.runtimeType})');
      }
    }
    records.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return records;
  }

  Future<void> _enforceCap(Directory dir) async {
    final records = await _records(dir);
    final excess = records.length - maxEntries;
    for (var i = 0; i < excess; i++) {
      final id = records[i].entryId;
      _log.error('Pending audio cap reached; dropping oldest entry $id');
      await _removeFiles(dir, id);
    }
  }

  Future<void> _removeFiles(Directory dir, String id) async {
    // The manifest holds transcript text: it goes before the audio it belongs to.
    await SliceManifest(_sliceManifestPath(dir, id)).delete();
    await _deleteIfExists(p.join(dir.path, '$id.wav'));
    await _deleteIfExists(p.join(dir.path, '$id.json'));
  }

  static String _sliceManifestPath(Directory dir, String id) =>
      p.join(dir.path, '$id$kSliceManifestExtension');

  /// Writes the finished slice texts of entry [id] to its manifest, tied to
  /// the audio's length so a changed WAV never reuses them. A failed write only
  /// costs the saving: the retry then sends every slice again.
  Future<void> _writeSliceParts(
    Directory dir,
    String id,
    List<String> parts,
  ) async {
    try {
      final wavLength = await File(p.join(dir.path, '$id.wav')).length();
      await SliceManifest(_sliceManifestPath(dir, id)).write(wavLength, parts);
    } on Object catch (e) {
      _log.warning('Could not keep finished slices of $id: ${e.runtimeType}');
    }
  }

  /// The finished slice texts of entry [id], or none when the manifest is
  /// missing, unreadable, or was written for audio of another length.
  Future<List<String>> _readSliceParts(
    Directory dir,
    String id,
    int wavLength,
  ) => SliceManifest(_sliceManifestPath(dir, id)).read(wavLength);

  Future<void> _writeRecord(String path, _PendingRecord record) async {
    final tmp = File('$path.tmp');
    try {
      await tmp.writeAsString(jsonEncode(record.toJson()), flush: true);
      await restrictPrivateFile(tmp.path);
      await tmp.rename(path);
    } on Object {
      await _deleteIfExists(tmp.path);
      rethrow;
    }
  }

  static Future<void> _moveFile(String from, String to) async {
    final source = File(from);
    try {
      await source.rename(to);
    } on FileSystemException {
      // Capture and app-data dirs may sit on different filesystems.
      await source.copy(to);
      await source.delete();
    }
  }

  static Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

/// Outcome of one [PendingAudioQueue.recoverAll] pass.
class PendingRecovery {
  const PendingRecovery({this.saved = 0, this.failed = 0, this.skipped = 0});

  final int saved;
  final int failed;
  final int skipped;
}

/// Metadata of one parked dictation: the [RecordingInput] fields plus the
/// retry counter.
class _PendingRecord {
  const _PendingRecord({
    required this.entryId,
    required this.createdAt,
    required this.transcript,
    required this.audioDurationMs,
    required this.modelId,
    required this.isLocal,
    required this.languageCode,
    required this.historyMaxEntries,
    required this.wordCount,
    required this.processingDurationSec,
    required this.attempts,
    this.originalTranscript,
    this.targetApp,
    this.rawTextSteps,
    this.retryErrorCode,
    this.expiresAt,
    this.hasAudio = true,
  });

  /// A kept audio whose transcription failed (UIA-FLW-01). The history fields
  /// stay empty until the retry produces a transcript.
  factory _PendingRecord.retry({
    required String entryId,
    required DateTime capturedAt,
    required Duration audioDuration,
    required String errorCode,
    required DateTime expiresAt,
  }) => _PendingRecord(
    entryId: entryId,
    createdAt: capturedAt,
    transcript: '',
    audioDurationMs: audioDuration.inMilliseconds,
    modelId: '',
    isLocal: true,
    languageCode: '',
    historyMaxEntries: 0,
    wordCount: 0,
    processingDurationSec: 0,
    attempts: 0,
    retryErrorCode: errorCode,
    expiresAt: expiresAt,
  );

  factory _PendingRecord.fromInput(
    RecordingInput input, {
    required int attempts,
    DictationTextSteps? rawTextSteps,
    bool hasAudio = true,
  }) {
    return _PendingRecord(
      hasAudio: hasAudio,
      entryId: input.entryId!,
      createdAt: input.createdAt ?? DateTime.now(),
      transcript: input.transcript,
      audioDurationMs: input.audioDuration.inMilliseconds,
      modelId: input.modelId,
      isLocal: input.isLocal,
      languageCode: input.languageCode,
      historyMaxEntries: input.historyMaxEntries,
      wordCount: input.wordCount,
      processingDurationSec: input.processingDurationSec,
      originalTranscript: input.originalTranscript,
      targetApp: input.targetApp,
      rawTextSteps: rawTextSteps,
      attempts: attempts,
    );
  }

  factory _PendingRecord.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('pending record is not an object');
    }
    final entryId = json['entryId'] as String;
    if (!isValidPendingEntryId(entryId)) {
      throw const FormatException('entry ID has an unexpected format');
    }
    return _PendingRecord(
      entryId: entryId,
      createdAt: DateTime.parse(json['createdAt'] as String),
      transcript: json['transcript'] as String,
      audioDurationMs: json['audioDurationMs'] as int,
      modelId: json['modelId'] as String,
      isLocal: json['isLocal'] as bool,
      languageCode: json['languageCode'] as String,
      historyMaxEntries: json['historyMaxEntries'] as int,
      wordCount: json['wordCount'] as int,
      processingDurationSec: json['processingDurationSec'] as int,
      rawTextSteps: _rawTextStepsFromJson(json),
      originalTranscript: json['originalTranscript'] as String?,
      targetApp: json['targetApp'] as String?,
      attempts: json['attempts'] as int,
      retryErrorCode: json['retryErrorCode'] as String?,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String),
      hasAudio: json['hasAudio'] != false,
    );
  }

  final String entryId;
  final DateTime createdAt;
  final String transcript;
  final int audioDurationMs;
  final String modelId;
  final bool isLocal;
  final String languageCode;
  final int historyMaxEntries;
  final int wordCount;
  final int processingDurationSec;
  final String? originalTranscript;
  final String? targetApp;

  /// Set when [transcript] is the raw transcript of a dictation stopped
  /// before its text steps ran: the steps its settings enabled.
  final DictationTextSteps? rawTextSteps;
  final int attempts;

  /// Set for a kept audio whose transcription failed; see [PendingRetry].
  final String? retryErrorCode;
  final DateTime? expiresAt;

  /// False when the dictation was parked without audio ("do not keep audio"):
  /// the save then runs from the text alone and there is no WAV to find.
  final bool hasAudio;

  _PendingRecord withAttempts(int value) => _PendingRecord(
    hasAudio: hasAudio,
    entryId: entryId,
    createdAt: createdAt,
    transcript: transcript,
    audioDurationMs: audioDurationMs,
    modelId: modelId,
    isLocal: isLocal,
    languageCode: languageCode,
    historyMaxEntries: historyMaxEntries,
    wordCount: wordCount,
    processingDurationSec: processingDurationSec,
    originalTranscript: originalTranscript,
    targetApp: targetApp,
    rawTextSteps: rawTextSteps,
    attempts: value,
    retryErrorCode: retryErrorCode,
    expiresAt: expiresAt,
  );

  /// Same save as the first attempt: history entry and daily stat written.
  /// A raw transcript first gets the whitespace cleanup and its text steps,
  /// so the entry matches what the live pipeline would have saved (without
  /// Smart Mode), with the cleaned transcript kept as the original.
  Future<RecordingInput> toInput(
    Future<String> Function(String text) applyReplacements,
  ) async {
    var text = transcript;
    var original = originalTranscript;
    var words = wordCount;
    final steps = rawTextSteps;
    if (steps != null) {
      original = collapseTranscriptWhitespace(transcript);
      text = await steps.apply(
        original,
        languageCode: languageCode,
        applyReplacements: applyReplacements,
      );
      words = computeWordCountFast(text);
    }
    return RecordingInput(
      transcript: text,
      audioDuration: Duration(milliseconds: audioDurationMs),
      modelId: modelId,
      isLocal: isLocal,
      languageCode: languageCode,
      applyTextReplacements: false,
      historyMaxEntries: historyMaxEntries,
      wordCount: words,
      processingDurationSec: processingDurationSec,
      originalTranscript: original,
      targetApp: targetApp,
      entryId: entryId,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toJson() => {
    'entryId': entryId,
    'createdAt': createdAt.toIso8601String(),
    'transcript': transcript,
    'audioDurationMs': audioDurationMs,
    'modelId': modelId,
    'isLocal': isLocal,
    'languageCode': languageCode,
    'historyMaxEntries': historyMaxEntries,
    'wordCount': wordCount,
    'processingDurationSec': processingDurationSec,
    'rawTextSteps': rawTextSteps?.toJson(),
    'originalTranscript': originalTranscript,
    'targetApp': targetApp,
    'attempts': attempts,
    'retryErrorCode': retryErrorCode,
    'expiresAt': expiresAt?.toIso8601String(),
    'hasAudio': hasAudio,
  };
}

/// Text steps of a parked raw transcript. Records without them carry a final
/// transcript. A record from a build that stored only a replacements flag
/// gets just the replacements. A corrupted value reads as a final transcript
/// instead of failing the whole record.
DictationTextSteps? _rawTextStepsFromJson(Map<String, Object?> json) {
  final steps = DictationTextSteps.tryParse(json['rawTextSteps']);
  if (steps != null) return steps;
  if (json['applyTextReplacements'] != true) return null;
  return const DictationTextSteps(
    removeFillerWords: false,
    spokenPunctuation: false,
    voiceLineBreaks: false,
    textReplacements: true,
  );
}
