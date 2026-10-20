import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../audio/user_audio_dirs.dart';
import '../recording_store.dart';

final _log = AppLogger('PendingAudio');

/// How long audio of a failed transcription is kept for a retry when
/// "Audio aufbewahren" is off (UIA-FLW-01). With the setting on, the normal
/// retention applies instead.
const Duration kParkedAudioMaxAge = Duration(hours: 24);

/// Transcription failures that a later try can fix: the server or the network
/// was down or busy, or the GPU ran out of memory. The audio itself is fine.
/// Not included: an empty recording, a missing or invalid key, a model that is
/// not on disk, or a rejected request. A retry would fail the same way.
const _repeatableTranscriptionErrors = {
  'stt_server_failed',
  'stt_cuda_oom',
  'transcription_timeout',
  'stt_server_connection_lost',
  'cloud_network_error',
  'cloud_timeout',
};

/// Whether a failed transcription with [code] is worth keeping its audio for
/// a retry (see [kParkedAudioMaxAge]).
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
}

/// A kept recording whose transcription failed, as the retry UI lists it.
class PendingRetry {
  const PendingRetry({
    required this.entryId,
    required this.capturedAt,
    required this.errorCode,
  });

  final String entryId;
  final DateTime capturedAt;
  final String errorCode;
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
    this.maxEntries = 20,
    this.maxAttempts = 5,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Folder that holds the parked audio and records.
  final String Function() directory;

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
  Future<void> park(String wavPath, RecordingInput input) async {
    final id = input.entryId;
    if (id == null) {
      throw ArgumentError.value(input, 'input', 'entryId is required');
    }
    await _parkRecord(
      wavPath,
      id,
      _PendingRecord.fromInput(input, attempts: 0),
    );
    _log.warning('Kept audio of entry $id for a later history save');
  }

  /// Keeps the audio of a dictation whose transcription failed with a
  /// repeatable error, so it can be transcribed again (UIA-FLW-01). The audio
  /// expires at [expiresAt]; see [purgeExpired].
  Future<void> parkForRetry(
    String wavPath, {
    required String entryId,
    required DateTime capturedAt,
    required Duration audioDuration,
    required String errorCode,
    required DateTime expiresAt,
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
    _log.warning('Kept audio of entry $entryId after a failed transcription');
  }

  /// Moves [wavPath] into the queue as `<id>.wav` and writes [record] as
  /// `<id>.json`. On a failed record write the audio goes back to [wavPath].
  Future<void> _parkRecord(
    String wavPath,
    String id,
    _PendingRecord record,
  ) async {
    final dir = Directory(directory());
    // Creates the folder with mode 0700 (user audio).
    await userAudioDirs.ensure(dir.path);
    final wavDest = p.join(dir.path, '$id.wav');
    await _moveFile(wavPath, wavDest);
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
  Future<List<PendingRetry>> retryEntries() async {
    final dir = Directory(directory());
    if (!await dir.exists()) return const [];
    return [
      for (final r in await _records(dir))
        if (r.retryErrorCode != null && r.expiresAt != null)
          PendingRetry(
            entryId: r.entryId,
            capturedAt: r.createdAt,
            errorCode: r.retryErrorCode!,
          ),
    ];
  }

  /// Deletes the kept retries whose time is over. Returns how many went.
  Future<int> purgeExpired() async {
    final dir = Directory(directory());
    if (!await dir.exists()) return 0;
    final now = _clock();
    var removed = 0;
    for (final record in await _records(dir)) {
      final expiresAt = record.expiresAt;
      if (record.retryErrorCode == null || expiresAt == null) continue;
      if (now.isBefore(expiresAt)) continue;
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
    required Future<String> Function(List<int> wavBytes) transcribe,
    required RecordingInput Function(String text, Duration audio) buildInput,
    required bool retainAudio,
  }) async {
    final dir = Directory(directory());
    _PendingRecord? record;
    for (final candidate in await _records(dir)) {
      if (candidate.entryId == entryId && candidate.retryErrorCode != null) {
        record = candidate;
      }
    }
    if (record == null) return PendingRetryOutcome.missing;
    final wavPath = p.join(dir.path, '$entryId.wav');
    final jsonPath = p.join(dir.path, '$entryId.json');
    if (!await File(wavPath).exists()) {
      await _removeFiles(dir, entryId);
      return PendingRetryOutcome.missing;
    }

    final String text;
    try {
      text = await transcribe(await File(wavPath).readAsBytes());
    } on Object catch (e) {
      _log.warning('Retry of kept audio $entryId failed: $e');
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
    _log.info('Saved retried dictation $entryId to history');
    return PendingRetryOutcome.saved;
  }

  /// Deletes a kept recording without saving it.
  Future<void> discard(String entryId) =>
      _removeFiles(Directory(directory()), entryId);

  /// Retries every parked dictation once. Returns the counts; never throws.
  Future<PendingRecovery> recoverAll({required bool retainAudio}) async {
    var saved = 0;
    var failed = 0;
    var skipped = 0;
    final dir = Directory(directory());
    if (!await dir.exists()) return const PendingRecovery();
    // Kept retries past their time are deleted here, so an app that was
    // closed for longer than 24 h does not keep the audio around.
    await purgeExpired();

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
          // The first save did write the entry, so only the files are stale.
          await _removeFiles(dir, id);
          continue;
        }
        if (!await File(wavPath).exists()) {
          _log.error('Audio of entry $id is missing; dropping its record');
          await _removeFiles(dir, id);
          skipped++;
          continue;
        }
        await save(record.toInput());
        if (retainAudio && this.retainAudio != null) {
          await this.retainAudio!(id, wavPath);
        } else {
          await _deleteIfExists(wavPath);
        }
        await _deleteIfExists(p.join(dir.path, '$id.json'));
        saved++;
        _log.info('Saved parked dictation $id to history');
      } on Object catch (e) {
        failed++;
        _log.warning('Retry of parked dictation $id failed: $e');
        await _writeRecord(
          p.join(dir.path, '$id.json'),
          record.withAttempts(record.attempts + 1),
        );
      }
    }
    return PendingRecovery(saved: saved, failed: failed, skipped: skipped);
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
        _log.warning('Ignoring unreadable pending record ${entity.path}: $e');
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
    await _deleteIfExists(p.join(dir.path, '$id.wav'));
    await _deleteIfExists(p.join(dir.path, '$id.json'));
  }

