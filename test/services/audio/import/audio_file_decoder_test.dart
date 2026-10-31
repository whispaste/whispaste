/// Unit tests for format sniffing and the decode pipeline. The platform
/// decoder is replaced with a fake here; the real AVFoundation path is covered
/// by `integration_test/audio_import_decode_test.dart` on macOS.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/audio_file_decoder.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';

Uint8List _bytes(List<int> head, {int pad = 0}) =>
    Uint8List.fromList([...head, ...List.filled(pad, 0)]);

class _FakeCompressedDecoder implements CompressedAudioDecoder {
  _FakeCompressedDecoder(this.onDecode);

  final Future<int> Function(String input, String rawOutput) onDecode;
  int calls = 0;

  @override
  Future<int> decodeToRawPcm16({
    required String inputPath,
    required String rawOutputPath,
  }) {
    calls++;
    return onDecode(inputPath, rawOutputPath);
  }
}

void main() {
  group('supportedImportExtensions', () {
    test(
      'WAV everywhere, compressed formats only where a decoder reads them',
      () {
        expect(
          supportedImportExtensions(
            isMacOS: false,
            isLinux: false,
            isWindows: false,
          ),
          ['wav'],
        );
        expect(
          supportedImportExtensions(
            isMacOS: true,
            isLinux: false,
            isWindows: false,
          ),
          ['wav', 'mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus'],
        );
        // Linux: Ogg/Opus, FLAC, MP3, and M4A/AAC through GStreamer at runtime.
        expect(
          supportedImportExtensions(
            isMacOS: false,
            isLinux: true,
            isWindows: false,
          ),
          ['wav', 'mp3', 'flac', 'ogg', 'opus', 'm4a', 'aac'],
        );
        // Windows: Media Foundation reads MP3, FLAC and M4A/AAC; Ogg/Opus goes to libopusfile.
        expect(
          supportedImportExtensions(
            isMacOS: false,
            isLinux: false,
            isWindows: true,
          ),
          ['wav', 'mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus'],
        );
      },
    );

    test(
      'the decoder accepts compressed input exactly where the list has it',
      () {
        bool supported({
          required bool mac,
          required bool linux,
          required bool windows,
        }) => compressedDecodeSupported(
          isMacOS: mac,
          isLinux: linux,
          isWindows: windows,
        );
        expect(supported(mac: false, linux: false, windows: false), isFalse);
        expect(supported(mac: true, linux: false, windows: false), isTrue);
        expect(supported(mac: false, linux: true, windows: false), isTrue);
        expect(supported(mac: false, linux: false, windows: true), isTrue);
      },
    );
  });

  group('sniffAudioFormat', () {
    test('recognises each supported container by its magic bytes', () {
      expect(
        sniffAudioFormat(
          _bytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]),
        ),
        AudioSourceFormat.wav,
      );
      expect(
        sniffAudioFormat(_bytes('fLaC'.codeUnits)),
        AudioSourceFormat.flac,
      );
      expect(sniffAudioFormat(_bytes('OggS'.codeUnits)), AudioSourceFormat.ogg);
      expect(sniffAudioFormat(_bytes('ID3'.codeUnits)), AudioSourceFormat.mp3);
      expect(
        sniffAudioFormat(_bytes([0xFF, 0xFB, 0x90])),
        AudioSourceFormat.mp3,
      );
      expect(
        sniffAudioFormat(_bytes([0, 0, 0, 0x1C, ...'ftypM4A '.codeUnits])),
        AudioSourceFormat.m4a,
      );
    });

    test('returns unknown for text and empty input', () {
      expect(
        sniffAudioFormat(_bytes('hello world'.codeUnits)),
        AudioSourceFormat.unknown,
      );
      expect(sniffAudioFormat(Uint8List(0)), AudioSourceFormat.unknown);
    });
  });

  group('platform decoder errors', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('whispaste/audio_file_decode');
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('wp35-channel-');
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
    });

    void mockNative(Future<Object?> Function(MethodCall) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    Future<void> expectFailure(Matcher matcher) async {
      final input = File('${dir.path}/in.ogg')
        ..writeAsBytesSync(_bytes('OggS'.codeUnits, pad: 64));
      await expectLater(
        decodeAudioFileToSttWav(
          inputPath: input.path,
          outputWavPath: '${dir.path}/out.wav',
        ),
        throwsA(matcher),
      );
      expect(File('${dir.path}/out.wav').existsSync(), isFalse);
    }

    test('an INPUT_LIMIT from the native side is an input limit', () async {
      mockNative((_) async => throw PlatformException(code: 'INPUT_LIMIT'));
      await expectFailure(isA<AudioInputLimitException>());
    }, skip: !compressedDecodeSupported());

    test('a DECODE_FAILED from the native side is a decode failure', () async {
      mockNative(
        (_) async => throw PlatformException(
          code: 'DECODE_FAILED',
          message: 'no audio decoded',
        ),
      );
      await expectFailure(isA<AudioDecodeFailedException>());
    }, skip: !compressedDecodeSupported());

    test(
      'UNSUPPORTED_FORMAT stays unsupported, not a decode failure',
      () async {
        mockNative(
          (_) async => throw PlatformException(code: 'UNSUPPORTED_FORMAT'),
        );
        await expectFailure(isA<AudioFormatUnsupportedException>());
      },
      skip: !compressedDecodeSupported(),
    );

    test(
      'UNAVAILABLE means the decoder is missing, not that the format is wrong',
      () async {
        mockNative((_) async => throw PlatformException(code: 'UNAVAILABLE'));
        await expectFailure(isA<AudioDecoderUnavailableException>());
      },
      skip: !compressedDecodeSupported(),
    );
  });

  group('nativeDecodeErrorFor', () {
    test('maps IO_ERROR to an IO failure on every host', () {
      final error = nativeDecodeErrorFor(
        PlatformException(code: 'IO_ERROR', message: 'disk full'),
      );
      expect(error, isA<AudioDecoderIoException>());
      expect(error.toString(), contains('disk full'));
    });
  });

  group('decodeAudioFileToSttWav', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('wp35-decode-');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test(
      'decodes a WAV in Dart without touching the platform decoder',
      () async {
        final input = File('${dir.path}/in.wav');
        final pcm = Int16List.fromList(
          List.generate(4800, (i) => (i % 200) * 100),
        );
        // 48 kHz mono 16-bit: resampled to 16 kHz by the Dart path.
        final wav48k = _wav48kMono(pcm);
        await input.writeAsBytes(wav48k);
        final fake = _FakeCompressedDecoder((_, _) async => 0);

        final out = '${dir.path}/out.wav';
        await decodeAudioFileToSttWav(
          inputPath: input.path,
          outputWavPath: out,
          compressedDecoder: fake,
        );

        expect(fake.calls, 0);
        final decoded = decodeWavBytes(await File(out).readAsBytes());
        expect(decoded.sampleRate, 16000);
        expect(decoded.samples.length, 1600);
      },
    );

    test('wraps raw PCM from the platform decoder into a 16 kHz WAV', () async {
      final input = File('${dir.path}/in.mp3')
        ..writeAsBytesSync(_bytes('ID3'.codeUnits, pad: 64));
      final raw = Int16List.fromList([0, 16384, -16384, 32767]);
      final fake = _FakeCompressedDecoder((_, rawOut) async {
        await File(rawOut).writeAsBytes(raw.buffer.asUint8List());
        return raw.length;
      });

      final out = '${dir.path}/out.wav';
      await decodeAudioFileToSttWav(
        inputPath: input.path,
        outputWavPath: out,
        compressedDecoder: fake,
      );

      expect(fake.calls, 1);
      final decoded = decodeWavBytes(await File(out).readAsBytes());
      expect(decoded.samples.length, 4);
      expect(decoded.samples[1], closeTo(0.5, 1e-4));
      // The intermediate raw file is removed.
      expect(File('$out.raw').existsSync(), isFalse);
    });

    test(
      'streams a raw file larger than one copy chunk without changing it',
      () async {
        final input = File('${dir.path}/long.mp3')
          ..writeAsBytesSync(_bytes('ID3'.codeUnits, pad: 64));
        // Two and a half 1 MiB chunks plus one stray byte: the copy must keep
        // every sample, drop the stray byte and leave no partial file behind.
        final samples = Int16List.fromList(
          List.generate(1300000, (i) => (i * 37) % 65536 - 32768),
        );
        final rawBytes = Uint8List.fromList([
          ...samples.buffer.asUint8List(),
          7,
        ]);
        final fake = _FakeCompressedDecoder((_, rawOut) async {
          await File(rawOut).writeAsBytes(rawBytes);
          return samples.length;
        });

        final out = '${dir.path}/long.wav';
        await decodeAudioFileToSttWav(
          inputPath: input.path,
          outputWavPath: out,
          compressedDecoder: fake,
        );

        final wav = await File(out).readAsBytes();
        expect(wav.length, 44 + samples.lengthInBytes);
        expect(wav.sublist(44), samples.buffer.asUint8List());
        expect(File('$out.raw').existsSync(), isFalse);
      },
    );

    test('removes the raw PCM even when the platform decoder fails', () async {
      final input = File('${dir.path}/broken.mp3')
        ..writeAsBytesSync(_bytes('ID3'.codeUnits, pad: 64));
      final fake = _FakeCompressedDecoder((_, rawOut) async {
        await File(rawOut).writeAsBytes(Uint8List(4096));
        throw const AudioDecodeFailedException('stopped halfway');
      });

      final out = '${dir.path}/broken.wav';
      await expectLater(
        decodeAudioFileToSttWav(
          inputPath: input.path,
          outputWavPath: out,
          compressedDecoder: fake,
        ),
        throwsA(isA<AudioDecodeFailedException>()),
      );

      expect(File('$out.raw').existsSync(), isFalse);
      expect(File(out).existsSync(), isFalse);
    });

    test('reports an unsupported compressed format as unsupported', () async {
      final input = File('${dir.path}/in.flac')
        ..writeAsBytesSync(_bytes('fLaC'.codeUnits, pad: 64));
      final fake = _FakeCompressedDecoder(
        (_, _) async => throw const AudioFormatUnsupportedException(
          'format not supported on this platform',
        ),
      );

      await expectLater(
        decodeAudioFileToSttWav(
          inputPath: input.path,
          outputWavPath: '${dir.path}/out.wav',
          compressedDecoder: fake,
        ),
        throwsA(
          isA<AudioFormatUnsupportedException>().having(
            (e) => e.message,
            'message',
            'format not supported on this platform',
          ),
        ),
      );
      expect(File('${dir.path}/out.wav').existsSync(), isFalse);
    });

    test('rejects files that are not audio at all', () async {
      final input = File('${dir.path}/notes.txt')
        ..writeAsStringSync('just text, not audio');
      await expectLater(
        decodeAudioFileToSttWav(
          inputPath: input.path,
          outputWavPath: '${dir.path}/out.wav',
          compressedDecoder: _FakeCompressedDecoder((_, _) async => 0),
        ),
        throwsA(isA<AudioFormatUnsupportedException>()),
      );
    });

    test('maps a corrupt WAV to a decode failure, not a crash', () async {
      final input = File('${dir.path}/bad.wav')
        ..writeAsBytesSync(
          _bytes([
            0x52,
            0x49,
            0x46,
            0x46,
            4,
            0,
            0,
            0,
            0x57,
            0x41,
            0x56,
            0x45,
          ], pad: 4),
        );
      await expectLater(
        decodeAudioFileToSttWav(
          inputPath: input.path,
          outputWavPath: '${dir.path}/out.wav',
          compressedDecoder: _FakeCompressedDecoder((_, _) async => 0),
        ),
        throwsA(isA<AudioDecodeFailedException>()),
      );
    });
  });
}

/// 48 kHz mono 16-bit WAV around [pcm].
Uint8List _wav48kMono(Int16List pcm) {
  const rate = 48000;
  final data = pcm.buffer.asUint8List();
  final out = ByteData(44 + data.length)
    ..setUint32(0, 0x46464952, Endian.little)
    ..setUint32(4, 36 + data.length, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little)
    ..setUint32(12, 0x20746D66, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x61746164, Endian.little)
    ..setUint32(40, data.length, Endian.little);
  final bytes = out.buffer.asUint8List()..setRange(44, 44 + data.length, data);
  return bytes;
}
