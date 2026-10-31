/// Repairs the size fields of a WAV that was cut off before it was finalised.
///
/// [WavFileWriter] writes the RIFF and data size fields as zeroes and only
/// patches them in `close()`. A recording that ends by crash or kill keeps
/// those zeroes, and a copy truncated during transfer can promise more sample
/// data than it holds. Engines reject such files (whisper-server answers HTTP
/// 400), so the transcription path repairs them first.
library;

import 'dart:typed_data';

/// Returns [wav] with its size fields set from the bytes actually present.
///
/// Only a broken data size triggers a repair: zero, `0xFFFFFFFF` (streaming
/// placeholder), or larger than the bytes after the data header. Then the data
/// size becomes the remaining length, rounded down to whole sample frames, the
/// RIFF size is set to match, and the bytes after the frames are dropped.
///
/// The repair is zero-copy: the size fields are patched in place and the
/// result is a view over the same buffer, so the sample data is never
/// duplicated (a 60-minute recording is about 115 MB). For a [Uint8List]
/// input the caller's buffer therefore changes: its size fields are repaired
/// and its length stays the same. Pass a copy if the original header matters.
///
/// Returns [wav] itself when nothing needs repair, when it is not a RIFF/WAVE
/// file, or when no `fmt ` and `data` chunk can be found. Those inputs reach
/// the engine untouched, so the engine reports its own error.
Uint8List repairWavHeader(List<int> wav) {
  final bytes = wav is Uint8List ? wav : Uint8List.fromList(wav);
  if (bytes.length < 12 ||
      !_hasTag(bytes, 0, 'RIFF') ||
      !_hasTag(bytes, 8, 'WAVE')) {
    return bytes;
  }

  int? blockAlign;
  int? dataHeader;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    if (_hasTag(bytes, offset, 'data')) {
      dataHeader = offset;
      break;
    }
    final size = _readU32(bytes, offset + 4);
    if (_hasTag(bytes, offset, 'fmt ') && offset + 8 + 16 <= bytes.length) {
      blockAlign = _readU16(bytes, offset + 8 + 12);
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  if (dataHeader == null || blockAlign == null || blockAlign == 0) {
    return bytes;
  }

  final dataStart = dataHeader + 8;
  final remaining = bytes.length - dataStart;
  final declared = _readU32(bytes, dataHeader + 4);
  final broken =
      declared == 0 || declared == 0xFFFFFFFF || declared > remaining;
  if (!broken) return bytes;

  final dataBytes = remaining - remaining % blockAlign;
  final end = dataStart + dataBytes;
  _writeU32(bytes, 4, end - 8);
  _writeU32(bytes, dataHeader + 4, dataBytes);
  return Uint8List.sublistView(bytes, 0, end);
}

bool _hasTag(List<int> bytes, int offset, String tag) {
  for (var i = 0; i < 4; i++) {
    if (bytes[offset + i] != tag.codeUnitAt(i)) return false;
  }
  return true;
}

int _readU16(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _readU32(List<int> bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

void _writeU32(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}
