/// Behaviour of the audio import queue: rejection at enqueue, ordering,
/// failure reasons, cancel, retry, and the audio-retention switch.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/audio_file_decoder.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';

/// 16 kHz mono 16-bit WAV of [seconds] of a 440 Hz tone.
Uint8List _toneWav({double seconds = 0.25}) {
  final frames = (16000 * seconds).round();
  final pcm = Int16List(frames);
  for (var i = 0; i < frames; i++) {
    pcm[i] = (3000 * (i % 36 < 18 ? 1 : -1)).toInt();
  }
  return encodePcm16MonoWav(pcm);
}

void main() {
  late Directory tmp;
  late String workDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wp35-queue-');
    workDir = '${tmp.path}/work';
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  File writeFile(String name, List<int> bytes) =>
      File('${tmp.path}/$name')..writeAsBytesSync(bytes);

  AudioImportQueue buildQueue({
    bool keepAudio = false,
    ImportTranscribeStep? transcribe,
    ImportSaveStep? save,
    void Function(List<ImportJob>)? onChanged,
    List<String>? savedTranscripts,
    List<String?>? savedAudioPaths,
  }) {
    return AudioImportQueue(
      workDir: workDir,
      keepAudio: () => keepAudio,
      decode: ({required inputPath, required outputWavPath}) =>
          decodeAudioFileToSttWav(
            inputPath: inputPath,
            outputWavPath: outputWavPath,
          ),
      transcribe: transcribe ?? (_) async => 'hallo welt',
      save:
          save ??
          ({
            required fileName,
            required transcript,
            required durationSec,
            required audioPath,
          }) async {
            savedTranscripts?.add(transcript);
            savedAudioPaths?.add(audioPath);
            return 'entry-${savedTranscripts?.length ?? 0}';
          },
      onChanged: onChanged,
    );
  }

  test('rejects folders and missing files without creating jobs', () async {
    final dir = Directory('${tmp.path}/a-folder')..createSync();
    final queue = buildQueue();

    final result = await queue.enqueue([dir.path, '${tmp.path}/missing.wav']);

    expect(queue.jobs, isEmpty);
    expect(result.jobIds, isEmpty);
    expect(result.rejections.map((r) => r.reason), [
      ImportRejectionReason.folder,
      ImportRejectionReason.notFound,
    ]);
  });

  test(
    'imports several WAV files in order and saves each transcript',
    () async {
      final a = writeFile('a.wav', _toneWav());
      final b = writeFile('b.wav', _toneWav(seconds: 0.5));
      final transcripts = <String>[];
      final queue = buildQueue(savedTranscripts: transcripts);

      await queue.enqueue([a.path, b.path]);

      expect(queue.jobs.map((j) => j.status), [
        ImportStatus.done,
        ImportStatus.done,
      ]);
      expect(queue.jobs.map((j) => j.fileName), ['a.wav', 'b.wav']);
      expect(transcripts, ['hallo welt', 'hallo welt']);
      expect(queue.jobs.every((j) => j.entryId != null), isTrue);
      expect(Directory(workDir).listSync(), isEmpty);
    },
  );

  test(
    'creates the scratch folder with mode 0700 (user audio)',
    () async {
      final big = writeFile('big.wav', _toneWav(seconds: 1));
      await buildQueue().enqueue([big.path]);

      expect(FileStat.statSync(workDir).mode & 0x1FF, 0x1C0);
    },
    skip: Platform.isWindows ? 'POSIX permissions only' : null,
  );

  test('reports copy progress while a job runs', () async {
    final big = writeFile('big.wav', _toneWav(seconds: 4));
    final seen = <double>[];
    final queue = buildQueue(
      onChanged: (jobs) {
        final p = jobs.isEmpty ? null : jobs.first.progress;
        if (p != null) seen.add(p);
      },
    );

    await queue.enqueue([big.path]);

    expect(seen, isNotEmpty);
    expect(seen.last, 1.0);
    expect(seen.every((v) => v >= 0 && v <= 1), isTrue);
  });

  test(
    'marks a non-audio file as unsupported format, not as success',
    () async {
      final text = writeFile('notes.m4a', 'plain text, not audio'.codeUnits);
      final queue = buildQueue();

      await queue.enqueue([text.path]);

      expect(queue.jobs.single.status, ImportStatus.failed);
      expect(queue.jobs.single.failure, ImportFailure.unsupportedFormat);
      expect(queue.jobs.single.entryId, isNull);
    },
  );

  test('retry requeues a failed job and it can then succeed', () async {
    final a = writeFile('a.wav', _toneWav());
    var calls = 0;
    final queue = buildQueue(
      transcribe: (_) async {
        calls++;
        if (calls == 1) throw Exception('engine not ready');
        return 'nach dem Retry';
      },
    );

    final result = await queue.enqueue([a.path]);
    expect(result.jobIds, [queue.jobs.single.id]);
    expect(queue.jobs.single.failure, ImportFailure.transcriptionFailed);

    await queue.retry(queue.jobs.single.id);

    expect(queue.jobs.single.status, ImportStatus.done);
    expect(calls, 2);
  });

  test('cancel removes a queued job before it starts', () async {
    final a = writeFile('a.wav', _toneWav());
    final b = writeFile('b.wav', _toneWav());
    final gate = Completer<void>();
    final transcribed = <int>[];
    final queue = buildQueue(
      transcribe: (bytes) async {
        transcribed.add(bytes.length);
        await gate.future;
        return 'x';
      },
    );

    final run = queue.enqueue([a.path, b.path]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    queue.cancel(queue.jobs[1].id);
    gate.complete();
    await run;

    expect(queue.jobs.map((j) => j.status), [
      ImportStatus.done,
      ImportStatus.cancelled,
    ]);
    expect(transcribed, hasLength(1));
  });

  test('keeps the decoded audio only when audio retention is on', () async {
    final a = writeFile('a.wav', _toneWav());

    final withoutAudio = <String?>[];
    await buildQueue(
      keepAudio: false,
      savedAudioPaths: withoutAudio,
    ).enqueue([a.path]);
    expect(withoutAudio, [null]);

    final withAudio = <String?>[];
    var existedDuringSave = false;
    final queue = buildQueue(
      keepAudio: true,
      save:
          ({
            required fileName,
            required transcript,
            required durationSec,
            required audioPath,
          }) async {
            withAudio.add(audioPath);
            existedDuringSave =
                audioPath != null && File(audioPath).existsSync();
            return 'entry';
          },
    );
    await queue.enqueue([a.path]);
    expect(withAudio.single, isNotNull);
    expect(existedDuringSave, isTrue);
    // The job's scratch directory is removed after the save, so the retained
    // copy must be moved out by the save step itself.
    expect(Directory(workDir).listSync(), isEmpty);
  });
}
