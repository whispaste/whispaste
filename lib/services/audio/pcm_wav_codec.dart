/// Shared PCM/WAV codec for WhisPaste's on-device STT engines.
///
/// Both whisper.cpp (`whisper_full`) and sherpa_onnx expect the SAME input —
/// normalized `[-1, 1]` float32 samples, 16 kHz mono. WhisPaste's recorder
/// already captures 16 kHz mono 16-bit PCM (`audio_service.dart`), so decoding
/// is only a 44-byte header skip plus int16-LE → float32; **no resampling** is
/// required.
library;

import 'dart:io';
import 'dart:typed_data';

/// Decodes WhisPaste's canonical 44-byte-header, 16 kHz mono, 16-bit PCM WAV
/// bytes (see `wav_file_writer.dart`) into normalized `[-1, 1]` float samples.
///
/// Returns an empty list for header-only or truncated input.
Float32List pcm16WavBytesToFloat32(List<int> wavBytes) {
  const headerSize = 44;
  if (wavBytes.length <= headerSize) return Float32List(0);

  final bytes = wavBytes is Uint8List ? wavBytes : Uint8List.fromList(wavBytes);
  return pcm16BytesToFloat32(Uint8List.sublistView(bytes, headerSize));
}

/// Decodes raw, HEADER-LESS 16-bit mono PCM bytes (little-endian) into
/// normalized `[-1, 1]` float samples — the same conversion
/// [pcm16WavBytesToFloat32] does after skipping the WAV header, split out so
/// callers that never had a WAV header in the first place (the live-preview
/// streaming path, which reads directly off `AudioRecorder.startStream`'s
/// raw PCM chunks) don't need to fabricate one just to reuse this logic.
///
/// Returns an empty list for a trailing odd byte (incomplete sample).
Float32List pcm16BytesToFloat32(Uint8List pcmBytes) {
  final byteData = ByteData.sublistView(pcmBytes);
  final sampleCount = byteData.lengthInBytes ~/ 2;
  final samples = Float32List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}

/// Length of the canonical WAV header the recorder writes; the PCM starts
/// right after it.
const int pcm16WavHeaderBytes = 44;

/// The PCM of a canonical WAV ([pcm16WavBytesToFloat32]'s input) read in
/// place, so a long recording is turned into float32 one decode window at a
/// time instead of all at once (#1642). [toFloat32] over the whole range
/// equals [pcm16WavBytesToFloat32], sample for sample.
///
/// Two forms read the same samples: [Pcm16WavView.new] over bytes in memory
/// and [Pcm16WavView.file] over the WAV file itself (#1665), which reads only
/// the range asked for. Both skip [pcm16WavHeaderBytes] and ignore the
/// header's size fields, so a WAV whose size fields were never patched reads
/// the same as its repaired copy.
abstract class Pcm16WavView {
  /// The PCM inside [wavBytes].
  factory Pcm16WavView(List<int> wavBytes) {
    if (wavBytes.length <= pcm16WavHeaderBytes) {
      return _MemoryPcm16WavView(ByteData(0));
    }
    final bytes = wavBytes is Uint8List
        ? wavBytes
        : Uint8List.fromList(wavBytes);
    return _MemoryPcm16WavView(
      ByteData.sublistView(bytes, pcm16WavHeaderBytes),
    );
  }

  /// The PCM of the WAV file at [path], read on demand (#1665). The sample
  /// count is fixed by the file's length now. Each read opens the file and
  /// closes it again, so no handle stays open between decode windows (on
  /// Windows an open handle would block moving or deleting the recording).
  /// Throws [FileSystemException] when the file cannot be read, here or in a
  /// later read (for example when it was deleted or shortened meanwhile).
  factory Pcm16WavView.file(String path) => _FilePcm16WavView(path);

  Pcm16WavView._();

  /// Whole samples after the header; a trailing odd byte does not count.
  int get sampleCount;

  /// The little-endian 16-bit PCM of samples `[start, end)`. The result may
  /// be a view of a buffer the next call reuses: read it before asking for
  /// the next range.
  ByteData pcmBytes(int start, int end);

  /// Sample [index] normalized to `[-1, 1]`.
  double sampleAt(int index) =>
      pcmBytes(index, index + 1).getInt16(0, Endian.little) / 32768.0;

  /// Samples `[start, end)` as a new float32 list.
  Float32List toFloat32(int start, int end) =>
      toFloat32Into(start, end, Float32List(end - start));

