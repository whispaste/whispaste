/// Applies the automatic level (`speech_leveler.dart`) to a finished capture
/// WAV, once, before anyone reads it (#1611).
///
/// Never loses audio: the leveled copy is written next to the original as
/// `<name>.leveling.wav` and only then renamed over it. Any failure (unknown
/// format, disk full, rename refused) leaves the original file as it was; the
/// copy is removed. A crash between the two steps leaves either the original
/// or the finished copy at the original path, and a stray copy matches the
/// `whispaste_*.wav` sweep of the capture folder.
///
/// The file is never held whole (#1642): one pass measures it and a second
/// writes the copy, 1 MB at a time, so a 60-minute recording (115 MB) costs
/// about as much memory as a short one.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'speech_leveler.dart';

/// Size of the canonical header [WavFileWriter] writes.
const int _headerSize = 44;

/// Files above this size are leveled on a background isolate (about one
/// minute of audio), so a long recording does not stall the UI thread.
const int _isolateThresholdBytes = 2 * 1024 * 1024;

/// Outcome of [levelWavFile].
class WavLevelResult {
  const WavLevelResult({
    required this.boostDb,
    required this.sampleCount,
    required this.fullScaleSamples,
    this.speechDbFs,
    this.error,
  });

  /// Nothing analysed and nothing changed.
  const WavLevelResult.skipped({this.error})
    : boostDb = 0,
      sampleCount = 0,
      fullScaleSamples = 0,
      speechDbFs = null;

  /// Boost written into the file, 0 when it stayed as it was.
  final double boostDb;

  /// Samples analysed.
  final int sampleCount;

  /// Input samples at the int16 limits (the microphone was overdriven).
  final int fullScaleSamples;

  /// Measured speech level before leveling, `null` when no speech was found
  /// or nothing was analysed. Only logged, never shown.
  final double? speechDbFs;

  /// Why the file was left alone, if something went wrong.
  final String? error;

  bool get changed => boostDb > 0;
}

/// Raises the speech level of the WAV at [path] in place, see library doc.
///
/// Only the recorder's own mono 16-bit PCM WAV is touched; any other file is
/// left as it is.
Future<WavLevelResult> levelWavFile(String path) async {
  try {
    final length = await File(path).length();
    if (length > _isolateThresholdBytes) {
      return await Isolate.run(() => _levelWavFileSync(path));
    }
    return _levelWavFileSync(path);
  } on Object catch (e) {
    return WavLevelResult.skipped(error: '$e');
  }
}

/// Bytes read and written per step. The file is never held whole (#1642):
/// one pass measures, a second writes the leveled copy, each through a buffer
/// of this size.
const int _chunkBytes = 1024 * 1024;

WavLevelResult _levelWavFileSync(String path) {
  final original = File(path);
  final SpeechLevelPlan plan;
  final input = original.openSync();
  try {
    final header = Uint8List(_headerSize);
    if (_readFull(input, header) < _headerSize || !isMonoPcm16Wav(header)) {
      return const WavLevelResult.skipped(error: 'not a mono 16-bit PCM WAV');
    }
    final analyzer = SpeechLevelAnalyzer();
    final buffer = Uint8List(_chunkBytes);
    while (true) {
      final read = _readFull(input, buffer);
      if (read <= 0) break;
      analyzer.add(ByteData.sublistView(buffer, 0, read));
    }
    plan = analyzer.finish();
  } finally {
    input.closeSync();
  }
  if (!plan.boosts) {
    return WavLevelResult(
      boostDb: 0,
      sampleCount: plan.sampleCount,
      fullScaleSamples: plan.fullScaleSamples,
      speechDbFs: plan.speechDbFs,
    );
  }

  final copy = File(levelingCopyPath(path));
  try {
    _writeLeveledCopy(original, copy, plan.gain);
    copy.renameSync(path);
  } on Object catch (e) {
    // A leftover copy is removed by the sweep later; the original is what
    // matters, so a failed cleanup is only reported alongside the cause.
    var cleanup = '';
    try {
      if (copy.existsSync()) copy.deleteSync();
    } on Object catch (cleanupError) {
      cleanup = ' (leftover copy not removed: $cleanupError)';
    }
    return WavLevelResult(
      boostDb: 0,
      sampleCount: plan.sampleCount,
      fullScaleSamples: plan.fullScaleSamples,
      speechDbFs: plan.speechDbFs,
      error: '$e$cleanup',
    );
  }
  return WavLevelResult(
    boostDb: plan.boostDb,
    sampleCount: plan.sampleCount,
    fullScaleSamples: plan.fullScaleSamples,
    speechDbFs: plan.speechDbFs,
  );
}

/// Writes [original] with [gain] applied to its PCM into [copy], chunk by
/// chunk. The header is copied as it is; chunks stay sample-aligned, so a
/// trailing odd byte reaches the copy untouched.
void _writeLeveledCopy(File original, File copy, double gain) {
  final input = original.openSync();
  RandomAccessFile? output;
  try {
    output = copy.openSync(mode: FileMode.write);
    final header = Uint8List(_headerSize);
    _readFull(input, header);
    output.writeFromSync(header);
    final buffer = Uint8List(_chunkBytes);
    while (true) {
      final read = _readFull(input, buffer);
      if (read <= 0) break;
      applyGainWithSoftLimit(ByteData.sublistView(buffer, 0, read), gain);
      output.writeFromSync(buffer, 0, read);
    }
    output.flushSync();
  } finally {
    input.closeSync();
    output?.closeSync();
  }
}

/// Fills [buffer] from [file] up to its end; fewer bytes only at the end of
/// the file. Keeps every chunk but the last one sample-aligned even when the
/// system returns a short read.
int _readFull(RandomAccessFile file, Uint8List buffer) {
  var filled = 0;
  while (filled < buffer.length) {
    final read = file.readIntoSync(buffer, filled);
    if (read <= 0) break;
    filled += read;
  }
  return filled;
}

/// Path of the temporary leveled copy of [path].
String levelingCopyPath(String path) {
  final dot = path.toLowerCase().endsWith('.wav') ? path.length - 4 : null;
  final stem = dot == null ? path : path.substring(0, dot);
  return '$stem.leveling.wav';
}

/// Whether [bytes] start with the canonical header of a mono 16-bit PCM WAV,
/// the only shape the recorder writes.
bool isMonoPcm16Wav(Uint8List bytes) {
  if (bytes.length < _headerSize) return false;
  bool tag(int offset, String t) {
    for (var i = 0; i < 4; i++) {
      if (bytes[offset + i] != t.codeUnitAt(i)) return false;
    }
    return true;
  }

  final view = ByteData.sublistView(bytes);
  return tag(0, 'RIFF') &&
      tag(8, 'WAVE') &&
      tag(12, 'fmt ') &&
      tag(36, 'data') &&
      view.getUint16(20, Endian.little) == 1 &&
      view.getUint16(22, Endian.little) == 1 &&
      view.getUint16(34, Endian.little) == 16;
}
