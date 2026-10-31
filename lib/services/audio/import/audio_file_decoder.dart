/// Turns one imported audio file into the 16 kHz mono 16-bit WAV the STT
/// engines read.
///
/// WAV is decoded in Dart ([decodeWavBytes]) on every platform. Compressed
/// formats go through the platform decoder:
/// - macOS: AVFoundation (`macos/Runner/AudioFileDecodeHost.swift`) for
///   MP3, FLAC and M4A/AAC.
/// - Linux: `linux/runner/audio_file_decode_core.cc` (libopusfile for Ogg/Opus,
///   libFLAC for FLAC, minimp3 for MP3) and `audio_file_decode_gst.cc` for
///   M4A/AAC through GStreamer, loaded at runtime (WP-35b).
/// - Windows: Media Foundation Source Reader (`windows/runner/
///   audio_file_decode_mf.cpp`) for MP3, FLAC and M4A/AAC for WP-35b.
/// A format whose platform decoder is missing at runtime fails with
/// [AudioDecoderUnavailableException]; a format the platform cannot read fails
/// with [AudioFormatUnsupportedException]. Decision and sources: docs/adr
/// (WP-35b).
library;

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import 'pcm_decoder.dart';

/// Container/codec families the import queue recognises by their magic bytes.
enum AudioSourceFormat {
  wav,
  flac,
  mp3,
  m4a,
  ogg,
  unknown;

  String get label => switch (this) {
    AudioSourceFormat.wav => 'WAV',
    AudioSourceFormat.flac => 'FLAC',
    AudioSourceFormat.mp3 => 'MP3',
    AudioSourceFormat.m4a => 'M4A/AAC',
    AudioSourceFormat.ogg => 'Ogg/Opus',
    AudioSourceFormat.unknown => 'unknown',
  };

  /// Formats that need the platform decoder.
  bool get isCompressed =>
      this == AudioSourceFormat.flac ||
      this == AudioSourceFormat.mp3 ||
      this == AudioSourceFormat.m4a ||
      this == AudioSourceFormat.ogg;
}