  /// Samples `[start, end)` as float32 in the front of [buffer], returned as
  /// a view of exactly that length. A decode loop reuses one buffer for all
  /// windows: each fresh window of a few MB would otherwise be garbage the
  /// heap only collects much later.
  Float32List toFloat32Into(int start, int end, Float32List buffer) {
    RangeError.checkValidRange(start, end, sampleCount);
    final length = end - start;
    if (buffer.length < length) {
      throw ArgumentError.value(
        buffer.length,
        'buffer',
        'shorter than $length',
      );
    }
    final pcm = pcmBytes(start, end);
    for (var i = 0; i < length; i++) {
      buffer[i] = pcm.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return Float32List.sublistView(buffer, 0, length);
  }
}

final class _MemoryPcm16WavView extends Pcm16WavView {
  _MemoryPcm16WavView(this._pcm)
    : sampleCount = _pcm.lengthInBytes ~/ 2,
      super._();

  final ByteData _pcm;

  @override
  final int sampleCount;

  @override
  ByteData pcmBytes(int start, int end) {
    RangeError.checkValidRange(start, end, sampleCount);
    return ByteData.sublistView(_pcm, start * 2, end * 2);
  }
}

final class _FilePcm16WavView extends Pcm16WavView {
  _FilePcm16WavView(this.path)
    : sampleCount = _sampleCountOfLength(File(path).lengthSync()),
      super._();

  final String path;

  @override
  final int sampleCount;

  /// Read buffer, grown to the largest range asked for (one decode window or
  /// one scan block, about 1 MB) and reused.
  Uint8List _scratch = Uint8List(0);

  @override
  ByteData pcmBytes(int start, int end) {
    RangeError.checkValidRange(start, end, sampleCount);
    final length = (end - start) * 2;
    if (_scratch.length < length) _scratch = Uint8List(length);
    final file = File(path).openSync();
    try {
      file.setPositionSync(pcm16WavHeaderBytes + start * 2);
      var filled = 0;
      while (filled < length) {
        final read = file.readIntoSync(_scratch, filled, length);
        if (read <= 0) {
          throw FileSystemException(
            'WAV file is shorter than when it was opened',
            path,
          );
        }
        filled += read;
      }
    } finally {
      file.closeSync();
    }
    return ByteData.sublistView(_scratch, 0, length);
  }
}

int _sampleCountOfLength(int length) =>
    length <= pcm16WavHeaderBytes ? 0 : (length - pcm16WavHeaderBytes) ~/ 2;

/// A recording as one isolate hands it to another (#1665): the path of its
/// WAV file, which the receiving side reads a window at a time, or the WAV
/// bytes when there is no file to read. Sending the path copies nothing;
/// sending bytes copies all of them into the receiving isolate.
final class Pcm16WavSource {
  const Pcm16WavSource.file(String this.path) : bytes = null;
  const Pcm16WavSource.bytes(Uint8List this.bytes) : path = null;

  /// The source for [wavBytes]: the file at [wavPath] when it holds the same
  /// samples ([wavFileMatches]), else the bytes themselves.
  factory Pcm16WavSource.preferFile(List<int> wavBytes, String? wavPath) {
    if (wavPath != null && wavFileMatches(wavPath, wavBytes)) {
      return Pcm16WavSource.file(wavPath);
    }
    return Pcm16WavSource.bytes(
      wavBytes is Uint8List ? wavBytes : Uint8List.fromList(wavBytes),
    );
  }

  /// The WAV file, or `null` for [bytes].
  final String? path;

  /// The WAV bytes, or `null` for [path].
  final Uint8List? bytes;

  /// Opens the view on the receiving side.
  Pcm16WavView open() {
    final file = path;
    return file != null ? Pcm16WavView.file(file) : Pcm16WavView(bytes!);
  }
}

/// Whether the WAV file at [path] exists and holds as many samples as
/// [wavBytes], so reading it gives what [wavBytes] would give (#1665). The
/// caller passes the bytes it read from that same file; this only catches a
/// file that is gone or changed size since. Never throws.
bool wavFileMatches(String path, List<int> wavBytes) {
  try {
    final file = File(path);
    if (!file.existsSync()) return false;
    return _sampleCountOfLength(file.lengthSync()) ==
        _sampleCountOfLength(wavBytes.length);
  } on FileSystemException {
    return false;
  }
}
