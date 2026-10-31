/// Queue robustness (WP-43a I-M-1, I-M-4, I-M-3-adjacent): non-`Exception`
/// errors from a step fail only that job, and a failed job does not keep the
/// container copy of the audio when audio retention is off.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/audio_file_decoder.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';

Uint8List _toneWav() => encodePcm16MonoWav(Int16List(4000));

void main() {
  late Directory tmp;
  late String workDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp43a-queue-');
    workDir = '${tmp.path}/work';
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  File writeSource(String name) =>
      File('${tmp.path}/$name')..writeAsBytesSync(_toneWav());

  AudioImportQueue buildQueue({
    required bool keepAudio,
    required ImportDecodeStep decode,
  }) {
    return AudioImportQueue(
      workDir: workDir,
      keepAudio: () => keepAudio,
      decode: decode,
      transcribe: (_, {onProgress, sliceManifestPath}) async => 'hallo',
      save:
          ({
            required fileName,
            required transcript,
            required durationSec,
            required audioPath,
          }) async => 'entry',
    );
  }

  test(
    'an Error from decode fails only that job, the next job still runs',
    () async {
      final first = writeSource('a.wav');
      final second = writeSource('b.wav');
      var calls = 0;
      final queue = buildQueue(
        keepAudio: false,
        decode: ({required inputPath, required outputWavPath}) async {
          calls++;
          if (calls == 1) throw StateError('NaN sample');
          await decodeAudioFileToSttWav(
            inputPath: inputPath,
            outputWavPath: outputWavPath,
          );
        },
      );

      await queue.enqueue([first.path, second.path]);

      expect(queue.jobs[0].status, ImportStatus.failed);
      expect(queue.jobs[0].failure, ImportFailure.decodeFailed);
      expect(queue.jobs[1].status, ImportStatus.done);
    },
  );

  test(
    'an out-of-memory style Error during transcription fails the job',
    () async {
      final source = writeSource('oom.wav');
      final queue = AudioImportQueue(
        workDir: workDir,
        keepAudio: () => false,
        decode: ({required inputPath, required outputWavPath}) =>
            decodeAudioFileToSttWav(
              inputPath: inputPath,
              outputWavPath: outputWavPath,
            ),
        transcribe: (_, {onProgress, sliceManifestPath}) async =>
            throw _FakeOom(),
        save:
            ({
              required fileName,
              required transcript,
              required durationSec,
              required audioPath,
            }) async => 'entry',
      );

      await queue.enqueue([source.path]);

      expect(queue.jobs.single.status, ImportStatus.failed);
      expect(queue.jobs.single.failure, ImportFailure.transcriptionFailed);
    },
  );

  test('a file over the import limit is reported as limit exceeded', () async {
    final source = writeSource('long.wav');
    final queue = buildQueue(
      keepAudio: false,
      decode: ({required inputPath, required outputWavPath}) =>
          throw const AudioInputLimitException('too long'),
    );

    await queue.enqueue([source.path]);

    expect(queue.jobs.single.failure, ImportFailure.inputLimitExceeded);
  });

  test(
    'with audio retention off, a failed job leaves no copy of the audio',
    () async {
      final source = writeSource('secret.wav');
      final queue = buildQueue(
        keepAudio: false,
        decode: ({required inputPath, required outputWavPath}) =>
            throw const AudioDecodeFailedException('corrupt'),
      );

      final result = await queue.enqueue([source.path]);

      final jobDir = Directory('$workDir/${result.jobIds.single}');
      final copies = jobDir.existsSync()
          ? jobDir.listSync().whereType<File>().toList()
          : <File>[];
      expect(copies, isEmpty);
      expect(queue.jobs.single.status, ImportStatus.failed);
    },
  );

  test(
    'a work directory that cannot be created fails the job as copy failure',
    () async {
      final source = writeSource('blocked.wav');
      // A regular file where the work directory should be: no subdirectory can
      // be created below it.
      File(workDir)
        ..createSync(recursive: true)
        ..writeAsBytesSync([0]);
      final queue = buildQueue(
        keepAudio: false,
        decode: ({required inputPath, required outputWavPath}) async {},
      );

      await queue.enqueue([source.path]);

      expect(queue.jobs.single.status, ImportStatus.failed);
      expect(queue.jobs.single.failure, ImportFailure.copyFailed);
    },
  );
  test(
    'enqueue refuses an oversize file and creates no job or scratch folder',
    () async {
      final big = writeSource('big.wav');
      final queue = AudioImportQueue(
        workDir: workDir,
        keepAudio: () => false,
        decode: ({required inputPath, required outputWavPath}) async {
          fail('an oversize file must never reach the decoder');
        },
        transcribe: (_, {onProgress, sliceManifestPath}) async => 'hallo',
        save:
            ({
              required fileName,
              required transcript,
              required durationSec,
              required audioPath,
            }) async => 'entry',
        maxInputBytes: 16,
      );
      final result = await queue.enqueue([big.path]);
      expect(result.jobIds, isEmpty);
      expect(result.rejections.single.reason, ImportRejectionReason.tooLarge);
      expect(queue.jobs, isEmpty);
      expect(Directory(workDir).existsSync(), isFalse);
    },
  );

  test('enqueue refuses a symlink to a FIFO without opening it', () async {
    final fifo = '${tmp.path}/pipe.wav';
    expect(Process.runSync('mkfifo', [fifo]).exitCode, 0);
    final link = '${tmp.path}/link.wav';
    Link(link).createSync(fifo);
    final queue = buildQueue(
      keepAudio: false,
      decode: ({required inputPath, required outputWavPath}) async {
        fail('a FIFO must never reach the decoder');
      },
    );
    final result = await queue.enqueue([link]);
    expect(result.jobIds, isEmpty);
    expect(
      result.rejections.single.reason,
      ImportRejectionReason.notRegularFile,
    );
  }, skip: Platform.isWindows ? 'POSIX file types only' : null);

  test(
    'an I/O error from the decoder fails with ioError and removes the partial WAV',
    () async {
      final source = writeSource('io.wav');
      final queue = AudioImportQueue(
        workDir: workDir,
        keepAudio: () =>
            true, // keeps the job folder, so the leftover is visible
        decode: ({required inputPath, required outputWavPath}) async {
          await File(outputWavPath).writeAsBytes(const [1, 2, 3]);
          throw const AudioDecoderIoException('disk full');
        },
        transcribe: (_, {onProgress, sliceManifestPath}) async => 'hallo',
        save:
            ({
              required fileName,
              required transcript,
              required durationSec,
              required audioPath,
            }) async => 'entry',
      );
      final result = await queue.enqueue([source.path]);
      final id = result.jobIds.single;
      final job = queue.jobs.singleWhere((j) => j.id == id);
      expect(job.status, ImportStatus.failed);
      expect(job.failure, ImportFailure.ioError);
      expect(File('$workDir/$id/audio.wav').existsSync(), isFalse);
    },
  );

  AudioImportQueue copyQueue({
    required bool keepAudio,
    Stream<List<int>> Function(String path)? openSource,
    Duration? stallTimeout,
  }) {
    return AudioImportQueue(
      workDir: workDir,
      keepAudio: () => keepAudio,
      decode: ({required inputPath, required outputWavPath}) async {
        throw StateError('decode must not run after a failed copy');
      },
      transcribe: (_, {onProgress, sliceManifestPath}) async => 'hallo',
      save:
          ({
            required fileName,
            required transcript,
            required durationSec,
            required audioPath,
          }) async => 'entry',
      openSource: openSource,
      stallTimeout: stallTimeout ?? const Duration(seconds: 60),
    );
  }

  /// No file may be left in the job folder after a failed copy.
  void expectNoLeftover(String jobId) {
    final dir = Directory('$workDir/$jobId');
    final leftovers = dir.existsSync()
        ? dir.listSync().whereType<File>().toList()
        : <File>[];
    expect(leftovers, isEmpty, reason: 'partial copy must be deleted');
  }

  test(
    'a source that stalls mid-copy fails the job with copyInterrupted',
    () async {
      final source = writeSource('stall.wav');
      final queue = copyQueue(
        keepAudio: true,
        stallTimeout: const Duration(milliseconds: 50),
        openSource: (path) async* {
          yield const [1, 2, 3];
          await Future<void>.delayed(const Duration(milliseconds: 500));
          yield const [4, 5, 6];
        },
      );

      await queue.enqueue([source.path]);

      final job = queue.jobs.single;
      expect(job.status, ImportStatus.failed);
      expect(job.failure, ImportFailure.copyInterrupted);
      expectNoLeftover(job.id);
    },
  );

  test(
    'a source that changes size during the copy aborts it with copyInterrupted',
    () async {
      final source = writeSource('grow.wav');
      final queue = copyQueue(
        keepAudio: true,
        openSource: (path) async* {
          yield const [1, 2, 3];
          // The file is replaced by a larger one while the copy is running.
          File(path).writeAsBytesSync(List<int>.filled(4096, 7));
          yield const [4, 5, 6];
        },
      );

      await queue.enqueue([source.path]);

      final job = queue.jobs.single;
      expect(job.status, ImportStatus.failed);
      expect(job.failure, ImportFailure.copyInterrupted);
      expectNoLeftover(job.id);
    },
  );

  test(
    'the cleanup log line holds the error type and code, never the path',
    () {
      const error = FileSystemException(
        'cannot delete',
        '/Users/someone/private/audio.wav',
        OSError('Permission denied', 13),
      );
      final line = describeImportError(error);
      expect(line, contains('13'));
      expect(line, isNot(contains('/Users')));
      expect(line, isNot(contains('audio.wav')));
      expect(describeImportError(StateError('x')), 'StateError');
    },
  );
}

class _FakeOom extends Error {}
