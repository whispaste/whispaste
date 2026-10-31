/// Pre-send repair for WAV payloads whose RIFF/data size fields were never
/// patched (FLUTTER_WHISPASTE-7X: whisper-server answers HTTP 400 "Invalid
/// request" for exactly that shape). The repair itself lives in
/// `repairWavHeader` (lib/services/audio/wav_header_repair.dart); this keeps
/// the nullable contract that the local engine and its tests rely on.
library;

import 'dart:typed_data';

import '../audio/wav_header_repair.dart';

/// Canonical header length (RIFF + fmt + data marker) in bytes.
const int _headerSize = 44;

/// Returns [bytes] repaired in place (zero-copy, see `repairWavHeader`), or
/// `null` when no repair is needed or there is no PCM data to repair (a bare
/// header). A non-null result shares its bytes with [bytes], whose size fields
/// it has patched.
Uint8List? repairZeroedWavSizeFields(Uint8List bytes) {
  if (bytes.length <= _headerSize) return null;
  final repaired = repairWavHeader(bytes);
  return identical(repaired, bytes) ? null : repaired;
}
