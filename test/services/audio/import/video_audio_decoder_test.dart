import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/audio_drop_intake.dart';
import 'package:whispaste/services/audio/import/audio_file_decoder.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';
import 'package:whispaste/services/audio/import/video_audio_decoder.dart';

class _Child implements Process {
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  final exited = Completer<int>();
  bool killed = false;

  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  Future<int> get exitCode => exited.future;
  @override
  int get pid => 1;
  @override
  IOSink get stdin => throw UnimplementedError();

  void finish(int code) {
    if (exited.isCompleted) return;
    unawaited(output.close());
    unawaited(errors.close());
    exited.complete(code);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (exited.isCompleted) return false;
    killed = true;
    finish(-1);
    return true;
  }
}

void main() {
  late Directory tmp;
  late File input;
  late String wav;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('video-import-');
    input = File('${tmp.path}/interview.MP4');
    await input.writeAsBytes([0, 0, 0, 24, ...'ftypisom'.codeUnits]);
    wav = '${tmp.path}/audio.wav';
  });
  tearDown(() => tmp.delete(recursive: true));

  test('sniffs MP4, legacy MOV and EBML, refuses a renamed text file', () {
    for (final box in ['ftypisom', 'ftypqt  ', 'moov', 'mdat', 'wide']) {
      expect(
        sniffAudioFormat(Uint8List.fromList([0, 0, 0, 24, ...box.codeUnits])),
        AudioSourceFormat.mp4,
      );
    }
    expect(
      sniffAudioFormat(Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3])),
      AudioSourceFormat.matroska,
    );
    expect(
      sniffAudioFormat(Uint8List.fromList('video.mp4'.codeUnits)),
      AudioSourceFormat.unknown,
    );
    expect(
      sniffAudioFormat(Uint8List.fromList([0x1a, 0x45])),
      AudioSourceFormat.unknown,
    );
  });

  test(
    'picker extensions also accept all four video formats on drop',
    () async {
      final files = <String>[];
      for (final ext in videoImportExtensions) {
        final file = await input.copy('${tmp.path}/clip.${ext.toUpperCase()}');
        files.add(file.path);
      }
      for (final platform in ['mac', 'win', 'linux']) {
        final allowed = supportedImportExtensions(
          isMacOS: platform == 'mac',
          isWindows: platform == 'win',
          isLinux: platform == 'linux',
        );
        final split = await splitAudioDrop(files, extensions: allowed.toSet());
        expect(split.accepted, files);
        expect(split.rejected, isEmpty);
      }
    },
  );

  VideoAudioDecoder decoder(_Child child, void Function(_Child) produce) =>
      VideoAudioDecoder(
        executable: '/app/video-decoder/ffmpeg',
        start: (executable, arguments) async {
          expect(executable, '/app/video-decoder/ffmpeg');
          expect(
            arguments,
            containsAllInOrder([
              '-protocol_whitelist',
              'file,pipe',
              '-f',
              'mov',
            ]),
          );
          expect(
            arguments,
            containsAllInOrder(['-map', '0:a:0', '-vn', '-sn', '-dn']),
          );
          scheduleMicrotask(() => produce(child));
          return child;
        },
      );

  Future<void> extract(
    VideoAudioDecoder decoder, {
    ImportDecodeControl? control,
    Duration maxDuration = kMaxImportDuration,
  }) => decodeAudioFileToSttWav(
    inputPath: input.path,
    outputWavPath: wav,
    videoDecoder: decoder,
    control: control,
    maxDuration: maxDuration,
  );

  test(
    'streams PCM to canonical WAV and reports extraction progress',
    () async {
      final progress = <double>[];
      final child = _Child();
      await extract(
        decoder(child, (child) {
          child.errors.add(
            utf8.encode(
              '  Duration: 00:00:02.00, start: 0\nout_time_us=1000000\n',
            ),
          );
          child.output.add([0, 0, 255, 127]);
          child.finish(0);
        }),
        control: ImportDecodeControl(
          isCancelled: () => false,
          onProgress: progress.add,
        ),
      );
      expect(decodeWavBytes(await File(wav).readAsBytes()).samples.length, 2);
      expect(progress, contains(0.5));
      expect(progress.last, 1);
      expect(File('$wav.raw').existsSync(), isFalse);
    },
  );

  test(
    'empty or partially corrupt video never yields a successful WAV',
    () async {
      for (final exit in [0, 1]) {
        final child = _Child();
        await expectLater(
          extract(
            decoder(child, (child) {
              if (exit == 1) child.output.add([0, 0]);
              child.finish(exit);
            }),
          ),
          throwsA(isA<AudioDecodeFailedException>()),
        );
        expect(File(wav).existsSync(), isFalse);
        expect(File('$wav.raw').existsSync(), isFalse);
        expect(input.existsSync(), isTrue);
      }
    },
  );

  test('a silent video gets a distinct no-audio failure', () async {
    final child = _Child();
    await expectLater(
      extract(
        decoder(child, (child) {
          child.errors.add(
            utf8.encode("Stream map '0:a:0' matches no streams.\n"),
          );
          child.finish(1);
        }),
      ),
      throwsA(isA<VideoHasNoAudio>()),
    );
    expect(File('$wav.raw').existsSync(), isFalse);
  });

  test('a missing helper is reported without falling back to PATH', () async {
    final missing = VideoAudioDecoder(
      start: (_, _) async =>
          throw const ProcessException('ffmpeg', [], 'missing'),
    );
    await expectLater(
      extract(missing),
      throwsA(isA<VideoDecoderUnavailable>()),
    );
  });

  test('cancel before launch creates no child and no scratch output', () async {
    final never = VideoAudioDecoder(
      start: (_, _) async => throw StateError('must not launch'),
    );
    await expectLater(
      extract(never, control: ImportDecodeControl(isCancelled: () => true)),
      throwsA(isA<AudioImportCancelled>()),
    );
    expect(File('$wav.raw').existsSync(), isFalse);
  });

  test('cancelling a stalled extraction kills and reaps the child', () async {
    var cancelled = false;
    final child = _Child();
    final result = extract(
      decoder(child, (_) {
        cancelled = true;
      }),
      control: ImportDecodeControl(isCancelled: () => cancelled),
    );
    await expectLater(result, throwsA(isA<AudioImportCancelled>()));
    expect(child.killed, isTrue);
    expect(child.exited.isCompleted, isTrue);
    expect(File('$wav.raw').existsSync(), isFalse);
    expect(input.existsSync(), isTrue);
  });

  test('duration limit also bounds PCM when metadata is absent', () async {
    final child = _Child();
    await expectLater(
      extract(
        decoder(child, (child) {
          child.output.add(List.filled(32002, 0));
        }),
        maxDuration: const Duration(seconds: 1),
      ),
      throwsA(isA<AudioInputLimitException>()),
    );
    expect(child.killed, isTrue);
    expect(File('$wav.raw').existsSync(), isFalse);
  });

  test('output failure kills the child and is classified as I/O', () async {
    final child = _Child();
    await expectLater(
      decoder(child, (_) {}).decodeToRawPcm16(
        inputPath: input.path,
        rawOutputPath: '${tmp.path}/missing/audio.raw',
        format: AudioSourceFormat.mp4,
      ),
      throwsA(isA<AudioDecoderIoException>()),
    );
    expect(child.killed, isTrue);
  });

  test(
    'queue cancellation removes scratch, preserves source and allows retry',
    () async {
      late AudioImportQueue queue;
      var first = true;
      queue = AudioImportQueue(
        workDir: '${tmp.path}/work',
        keepAudio: () => true,
        decode: ({required inputPath, required outputWavPath}) async =>
            throw StateError('controlled path required'),
        decodeWithControl:
            ({
              required inputPath,
              required outputWavPath,
              required control,
            }) async {
              if (first) {
                first = false;
                queue.cancel(queue.jobs.single.id);
                control.checkCancelled();
              }
              await File(
                outputWavPath,
              ).writeAsBytes(encodePcm16MonoWav(Int16List(16)));
            },
        transcribe: (_, {onProgress, sliceManifestPath}) async => 'interview',
        save:
            ({
              required fileName,
              required transcript,
              required durationSec,
              required audioPath,
            }) async => 'entry',
      );
      final result = await queue.enqueue([input.path]);
      expect(queue.jobs.single.status, ImportStatus.cancelled);
      expect(
        Directory('${tmp.path}/work/${result.jobIds.single}').existsSync(),
        isFalse,
      );
      expect(input.existsSync(), isTrue);
      await queue.retry(result.jobIds.single);
      expect(queue.jobs.single.status, ImportStatus.done);
    },
  );
}