/// Thrown when a file cannot be imported on this platform, or its content is
/// not an audio format the decoders know. The message is user-facing.
class AudioFormatUnsupportedException implements Exception {
  const AudioFormatUnsupportedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when a supported format fails to decode (corrupt file, truncated
/// stream). Distinct from "unsupported" so the queue can offer a retry.
/// The format is known, but no platform decoder for it is installed (for
/// example M4A/AAC on Linux without GStreamer and an AAC decoder).
class AudioDecoderUnavailableException implements Exception {
  const AudioDecoderUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'AudioDecoderUnavailableException: $message';
}

/// The platform decoder could not write its output (disk full, not writable,
/// or an unreadable scratch file). The message is developer-facing.
class AudioDecoderIoException implements Exception {
  const AudioDecoderIoException(this.message);

  final String message;

  @override
  String toString() => 'AudioDecoderIoException: $message';
}

class AudioDecodeFailedException implements Exception {
  const AudioDecodeFailedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Identifies the container from the first bytes of a file.
AudioSourceFormat sniffAudioFormat(Uint8List head) {
  bool at(int offset, String tag) {
    if (head.length < offset + tag.length) return false;
    for (var i = 0; i < tag.length; i++) {
      if (head[offset + i] != tag.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (isWavBytes(head)) return AudioSourceFormat.wav;
  if (at(0, 'OggS')) return AudioSourceFormat.ogg; // Ogg/Opus or Ogg/Vorbis
  if (at(0, 'fLaC')) return AudioSourceFormat.flac;
  if (at(0, 'ID3')) return AudioSourceFormat.mp3;
  if (head.length >= 2 && head[0] == 0xFF && (head[1] & 0xE0) == 0xE0) {
    return AudioSourceFormat.mp3; // MPEG audio frame sync
  }
  if (at(4, 'ftyp')) return AudioSourceFormat.m4a;
  return AudioSourceFormat.unknown;
}

/// Platform decoder for compressed formats.
abstract class CompressedAudioDecoder {
  /// Decodes [inputPath] to 16 kHz mono PCM and writes raw little-endian
  /// int16 samples to [rawOutputPath]. Returns the number of frames written.
  Future<int> decodeToRawPcm16({
    required String inputPath,
    required String rawOutputPath,
  });
}

/// Whether this platform has a native compressed-audio decoder at all (macOS
/// AVFoundation, Linux libopusfile/libFLAC/minimp3). WAV does not need it.
/// Which format a file needs is decided by the native side.
bool compressedDecodeSupported({
  bool? isMacOS,
  bool? isLinux,
  bool? isWindows,
}) =>
    (isMacOS ?? Platform.isMacOS) ||
    (isLinux ?? Platform.isLinux) ||
    (isWindows ?? Platform.isWindows);

/// File extensions the importer accepts, used by the file picker and checked
/// against the decoder's capability. WAV everywhere; each platform adds only
/// the compressed formats its native decoder reads (see the library comment).
/// Keep in sync with the native decoders.
List<String> supportedImportExtensions({
  bool? isMacOS,
  bool? isLinux,
  bool? isWindows,
}) {
  final mac = isMacOS ?? Platform.isMacOS;
  final linux = isLinux ?? Platform.isLinux;
  final windows = isWindows ?? Platform.isWindows;
  return [
    'wav',
    if (mac) ...['mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus'],
    if (linux) ...['mp3', 'flac', 'ogg', 'opus', 'm4a', 'aac'],
    if (windows) ...['mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus'],
  ];
}

class MethodChannelAudioDecoder implements CompressedAudioDecoder {
  MethodChannelAudioDecoder({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('whispaste/audio_file_decode');

  final MethodChannel _channel;

  @override
  Future<int> decodeToRawPcm16({
    required String inputPath,
    required String rawOutputPath,
  }) async {
    if (!compressedDecodeSupported()) {
      throw const AudioFormatUnsupportedException(
        'format not supported on this platform',
      );
    }
    try {
      final frames = await _channel.invokeMethod<int>('decodeToPcm16', {
        'inputPath': inputPath,
        'outputPath': rawOutputPath,
      });
      return frames ?? 0;
    } on MissingPluginException {
      throw const AudioFormatUnsupportedException(
        'format not supported on this platform',
      );
    } on PlatformException catch (e) {
      throw nativeDecodeErrorFor(e);
    }
  }
}

/// Maps a native decoder error code to the exception the importer reports.
/// A pure function, so the mapping is testable on every host.
Exception nativeDecodeErrorFor(PlatformException e) {
  switch (e.code) {
    case 'UNSUPPORTED_FORMAT':
      return const AudioFormatUnsupportedException(
        'format not supported on this platform',
      );
    case 'UNAVAILABLE':
      return const AudioDecoderUnavailableException(
        'decoder not installed on this system',
      );
    case 'IO_ERROR':
      return AudioDecoderIoException(e.message ?? e.code);
    case 'INPUT_LIMIT':
      return AudioInputLimitException(
        'audio longer than ${kMaxImportDuration.inHours} hours',
      );
    default:
      return AudioDecodeFailedException(e.message ?? e.code);
  }
}

/// Decodes [inputPath] into a 16 kHz mono 16-bit WAV at [outputWavPath].
///
/// [inputPath] must be a copy inside the app container (see the import
/// service): on the Mac App Store the original path is not readable later.
/// Throws [AudioFormatUnsupportedException], [AudioDecodeFailedException] or
/// [AudioInputLimitException]. The input size is checked with a stat before
/// the file is opened. Compressed input is capped by the platform decoder while
/// it decodes, and the raw result is checked again by size before conversion.
///
/// All reading, resampling and writing happens in a background isolate, and
/// the WAV is streamed to disk, so long files do not freeze the UI or hold a
/// second copy of the audio in memory.
Future<void> decodeAudioFileToSttWav({
  required String inputPath,
  required String outputWavPath,
  CompressedAudioDecoder? compressedDecoder,
  int maxInputBytes = kMaxImportFileBytes,
  Duration maxDuration = kMaxImportDuration,
}) async {
  final input = File(inputPath);
  if (await input.length() > maxInputBytes) {
    throw AudioInputLimitException(
      'file larger than ${maxInputBytes ~/ 1000000} MB',
    );
  }
  final raf = await input.open();
  final Uint8List head;
  try {
    head = await raf.read(64);
  } finally {
    await raf.close();
  }
  final format = sniffAudioFormat(head);

  if (format == AudioSourceFormat.wav) {
    await Isolate.run(
      () => _wavFileToSttWav(
        inputPath,
        outputWavPath,
        maxDuration.inMilliseconds,
      ),
    );
  } else if (format.isCompressed) {
    final decoder = compressedDecoder ?? MethodChannelAudioDecoder();
    final rawPath = '$outputWavPath.raw';
    try {
      await decoder.decodeToRawPcm16(
        inputPath: inputPath,
        rawOutputPath: rawPath,
      );
      final maxRawBytes =
          maxDuration.inMilliseconds * kSttSampleRate ~/ 1000 * 2;
      if (await File(rawPath).length() > maxRawBytes) {
        throw AudioInputLimitException(
          'audio longer than ${maxDuration.inHours} hours',
        );
      }
      await Isolate.run(() => _rawPcmToWavFile(rawPath, outputWavPath));
    } finally {
      final rawFile = File(rawPath);
      if (await rawFile.exists()) await rawFile.delete();
    }
  } else {
    throw AudioFormatUnsupportedException(
      'unrecognised audio format (${format.label})',
    );
  }
}

/// Raw PCM is copied in blocks of this size, so the copy never holds the whole
/// decoded file in memory.
const int _rawCopyChunkBytes = 1 << 20;

/// Top-level so that [Isolate.run] can call it; only sendable values cross.
void _wavFileToSttWav(
  String inputPath,
  String outputWavPath,
  int maxDurationMs,
) {
  final bytes = File(inputPath).readAsBytesSync();
  final decoded = _decodeWavOrThrow(
    bytes,
    Duration(milliseconds: maxDurationMs),
  );
  final resampled = resampleLinearSinc(
    decoded.samples,
    decoded.sampleRate,
    kSttSampleRate,
  );
  final pcm = floatToPcm16(resampled);
  _writeWavFile(outputWavPath, [pcm.buffer.asUint8List()], pcm.lengthInBytes);
}

/// Top-level so that [Isolate.run] can call it. Streams the raw little-endian
/// PCM from [rawPath] into a WAV at [outputWavPath] in fixed-size blocks. A
/// trailing odd byte is dropped.
void _rawPcmToWavFile(String rawPath, String outputWavPath) {
  final RandomAccessFile raf;
  final int dataBytes;
  try {
    raf = File(rawPath).openSync();
    dataBytes = raf.lengthSync() & ~1;
  } on FileSystemException catch (e) {
    throw AudioDecoderIoException('cannot read raw PCM: ${e.message}');
  }
  final out = _openWavOutput(outputWavPath, dataBytes);
  try {
    final chunk = Uint8List(_rawCopyChunkBytes);
    var remaining = dataBytes;
    while (remaining > 0) {
      final want = remaining < chunk.length ? remaining : chunk.length;
      final read = raf.readIntoSync(chunk, 0, want);
      if (read <= 0) {
        throw AudioDecoderIoException('raw PCM ended early: $rawPath');
      }
      _writeOrThrow(out, Uint8List.sublistView(chunk, 0, read));
      remaining -= read;
    }
  } finally {
    raf.closeSync();
    _closeOutput(out);
  }
}

/// Writes [parts] as one WAV whose sample data totals [dataBytes].
void _writeWavFile(String outputWavPath, List<Uint8List> parts, int dataBytes) {
  final out = _openWavOutput(outputWavPath, dataBytes);
  try {
    for (final part in parts) {
      _writeOrThrow(out, part);
    }
  } finally {
    _closeOutput(out);
  }
}

RandomAccessFile _openWavOutput(String path, int dataBytes) {
  try {
    final out = File(path).openSync(mode: FileMode.write);
    _writeOrThrow(out, wavHeaderPcm16Mono(dataBytes));
    return out;
  } on FileSystemException catch (e) {
    throw AudioDecoderIoException('cannot write WAV: ${e.message}');
  }
}

void _writeOrThrow(RandomAccessFile out, Uint8List bytes) {
  try {
    out.writeFromSync(bytes);
  } on FileSystemException catch (e) {
    throw AudioDecoderIoException('cannot write WAV: ${e.message}');
  }
}

void _closeOutput(RandomAccessFile out) {
  try {
    out.closeSync();
  } on FileSystemException catch (e) {
    throw AudioDecoderIoException('cannot write WAV: ${e.message}');
  }
}

DecodedAudio _decodeWavOrThrow(Uint8List bytes, Duration maxDuration) {
  try {
    return decodeWavBytes(bytes, maxDuration: maxDuration);
  } on AudioDecodeException catch (e) {
    throw AudioDecodeFailedException(e.message);
  }
}
