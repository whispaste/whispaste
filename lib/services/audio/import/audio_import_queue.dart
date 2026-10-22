/// Sequential queue that imports audio files: copy into the app container,
/// decode to 16 kHz mono WAV, transcribe, and save a history entry.
///
/// Each job runs one step at a time. Progress is reported for the copy step
/// (by bytes) and, when the engine reports it, for transcription; decoding is
/// indeterminate. Transcription also records when it started, so the UI can
/// show elapsed time. Cancel and retry are per job. Folders and missing files are rejected at enqueue time with a
/// message, and a failed job keeps its [ImportFailure] so the UI can say why.
///
/// The queue does not know about Riverpod or the database; the caller passes
/// the decode, transcribe and save steps in. See `audio_import_providers.dart`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'audio_drop_intake.dart';
import 'audio_file_decoder.dart';
import 'pcm_decoder.dart';
import '../user_audio_dirs.dart';

enum ImportStatus {
  queued,
  copying,
  decoding,
  transcribing,
  done,
  failed,
  cancelled,
}

/// Why a job failed. Mapped to a localized message in the UI.
enum ImportFailure {
  copyFailed,
  unsupportedFormat,
  decoderUnavailable,
  decodeFailed,
  inputLimitExceeded,
  transcriptionFailed,
  saveFailed,
  // The disk is full or not writable. Shown with its own message.
  ioError,
  // The source stalled, or it changed while it was copied. Shown with its own
  // message; a slow large file is not an error by itself.
  copyInterrupted,
}

/// Thrown when the source no longer matches its first check during the copy.
class _SourceChangedException implements Exception {
  const _SourceChangedException();
}

class ImportJob {
  const ImportJob({
    required this.id,
    required this.fileName,
    this.status = ImportStatus.queued,
    this.progress,
    this.transcribingSince,
    this.failure,
    this.entryId,
  });

  final String id;
  final String fileName;
  final ImportStatus status;

  /// Progress in `0..1` of the copy, or of the transcription when the engine
  /// reports it. Null while the step is indeterminate.
  final double? progress;

  /// When the transcription step started; null outside `transcribing`.
  final DateTime? transcribingSince;
  final ImportFailure? failure;

  /// History entry created for a finished job.
  final String? entryId;

  bool get isFinished =>
      status == ImportStatus.done ||
      status == ImportStatus.failed ||
      status == ImportStatus.cancelled;

  ImportJob copyWith({
    ImportStatus? status,
    double? progress,
    bool clearProgress = false,
    DateTime? transcribingSince,
    bool clearTranscribingSince = false,
    ImportFailure? failure,
    bool clearFailure = false,
    String? entryId,
  }) => ImportJob(
    id: id,
    fileName: fileName,
    status: status ?? this.status,
    progress: clearProgress ? null : (progress ?? this.progress),
    transcribingSince: clearTranscribingSince
        ? null
        : (transcribingSince ?? this.transcribingSince),
    failure: clearFailure ? null : (failure ?? this.failure),
    entryId: entryId ?? this.entryId,
  );
}

/// What one [AudioImportQueue.enqueue] call did with its paths.
class ImportEnqueueResult {
  const ImportEnqueueResult({required this.rejections, required this.jobIds});

  final List<ImportRejection> rejections;

  /// Ids of the jobs this call added, in the order of the accepted paths.
  final List<String> jobIds;
}

/// A file the queue refused at enqueue time.
class ImportRejection {
  const ImportRejection({required this.path, required this.reason});

  final String path;
  final ImportRejectionReason reason;
}

enum ImportRejectionReason {
  folder,
  notFound,

  /// A dropped file whose extension the import cannot read. The file dialog
  /// filters these out; a drop from the file manager does not.
  unsupportedType,
  notRegularFile,
  reservedName,
  tooLarge,
}

typedef ImportDecodeStep =
    Future<void> Function({
      required String inputPath,
      required String outputWavPath,
    });

/// Transcribes the WAV bytes. [onProgress] receives fractions in `0..1` while
/// the engine works; an engine that cannot report progress never calls it.
typedef ImportTranscribeStep =
    Future<String> Function(
      Uint8List wavBytes, {
      void Function(double fraction)? onProgress,
    });

/// Shortest gap between two transcription progress updates (about 4 per
/// second); a faster engine is throttled so the UI does not rebuild per tick.
const kTranscribeProgressInterval = Duration(milliseconds: 250);

/// Saves the finished import and returns the new history entry id. Receives
/// [audioPath] only when audio retention is on; otherwise null.
typedef ImportSaveStep =
    Future<String> Function({
      required String fileName,
      required String transcript,
      required double durationSec,
      required String? audioPath,
    });

