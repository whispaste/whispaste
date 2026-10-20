/// Runs the real platform decoder (AVFoundation on macOS, libopusfile/libFLAC/
/// minimp3 on Linux, Media Foundation on Windows) against small fixtures in
/// `test/fixtures/audio_import/`, all generated locally (synthetic 440 Hz tone,
/// no third-party recordings).
///
/// Per format the expectation follows the platform's own extension list
/// ([supportedImportExtensions]): a listed format must decode to 16 kHz mono
/// with the tone's level, an unlisted one must be reported as unsupported.
/// Run with `flutter test integration_test/audio_import_decode_test.dart -d`
/// and the target macos, linux or windows.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whispaste/services/audio/import/audio_file_decoder.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';

const _fixtureDir = 'test/fixtures/audio_import';

double _rms(Float32List s) {
  var acc = 0.0;
  for (final v in s) {
    acc += v * v;
  }
  return math.sqrt(acc / s.length);
}

/// One fixture and its expected length at 16 kHz.
class _Case {
  const _Case(this.name, this.frames);

  final String name;
  final int frames;

  String get extension => name.split('.').last;
}

const _cases = [
  _Case('tone_stereo_44k.mp3', 8000),
  _Case('tone_stereo_44k.flac', 8000),
  _Case('tone_stereo_44k.m4a', 8000),
  _Case('tone1s_stereo44.mp3', 16000),
  _Case('tone1s_stereo44.flac', 16000),
  _Case('tone1s_stereo44.opus', 16000),
  _Case('tone1s_mono16.opus', 16000),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory scratch;
  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('wp35-native-');
  });
  tearDown(() async {
    await scratch.delete(recursive: true);
  });

  final listed = supportedImportExtensions();
  for (final c in _cases) {
    final decodes = listed.contains(c.extension);
    testWidgets(
      '${c.name}: ${decodes ? 'decodes to 16 kHz mono' : 'reported as unsupported'}',
      (tester) async {
        final input = File('${scratch.path}/copy-${c.name}')
          ..writeAsBytesSync(File('$_fixtureDir/${c.name}').readAsBytesSync());
        final out = '${scratch.path}/out.wav';

        final decoding = decodeAudioFileToSttWav(
          inputPath: input.path,
          outputWavPath: out,
        );
        if (!decodes) {
          await expectLater(
            decoding,
            throwsA(isA<AudioFormatUnsupportedException>()),
          );
          return;
        }
        try {
          await decoding;
        } on AudioDecoderUnavailableException {
          // Linux M4A/AAC needs GStreamer and an AAC decoder on the host. Without
          // them the import must say so clearly instead of failing obscurely.
          expect(Platform.isLinux && c.extension == 'm4a', isTrue);
          return;
        }

        final decoded = decodeWavBytes(await File(out).readAsBytes());
        expect(decoded.sampleRate, kSttSampleRate);
        // Codec padding gives a few percent of slack on the length.
        expect(decoded.samples.length, closeTo(c.frames, c.frames * 0.05));
        expect(_rms(decoded.samples), greaterThan(0.05));
        expect(File('$out.raw').existsSync(), isFalse);
      },
    );
  }

  testWidgets(
    'stereo with signal only on the right channel is not silent',
    (tester) async {
      // A plain channel pick would keep only the left channel and produce silence.
      final input = File('${scratch.path}/copy-right.flac')
        ..writeAsBytesSync(
          File('$_fixtureDir/tone_right_only_44k.flac').readAsBytesSync(),
        );
      final out = '${scratch.path}/right.wav';

      await decodeAudioFileToSttWav(inputPath: input.path, outputWavPath: out);

      final decoded = decodeWavBytes(await File(out).readAsBytes());
      // Mixing halves a one-channel tone (RMS ~0.044 here), so the bar is low;
      // a silent result is 0.0.
      expect(_rms(decoded.samples), greaterThan(0.02));
    },
    skip: !compressedDecodeSupported(),
  );

  testWidgets('a non-audio file with an audio extension is rejected', (
    tester,
  ) async {
    final input = File('${scratch.path}/fake.m4a')
      ..writeAsStringSync('this is not an mpeg-4 container at all, just text');
    await expectLater(
      decodeAudioFileToSttWav(
        inputPath: input.path,
        outputWavPath: '${scratch.path}/out.wav',
      ),
      throwsA(isA<AudioFormatUnsupportedException>()),
    );
  });
}
