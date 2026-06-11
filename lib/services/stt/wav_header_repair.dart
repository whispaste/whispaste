/// Pre-send repair for WAV payloads whose RIFF/data size fields are zero.
///
/// Field shape FLUTTER_WHISPASTE-7X: a recording whose header patch never
/// ran (the pre-serialisation [WavFileWriter] lost the `close()` patch when
/// it raced a late chunk write) ships with valid PCM data but zeroed size
/// fields. whisper-server's audio decoder rejects exactly that container as
/// unreadable, and httplib surfaces it as HTTP 400 "Invalid request" — the
/// user's dictation is silently lost although the samples are all there.
///
/// The sizes are fully derivable from the byte length for the canonical
/// 44-byte-header layout the app records (RIFF → fmt → data, no extra
/// chunks), so the transcriber repairs them deterministically instead of
/// letting the server reject the request. Pure, dependency-free.
library;

import 'dart:typed_data';

/// Byte offset of the RIFF chunk size field.
const int _riffSizeOffset = 4;

/// Byte offset of the data sub-chunk size field in the canonical layout.
const int _dataSizeOffset = 40;

/// Canonical header length (RIFF + fmt + data marker) in bytes.
const int _headerSize = 44;

bool _hasTag(Uint8List bytes, int offset, String tag) {
  for (var i = 0; i < tag.length; i++) {
    if (bytes[offset + i] != tag.codeUnitAt(i)) return false;
  }
  return true;
}

int _readU32LE(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

void _writeU32LE(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}

/// Returns a copy of [bytes] with the RIFF and data size fields patched to
/// match the actual byte length, or `null` when no repair is needed or the
/// payload is not a canonical-layout WAV this module can reason about.
///
/// Repair fires only when ALL of the following hold:
/// - payload is longer than the 44-byte canonical header (there is PCM data),
/// - `RIFF`/`WAVE`/`fmt `/`data` markers sit at their canonical offsets,
/// - at least one of the two size fields is zero (the unpatched-header
///   signature — a well-formed encoder never writes zero alongside data).
///
/// Non-canonical WAVs (extra chunks, float PCM, …) are left untouched: their
/// size fields cannot be derived from the byte length alone.
Uint8List? repairZeroedWavSizeFields(Uint8List bytes) {
  if (bytes.length <= _headerSize) return null;
  if (!_hasTag(bytes, 0, 'RIFF') ||
      !_hasTag(bytes, 8, 'WAVE') ||
      !_hasTag(bytes, 12, 'fmt ') ||
      !_hasTag(bytes, 36, 'data')) {
    return null;
  }

  final riffSize = _readU32LE(bytes, _riffSizeOffset);
  final dataSize = _readU32LE(bytes, _dataSizeOffset);
  if (riffSize != 0 && dataSize != 0) return null;

  final repaired = Uint8List.fromList(bytes);
  _writeU32LE(repaired, _riffSizeOffset, bytes.length - 8);
  _writeU32LE(repaired, _dataSizeOffset, bytes.length - _headerSize);
  return repaired;
}