/// A log-safe description of [error]: its type and, for file-system errors,
/// the OS error code. The message text is left out on purpose, because
/// `FileSystemException` messages contain the file path.
String describeImportError(Object error) {
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    return 'FileSystemException (os error ${code ?? 'unknown'})';
  }
  return error.runtimeType.toString();
}

/// Longest wait for the next chunk of a source before the copy fails.
const kCopyStallTimeout = Duration(seconds: 60);

class AudioImportQueue {
  AudioImportQueue({
    required this.workDir,
    required this.keepAudio,
    required this.decode,
    required this.transcribe,
    required this.save,
    this.onChanged,
    this.onCleanupError,
    this.maxInputBytes = kMaxImportFileBytes,
    this.openSource,
    this.stallTimeout = kCopyStallTimeout,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Opens a source for the copy. Tests substitute a fake stream here.
  final Stream<List<int>> Function(String path)? openSource;

  /// Longest wait for the next chunk before the copy is failed. The only time
  /// limit on a copy: a slow but steady read of a large file is allowed.
  final Duration stallTimeout;

  /// Largest source file accepted. Checked by stat before any copy, and again
  /// while copying, so a file that grows after it was queued is still stopped.
  final int maxInputBytes;

  /// Scratch directory inside the app container; one subdirectory per job.
  final String workDir;

  /// Read at each job start. Imported audio is kept only when the user has
  /// opted into audio retention.
  final bool Function() keepAudio;

  final ImportDecodeStep decode;
  final ImportTranscribeStep transcribe;
  final ImportSaveStep save;

  /// Called after every change to [jobs], for the UI to rebuild.
  final void Function(List<ImportJob> jobs)? onChanged;

  /// Receives scratch-folder removal failures. They never fail a job.
  final void Function(Object error)? onCleanupError;

  final List<ImportJob> _jobs = [];
  // Resolved source paths: a symbolic link is followed once, at enqueue time.
  final Map<String, String> _sourcePaths = {};
  final Set<String> _cancelRequested = {};
  Future<void>? _pump;
  var _nextId = 0;

  List<ImportJob> get jobs => List.unmodifiable(_jobs);

  /// Adds [paths] to the queue. Folders and missing files are returned as
  /// rejections and never become jobs. The returned future completes when the
  /// queue has finished the jobs added by this call, and carries their ids.
  Future<ImportEnqueueResult> enqueue(List<String> paths) async {
    final rejections = <ImportRejection>[];
    final jobIds = <String>[];
    for (final path in paths) {
      final source = await inspectImportSource(path);
      final reason = switch (source.kind) {
        ImportSourceKind.directory => ImportRejectionReason.folder,
        ImportSourceKind.notFound => ImportRejectionReason.notFound,
        ImportSourceKind.notRegularFile => ImportRejectionReason.notRegularFile,
        ImportSourceKind.reservedName => ImportRejectionReason.reservedName,
        ImportSourceKind.regularFile when source.size > maxInputBytes =>
          ImportRejectionReason.tooLarge,
        ImportSourceKind.regularFile => null,
      };
      if (reason != null) {
        rejections.add(ImportRejection(path: path, reason: reason));
        continue;
      }
      final id = 'imp-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
      _sourcePaths[id] = source.resolvedPath;
      _jobs.add(ImportJob(id: id, fileName: p.basename(path)));
      jobIds.add(id);
    }
    _notify();
    await _runPending();
    return ImportEnqueueResult(rejections: rejections, jobIds: jobIds);
  }

  /// Deletes scratch files left by an earlier run. The queue is in memory
  /// only, so anything in [workDir] at startup belongs to no live job.
  Future<void> clearScratch() async {
    final dir = Directory(workDir);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Cancels a queued or running job. A running job stops at its next step
  /// boundary (or mid-copy), and its scratch files are removed.
  void cancel(String id) {
    final index = _indexOf(id);
    if (index < 0) return;
    final job = _jobs[index];
    if (job.isFinished) return;
    if (job.status == ImportStatus.queued) {
      // The original path stays so that retry can copy it again.
      _jobs[index] = job.copyWith(status: ImportStatus.cancelled);
      _notify();
    } else {
      _cancelRequested.add(id);
    }
  }

  /// Requeues a failed or cancelled job. The original file is read again, so
  /// retry works only while the source is still reachable.
  Future<void> retry(String id) {
    final index = _indexOf(id);
    if (index < 0) return Future.value();
    final job = _jobs[index];
    if (job.status != ImportStatus.failed &&
        job.status != ImportStatus.cancelled) {
      return Future.value();
    }
    _cancelRequested.remove(id);
    _jobs[index] = job.copyWith(
      status: ImportStatus.queued,
      clearFailure: true,
      clearProgress: true,
    );
    _notify();
    return _runPending();
  }

  Future<void> _runPending() {
    return _pump ??= _drain().whenComplete(() => _pump = null);
  }

  Future<void> _drain() async {
    while (true) {
      final index = _jobs.indexWhere((j) => j.status == ImportStatus.queued);
      if (index < 0) return;
      await _runJob(_jobs[index].id);
    }
  }

  Future<void> _runJob(String id) async {
    final dir = Directory(p.join(workDir, id));
    try {
      try {
        // The scratch folder holds copies of the user's audio: mode 0700.
        await userAudioDirs.ensure(workDir);
        await dir.create(recursive: true);
      } on Object {
        _fail(id, ImportFailure.copyFailed);
        return;
      }
      // Cancelled while the directory was being created.
      if (_statusOf(id) == ImportStatus.cancelled) return;
      final copied = p.join(dir.path, 'source${p.extension(_fileNameOf(id))}');
      if (!File(copied).existsSync()) {
        final sourcePath = _sourcePaths[id];
        if (sourcePath == null) {
          _fail(id, ImportFailure.copyFailed);
          return;
        }
        _set(id, status: ImportStatus.copying, progress: 0);
        if (!await _copyWithProgress(id, sourcePath, copied)) return;
      }

      _set(id, status: ImportStatus.decoding, clearProgress: true);
      final wavPath = p.join(dir.path, 'audio.wav');
      final decodeFailure = await _decodeStep(copied, wavPath);
      if (decodeFailure != null) {
        // A failed decode may leave a partial WAV behind; it is never kept.
        await _deleteIfExists(wavPath);
        _fail(id, decodeFailure);
        return;
      }
      if (_isCancelled(id)) {
        _cancelNow(id);
        return;
      }

      _set(
        id,
        status: ImportStatus.transcribing,
        clearProgress: true,
        transcribingSince: _clock(),
      );
      final String transcript;
      final double durationSec;
      try {
        final wavBytes = await File(wavPath).readAsBytes();
        durationSec = (wavBytes.length - 44) / 32000;
        transcript = await transcribe(
          wavBytes,
          onProgress: _transcribeProgressReporter(id),
        );
      } on Object {
        _fail(id, ImportFailure.transcriptionFailed);
        return;
      }
      if (_isCancelled(id)) {
        _cancelNow(id);
        return;
      }

      final String entryId;
      try {
        entryId = await save(
          fileName: _fileNameOf(id),
          transcript: transcript,
          durationSec: durationSec,
          audioPath: keepAudio() ? wavPath : null,
        );
      } on Object {
        _fail(id, ImportFailure.saveFailed);
        return;
      }
      _set(
        id,
        status: ImportStatus.done,
        entryId: entryId,
        clearProgress: true,
        clearTranscribingSince: true,
      );
    } finally {
      _cancelRequested.remove(id);
      final status = _statusOf(id);
      if (status == ImportStatus.done) _sourcePaths.remove(id);
      // A failed job keeps its container copy for retry, but only while audio
      // retention is on. Otherwise the audio is removed even on failure.
      // Done and cancelled jobs drop their copy; the original path is kept so
      // that a cancelled job can still be retried.
      final keepCopy = status == ImportStatus.failed && keepAudio();
      if (!keepCopy) {
        try {
          if (await dir.exists()) await dir.delete(recursive: true);
        } on FileSystemException catch (error) {
          // Best effort: a leftover folder is removed by clearScratch at the
          // next start.
          onCleanupError?.call(error);
        }
      }
    }
  }

  /// Builds the progress sink for one transcription. Updates are dropped
  /// unless the job is still transcribing, so a late report from the engine
  /// cannot change a finished job. Non-finite values are ignored, others are
  /// clamped to `0..1`, and updates come at most once per
  /// [kTranscribeProgressInterval].
  void Function(double fraction) _transcribeProgressReporter(String id) {
    DateTime? lastReportAt;
    var highest = 0.0;
    return (fraction) {
      if (!fraction.isFinite) return;
      if (_statusOf(id) != ImportStatus.transcribing) return;
      final clamped = fraction.clamp(0.0, 1.0).toDouble();
      // Never move the bar backwards, even if the engine restarts a decode
      // (for example a retry on another backend) and reports from zero again.
      if (clamped <= highest) return;
      final now = _clock();
      final last = lastReportAt;
      if (last != null && now.difference(last) < kTranscribeProgressInterval) {
        return;
      }
      lastReportAt = now;
      highest = clamped;
      _set(id, progress: clamped);
    };
  }

  /// Runs the decode step. Returns null on success, otherwise the failure to
  /// show. Any error, including Error subtypes, fails only this job.
  Future<ImportFailure?> _decodeStep(String inputPath, String wavPath) async {
    try {
      await decode(inputPath: inputPath, outputWavPath: wavPath);
      return null;
    } on AudioFormatUnsupportedException {
      return ImportFailure.unsupportedFormat;
    } on AudioDecoderUnavailableException {
      return ImportFailure.decoderUnavailable;
    } on AudioInputLimitException {
      return ImportFailure.inputLimitExceeded;
    } on AudioDecoderIoException {
      return ImportFailure.ioError;
    } on Object {
      return ImportFailure.decodeFailed;
    }
  }

  ImportStatus? _statusOf(String id) {
    final index = _indexOf(id);
    return index < 0 ? null : _jobs[index].status;
  }

  String _fileNameOf(String id) => _jobs[_indexOf(id)].fileName;

  /// Copies [source] to [target] in chunks, reporting progress. Returns false
  /// (and marks the job failed or cancelled) when the copy did not finish.
  /// A partial target is removed so a retry never mistakes it for a copy.
  Future<bool> _copyWithProgress(
    String id,
    String source,
    String target,
  ) async {
    // Re-inspect: the file may have been replaced since it was queued.
    final check = await inspectImportSource(source);
    if (check.kind != ImportSourceKind.regularFile) {
      _fail(id, ImportFailure.copyFailed);
      return false;
    }
    if (check.size > maxInputBytes) {
      _fail(id, ImportFailure.inputLimitExceeded);
      return false;
    }
    final Stream<List<int>> Function(String) open =
        openSource ?? (path) => File(path).openRead();
    var copied = 0;
    var tooLarge = false;
    try {
      final total = check.size;
      final sink = File(target).openWrite();
      try {
        // A stalled read (for example a FIFO swapped in after the check) fails
        // the job after kCopyStallTimeout instead of hanging it.
        await for (final chunk in open(
          check.resolvedPath,
        ).timeout(stallTimeout)) {
          if (_isCancelled(id)) {
            await sink.close();
            await _deleteIfExists(target);
            _cancelNow(id);
            return false;
          }
          // Stat the path again for every chunk and compare with the first
          // check: a swapped file, a new type or a size change aborts the copy.
          // This narrows the TOCTOU window only; a local user with write access
          // to the import folder can still race it, which file permissions
          // must prevent.
          final again = await inspectImportSource(check.resolvedPath);
          if (again.kind != ImportSourceKind.regularFile ||
              again.size != check.size) {
            throw const _SourceChangedException();
          }
          copied += chunk.length;
          if (copied > maxInputBytes) {
            // The file grew past the limit after the stat check: stop here.
            tooLarge = true;
            break;
          }
          sink.add(chunk);
          _set(id, progress: total == 0 ? 1 : (copied / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }
      if (tooLarge) {
        await _deleteIfExists(target);
        _fail(id, ImportFailure.inputLimitExceeded);
        return false;
      }
    } on TimeoutException {
      await _deleteIfExists(target);
      _fail(id, ImportFailure.copyInterrupted);
      return false;
    } on _SourceChangedException {
      await _deleteIfExists(target);
      _fail(id, ImportFailure.copyInterrupted);
      return false;
    } on Object {
      await _deleteIfExists(target);
      _fail(id, ImportFailure.copyFailed);
      return false;
    }
    return true;
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  bool _isCancelled(String id) => _cancelRequested.contains(id);

  void _cancelNow(String id) => _finish(id, ImportStatus.cancelled);

  void _fail(String id, ImportFailure failure) {
    final index = _indexOf(id);
    if (index < 0) return;
    _jobs[index] = _jobs[index].copyWith(
      status: ImportStatus.failed,
      failure: failure,
      clearProgress: true,
      clearTranscribingSince: true,
    );
    _notify();
  }

  void _finish(String id, ImportStatus status) {
    final index = _indexOf(id);
    if (index < 0) return;
    _jobs[index] = _jobs[index].copyWith(
      status: status,
      clearProgress: true,
      clearTranscribingSince: true,
    );
    _notify();
  }

  void _set(
    String id, {
    ImportStatus? status,
    double? progress,
    bool clearProgress = false,
    DateTime? transcribingSince,
    bool clearTranscribingSince = false,
    String? entryId,
  }) {
    final index = _indexOf(id);
    if (index < 0) return;
    _jobs[index] = _jobs[index].copyWith(
      status: status,
      progress: progress,
      clearProgress: clearProgress,
      transcribingSince: transcribingSince,
      clearTranscribingSince: clearTranscribingSince,
      entryId: entryId,
    );
    _notify();
  }

  int _indexOf(String id) => _jobs.indexWhere((j) => j.id == id);

  void _notify() => onChanged?.call(jobs);
}
