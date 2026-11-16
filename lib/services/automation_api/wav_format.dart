/// WAV format gate for the automation API transcription route (ticket / 8.2).
///
/// Accepts exactly what the existing transcription path is fed today: RIFF
/// WAVE, uncompressed PCM, one channel, 16 kHz, 16 bit. The check reads only
/// the header and never throws on malformed input.
library;

/// Returns `null` when [bytes] is an accepted WAV, otherwise a short reason.
String? checkWav16kMono16(List<int> bytes) {
  if (bytes.length < 12) return 'too short to be a WAV file';
  if (_ascii(bytes, 0, 4) != 'RIFF') return 'not a RIFF file';
  if (_ascii(bytes, 8, 4) != 'WAVE') return 'not a WAVE file';

  var offset = 12;
  int? fmtAt;
  var hasData = false;
  while (offset + 8 <= bytes.length) {
    final id = _ascii(bytes, offset, 4);
    final size = _u32(bytes, offset + 4);
    if (id == 'fmt ') fmtAt = offset + 8;
    if (id == 'data') hasData = true;
    if (size == null) break;
    // Chunks are word-aligned; an odd size is followed by one pad byte.
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }

  if (fmtAt == null) return 'missing fmt chunk';
  if (!hasData) return 'missing data chunk';
  if (fmtAt + 16 > bytes.length) return 'truncated fmt chunk';

  final audioFormat = _u16(bytes, fmtAt);
  final channels = _u16(bytes, fmtAt + 2);
  final sampleRate = _u32(bytes, fmtAt + 4);
  final bits = _u16(bytes, fmtAt + 14);

  if (audioFormat != 1) return 'not uncompressed PCM';
  if (channels != 1) return 'not mono';
  if (sampleRate != 16000) return 'not 16 kHz';
  if (bits != 16) return 'not 16-bit';
  return null;
}

String _ascii(List<int> b, int at, int length) {
  if (at + length > b.length) return '';
  return String.fromCharCodes(b.sublist(at, at + length));
}

int? _u16(List<int> b, int at) =>
    at + 2 <= b.length ? b[at] | (b[at + 1] << 8) : null;

int? _u32(List<int> b, int at) => at + 4 <= b.length
    ? b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)
    : null;
