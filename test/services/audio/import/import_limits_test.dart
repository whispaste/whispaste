/// Import limits (WP-43a I-H-1, I-H-2, I-M-2): sample-rate range, maximum
/// duration and maximum input size are enforced before the large buffers are
/// allocated, and non-finite float samples never reach the PCM conversion.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/audio_file_decoder.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';

/// 16-bit mono WAV with [frames] silent frames, claiming [sampleRate].
/// The rate is patched after encoding so that out-of-range values stay valid
/// header bytes.
Uint8List _wavWithRate(int sampleRate, {int frames = 10}) {
  final bytes = encodePcm16MonoWav(Int16List(frames));
  ByteData.sublistView(bytes).setUint32(24, sampleRate, Endian.little);
  return bytes;
}

void main() {
  group('sample rate range', () {
    test('rejects a header rate of 1 Hz before allocating the output', () {
      expect(
        () => decodeWavBytes(_wavWithRate(1, frames: 10000)),
        throwsA(isA<AudioDecodeException>()),
      );
    });

    test('rejects the maximum 32-bit rate', () {
      expect(
        () => decodeWavBytes(_wavWithRate(0xFFFFFFFF)),
        throwsA(isA<AudioDecodeException>()),
      );
    });

    test('rejects rates just outside 8000..192000', () {
      expect(
        () => decodeWavBytes(_wavWithRate(7999)),
        throwsA(isA<AudioDecodeException>()),
      );
      expect(
        () => decodeWavBytes(_wavWithRate(192001)),
        throwsA(isA<AudioDecodeException>()),
      );
    });

    test('accepts both ends of the range', () {
      expect(decodeWavBytes(_wavWithRate(8000)).sampleRate, 8000);
      expect(decodeWavBytes(_wavWithRate(192000)).sampleRate, 192000);
    });
  });

  group('maximum duration', () {
    test('accepts audio exactly at the limit', () {
      final bytes = _wavWithRate(16000, frames: 16000);
      final decoded = decodeWavBytes(
        bytes,
        maxDuration: const Duration(seconds: 1),
      );
      expect(decoded.samples.length, 16000);
    });

    test('rejects audio one frame over the limit as a limit error', () {
      final bytes = _wavWithRate(16000, frames: 16001);
      expect(
        () => decodeWavBytes(bytes, maxDuration: const Duration(seconds: 1)),
        throwsA(isA<AudioInputLimitException>()),
      );
    });

    test('the default limit is six hours', () {
      expect(kMaxImportDuration, const Duration(hours: 6));
    });
  });

  group('non-finite float samples', () {
    test('NaN, +Inf and -Inf become silence, finite values survive', () {
      final pcm = floatToPcm16(
        Float32List.fromList([
          double.nan,
          double.infinity,
          double.negativeInfinity,
          0.5,
        ]),
      );
      expect(pcm.toList(), [0, 0, 0, 16384]);
    });
  });

  group('maximum input size', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('wp43a-limits-');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('rejects a file above the byte limit before reading it', () async {
      final input = File('${tmp.path}/big.wav')
        ..writeAsBytesSync(_wavWithRate(16000, frames: 1000));
      await expectLater(
        decodeAudioFileToSttWav(
          inputPath: input.path,
          outputWavPath: '${tmp.path}/out.wav',
          maxInputBytes: 100,
        ),
        throwsA(isA<AudioInputLimitException>()),
      );
      expect(File('${tmp.path}/out.wav').existsSync(), isFalse);
    });

    test('the default byte limit is one GB', () {
      expect(kMaxImportFileBytes, 1000000000);
    });
  });
}
