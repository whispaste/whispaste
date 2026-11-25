import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/audio/import/pcm_decoder.dart';
import 'package:whispaste/services/audio/upload_audio_encoder.dart';

/// A helper process that reads all of stdin and answers with [output] and
/// [exit]. [hang] keeps it silent until it is killed.
class _FakeProcess implements Process {
  _FakeProcess(this.output, this.exit, {this.hang = false}) {
    _stdin.stream.listen(received.addAll, onDone: _finish);
  }

  final List<int> output;
  final int exit;
  final bool hang;
  final received = <int>[];
  // The encoder closes stdin; kill() and _finish() close stdout.
  // ignore: close_sinks
  final _stdin = StreamController<List<int>>();
  // ignore: close_sinks
  final _stdout = StreamController<List<int>>();
  final _exit = Completer<int>();
  var killed = false;

  void _finish() {
    if (hang) return;
    if (output.isNotEmpty) _stdout.add(output);
    _stdout.close();
    if (!_exit.isCompleted) _exit.complete(exit);
  }

  @override
  // ignore: close_sinks
  late final IOSink stdin = IOSink(_stdin.sink);

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_stdout.isClosed) _stdout.close();
    if (!_exit.isCompleted) _exit.complete(-9);
    return true;
  }
}

const _webm = [0x1A, 0x45, 0xDF, 0xA3, 0x01, 0x02];

void main() {
  late Directory dir;
  late String helper;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp_upload_encoder');
    helper = '${dir.path}/ffmpeg';
    File(helper).writeAsBytesSync(const []);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Uint8List pcmOf(int seconds) => Uint8List(seconds * kSttSampleRate * 2);

  group('canonicalPcm16MonoSamples', () {
    test('returns the samples of a WhisPaste WAV as a view', () {
      final wav = Uint8List(44 + 64)..setRange(0, 44, wavHeaderPcm16Mono(64));
      final samples = canonicalPcm16MonoSamples(wav)!;
      expect(samples.length, 64);
      // A view: a change of the recording shows in the samples.
      wav[44] = 7;
      expect(samples[0], 7);
    });

    test('rejects other sample rates, stereo and a missing header', () {
      Uint8List wav() =>
          Uint8List(44 + 64)..setRange(0, 44, wavHeaderPcm16Mono(64));
      final rate = wav();
      ByteData.sublistView(rate).setUint32(24, 44100, Endian.little);
      final stereo = wav();
      ByteData.sublistView(stereo).setUint16(22, 2, Endian.little);
      expect(canonicalPcm16MonoSamples(rate), isNull);
      expect(canonicalPcm16MonoSamples(stereo), isNull);
      expect(canonicalPcm16MonoSamples(Uint8List(108)), isNull);
    });
  });

  group('OpusUploadEncoder', () {
    test('pipes the samples in and returns the WebM', () async {
      final process = _FakeProcess(_webm, 0);
      List<String>? arguments;
      final encoder = OpusUploadEncoder(
        executable: helper,
        start: (_, args) async {
          arguments = args;
          return process;
        },
      );
      final pcm = pcmOf(40);
      final result = await encoder.encode([pcm], pcm.length);

      expect(result!.bytes, _webm);
      expect(result.filename, 'audio.webm');
      expect(result.mime, 'audio/webm');
      expect(process.received.length, pcm.length);
      // Only pipes, the libopus encoder and the WebM container.
      expect(arguments, containsAllInOrder(['-protocol_whitelist', 'pipe']));
      expect(arguments, containsAllInOrder(['-c:a', 'libopus']));
      expect(arguments, containsAllInOrder(['-f', 'webm', 'pipe:1']));
    });

    test('short audio stays WAV and starts no helper', () async {
      var started = false;
      final encoder = OpusUploadEncoder(
        executable: helper,
        start: (_, _) async {
          started = true;
          return _FakeProcess(_webm, 0);
        },
      );
      final pcm = Uint8List(kUploadCompressMinPcmBytes - 2);
      expect(await encoder.encode([pcm], pcm.length), isNull);
      expect(started, isFalse);
    });

    test('a missing helper means WAV without starting anything', () async {
      var started = false;
      final encoder = OpusUploadEncoder(
        executable: '${dir.path}/missing',
        start: (_, _) async {
          started = true;
          return _FakeProcess(_webm, 0);
        },
      );
      final pcm = pcmOf(40);
      expect(await encoder.encode([pcm], pcm.length), isNull);
      expect(started, isFalse);
    });

    test('a helper that cannot start means WAV', () async {
      final encoder = OpusUploadEncoder(
        executable: helper,
        start: (_, _) async => throw const ProcessException('ffmpeg', []),
      );
      final pcm = pcmOf(40);
      expect(await encoder.encode([pcm], pcm.length), isNull);
    });

    for (final (name, output, exit) in [
      ('a failed exit', _webm, 1),
      ('an empty output', const <int>[], 0),
      ('an output that is no WebM', const [1, 2, 3, 4, 5, 6], 0),
    ]) {
      test('$name means WAV', () async {
        final encoder = OpusUploadEncoder(
          executable: helper,
          start: (_, _) async => _FakeProcess(output, exit),
        );
        final pcm = pcmOf(40);
        expect(await encoder.encode([pcm], pcm.length), isNull);
      });
    }

    test(
      'an output as large as the samples is stopped and means WAV',
      () async {
        final pcm = pcmOf(31);
        final process = _FakeProcess([..._webm, ...Uint8List(pcm.length)], 0);
        final encoder = OpusUploadEncoder(
          executable: helper,
          start: (_, _) async => process,
        );
        expect(await encoder.encode([pcm], pcm.length), isNull);
        expect(process.killed, isTrue);
      },
    );

    test('a stalled helper is killed and means WAV', () async {
      final process = _FakeProcess(_webm, 0, hang: true);
      final encoder = OpusUploadEncoder(
        executable: helper,
        start: (_, _) async => process,
        stallTimeout: const Duration(milliseconds: 300),
      );
      final pcm = pcmOf(40);
      expect(await encoder.encode([pcm], pcm.length), isNull);
      expect(process.killed, isTrue);
    });
  });
}
