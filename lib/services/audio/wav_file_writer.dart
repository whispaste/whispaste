/// Streaming WAV-container writer for the PCM-stream recording pipeline.
///
/// Writes a canonical 44-byte RIFF/WAVE/fmt /data header followed by raw
/// little-endian PCM samples. Length fields in the RIFF and data sub-chunks
/// are stamped with placeholder zeroes on construction and patched in by
/// [close] once the total payload size is known.
///
/// Pure-data: no Riverpod, no file-system coupling. The writer talks to a
/// pluggable [PcmSink], so production code can supply a [FilePcmSink] and
/// tests can use [BytesSink] in-memory.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Output sink for raw bytes consumed by [WavFileWriter].
///
/// Two operations:
/// - [add] appends a chunk at the current end of the stream.
/// - [overwrite] replaces bytes at a known offset, used by [WavFileWriter.close]
///   to patch the RIFF and data length fields after the payload size is final.
abstract class PcmSink {
  /// Appends [bytes] to the sink.
  Future<void> add(List<int> bytes);

  /// Overwrites bytes starting at [offset] with [bytes]. The sink must already
  /// contain at least `offset + bytes.length` bytes (i.e. callers can only
  /// patch over regions they previously wrote).
  Future<void> overwrite(int offset, List<int> bytes);

  /// Flushes any buffered data and releases underlying resources.
  Future<void> close();
}

/// In-memory [PcmSink] backed by a [Uint8List]. Intended for tests.
class BytesSink implements PcmSink {
  final BytesBuilder _builder = BytesBuilder(copy: false);
  Uint8List? _frozen;

  @override
  Future<void> add(List<int> bytes) async {
    if (_frozen != null) {
      throw StateError('BytesSink is closed');
    }
    _builder.add(bytes);
  }

  @override
  Future<void> overwrite(int offset, List<int> bytes) async {
    // Materialise the current buffer so we can patch in place.
    final current = _frozen ?? _builder.toBytes();
    if (offset + bytes.length > current.length) {
      throw RangeError(
        'overwrite range [$offset, ${offset + bytes.length}) exceeds '
        'sink length ${current.length}',
      );
    }
    for (var i = 0; i < bytes.length; i++) {
      current[offset + i] = bytes[i];
    }
    if (_frozen == null) {
      _builder
        ..clear()
        ..add(current);
    } else {
      _frozen = current;
    }
  }

  @override
  Future<void> close() async {
    _frozen ??= _builder.toBytes();
  }

  /// Returns the accumulated bytes. Implicitly closes the sink.
  Uint8List takeBytes() {
    _frozen ??= _builder.toBytes();
    return _frozen!;
  }
}

/// File-backed [PcmSink] using a [RandomAccessFile] to allow header
/// fix-up via `setPosition`. Production sink used by [WavFileWriter].
class FilePcmSink implements PcmSink {
  FilePcmSink._(this._raf);

  /// Opens [path] for writing (truncates if it exists).
  static Future<FilePcmSink> open(String path) async {
    final file = File(path);
    final raf = await file.open(mode: FileMode.write);
    return FilePcmSink._(raf);
  }

  final RandomAccessFile _raf;
  int _length = 0;

  @override
  Future<void> add(List<int> bytes) async {
    // Always append at the current tail.
    await _raf.setPosition(_length);
    await _raf.writeFrom(bytes);
    _length += bytes.length;
  }

  @override
  Future<void> overwrite(int offset, List<int> bytes) async {
    if (offset + bytes.length > _length) {
      throw RangeError(
        'overwrite range [$offset, ${offset + bytes.length}) exceeds '
        'file length $_length',
      );
    }
    await _raf.setPosition(offset);
    await _raf.writeFrom(bytes);
    // Restore position to tail so subsequent [add] keeps appending.
    await _raf.setPosition(_length);
  }

  @override
  Future<void> close() async {
    await _raf.close();
  }
}

/// Streaming WAV-container writer.
///
/// Usage:
/// ```dart
/// final sink = await FilePcmSink.open('/tmp/out.wav');
/// final writer = WavFileWriter(
///   sink: sink,
///   sampleRate: 16000,
///   channels: 1,
///   bitsPerSample: 16,
/// );
/// await writer.writeChunk(pcmBytes);
/// await writer.close(); // patches length fields and closes the sink.
/// ```
class WavFileWriter {
  WavFileWriter({
    required this.sink,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  }) {
    // Head of the operation queue: every later writeChunk/close is chained
    // behind the header write, so callers never need to await construction.
    unawaited(_enqueue(_writeHeader));
  }