  Future<void> _writeRecord(String path, _PendingRecord record) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsString(jsonEncode(record.toJson()), flush: true);
    await tmp.rename(path);
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
    this.retryErrorCode,
    this.expiresAt,
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
  }) {
    return _PendingRecord(
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
      attempts: attempts,
    );
  }

  factory _PendingRecord.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('pending record is not an object');
    }
    return _PendingRecord(
      entryId: json['entryId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      transcript: json['transcript'] as String,
      audioDurationMs: json['audioDurationMs'] as int,
      modelId: json['modelId'] as String,
      isLocal: json['isLocal'] as bool,
      languageCode: json['languageCode'] as String,
      historyMaxEntries: json['historyMaxEntries'] as int,
      wordCount: json['wordCount'] as int,
      processingDurationSec: json['processingDurationSec'] as int,
      originalTranscript: json['originalTranscript'] as String?,
      targetApp: json['targetApp'] as String?,
      attempts: json['attempts'] as int,
      retryErrorCode: json['retryErrorCode'] as String?,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String),
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
  final int attempts;

  /// Set for a kept audio whose transcription failed; see [PendingRetry].
  final String? retryErrorCode;
  final DateTime? expiresAt;

  _PendingRecord withAttempts(int value) => _PendingRecord(
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
    attempts: value,
    retryErrorCode: retryErrorCode,
    expiresAt: expiresAt,
  );

  /// Same save as the first attempt: no replacements (the transcript is
  /// already final), history entry and daily stat written.
  RecordingInput toInput() => RecordingInput(
    transcript: transcript,
    audioDuration: Duration(milliseconds: audioDurationMs),
    modelId: modelId,
    isLocal: isLocal,
    languageCode: languageCode,
    applyTextReplacements: false,
    historyMaxEntries: historyMaxEntries,
    wordCount: wordCount,
    processingDurationSec: processingDurationSec,
    originalTranscript: originalTranscript,
    targetApp: targetApp,
    entryId: entryId,
    createdAt: createdAt,
  );

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
    'originalTranscript': originalTranscript,
    'targetApp': targetApp,
    'attempts': attempts,
    'retryErrorCode': retryErrorCode,
    'expiresAt': expiresAt?.toIso8601String(),
  };
}