  /// Output sink. Owned by the writer — [close] closes it.
  final PcmSink sink;

  /// Sample rate in Hz (e.g. 16000).
  final int sampleRate;

  /// Number of interleaved channels (1 = mono, 2 = stereo).
  final int channels;

  /// Bits per sample (8 / 16 / 24 / 32).
  final int bitsPerSample;

  /// Total number of PCM payload bytes written so far (excludes header).
  int _dataLength = 0;

  /// True after [close] has run.
  bool _closed = false;

  /// Tail of the sink-operation queue. Every sink access ([_writeHeader],
  /// [writeChunk], [close]) is chained onto this future so at most one
  /// operation is in flight at a time. The production sink wraps a
  /// [RandomAccessFile], which throws ("An async operation is currently
  /// pending") on overlapping async calls — the recording pipeline fires
  /// [writeChunk] without awaiting it, so an un-serialised [close] racing a
  /// late chunk made the header patch fail silently and shipped a WAV with
  /// zeroed RIFF/data size fields. whisper-server rejects exactly that shape
  /// with HTTP 400 "Invalid request" (FLUTTER_WHISPASTE-7X).
  Future<void> _pending = Future<void>.value();

  /// Chains [op] onto the queue tail and returns its future. Errors of
  /// earlier operations do not poison the queue — each caller still sees
  /// its own operation's error.
  Future<T> _enqueue<T>(Future<T> Function() op) {
    final result = _pending.then((_) => op());
    _pending = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  /// PCM format code (1 = uncompressed linear PCM).
  static const int _formatPcm = 1;

  /// Canonical header length in bytes (RIFF + fmt + data marker).
  static const int _headerSize = 44;

  /// Byte offset of the RIFF chunk size field.
  static const int _riffSizeOffset = 4;

  /// Byte offset of the data sub-chunk size field.
  static const int _dataSizeOffset = 40;

  Future<void> _writeHeader() async {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;

    final header = ByteData(_headerSize);
    // RIFF descriptor.
    header
      ..setUint8(0, 0x52) // R
      ..setUint8(1, 0x49) // I
      ..setUint8(2, 0x46) // F
      ..setUint8(3, 0x46) // F
      // Placeholder for RIFF size = (file length - 8). Patched in close().
      ..setUint32(4, 0, Endian.little)
      ..setUint8(8, 0x57) // W
      ..setUint8(9, 0x41) // A
      ..setUint8(10, 0x56) // V
      ..setUint8(11, 0x45) // E
      // fmt sub-chunk.
      ..setUint8(12, 0x66) // f
      ..setUint8(13, 0x6D) // m
      ..setUint8(14, 0x74) // t
      ..setUint8(15, 0x20) // ' '
      ..setUint32(16, 16, Endian.little) // PCM fmt chunk size
      ..setUint16(20, _formatPcm, Endian.little)
      ..setUint16(22, channels, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, byteRate, Endian.little)
      ..setUint16(32, blockAlign, Endian.little)
      ..setUint16(34, bitsPerSample, Endian.little)
      // data sub-chunk header.
      ..setUint8(36, 0x64) // d
      ..setUint8(37, 0x61) // a
      ..setUint8(38, 0x74) // t
      ..setUint8(39, 0x61) // a
      // Placeholder for data size. Patched in close().
      ..setUint32(40, 0, Endian.little);

    await sink.add(header.buffer.asUint8List());
  }

  /// Appends a chunk of raw little-endian PCM bytes.
  ///
  /// Chunks may span sample boundaries — the writer never inspects sample
  /// content, only the byte count.
  Future<void> writeChunk(List<int> bytes) async {
    if (_closed) {
      throw StateError('WavFileWriter is closed');
    }
    if (bytes.isEmpty) return;
    await _enqueue(() async {
      await sink.add(bytes);
      _dataLength += bytes.length;
    });
  }

  /// Finalises the WAV file: patches the RIFF and data length fields with
  /// their actual values and closes the underlying sink.
  ///
  /// Queued [writeChunk] operations complete first (queue order), so the
  /// patched sizes always cover every chunk that was accepted before close.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    await _enqueue(() async {
      final riffSize = _headerSize - 8 + _dataLength;
      final dataSize = _dataLength;

      final patch = ByteData(4);
      patch.setUint32(0, riffSize, Endian.little);
      await sink.overwrite(_riffSizeOffset, patch.buffer.asUint8List());

      patch.setUint32(0, dataSize, Endian.little);
      await sink.overwrite(_dataSizeOffset, patch.buffer.asUint8List());

      await sink.close();
    });
  }
}
