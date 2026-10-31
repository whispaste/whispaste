/// Finds pauses in 16 kHz mono 16-bit little-endian PCM without copying it.
///
/// Long uploads are cut where nobody is speaking (see `openai_transcriber.dart`).
/// The finder reads straight from a [ByteData] view over the recording, so a
/// 60-minute recording costs no extra memory.
library;

import 'dart:typed_data';

/// Samples per analysis frame: 20 ms at 16 kHz, as in the Whisper pause split.
const int pcm16FrameSamples = 320;

/// Bytes per 16-bit sample.
const int _bytesPerSample = 2;

/// Frame RMS below this (samples normalised to `[-1, 1]`) counts as silence.
/// Same threshold as the local Whisper pause split.
const double pcm16SilenceRms = 0.015;

/// Shortest silent run that counts as a pause: 700 ms, i.e. 35 frames.
const int pcm16MinPauseFrames = 35;

/// Byte offset into [pcm] of the middle of the latest pause that lies entirely
/// inside `[fromByte, toByte)`, or `null` when the range holds no such pause.
///
/// [pcm] holds PCM samples only (no WAV header). [fromByte] and [toByte] must
/// be even, so that the returned cut lands on a sample boundary.
int? findLatestPauseMidByte(
  ByteData pcm,
  int fromByte,
  int toByte, {
  double silenceRms = pcm16SilenceRms,
  int minPauseFrames = pcm16MinPauseFrames,
}) {
  const frameBytes = pcm16FrameSamples * _bytesPerSample;
  final frameCount = (toByte - fromByte) ~/ frameBytes;
  if (frameCount <= 0) return null;

  // Squared-sum threshold on the int16 scale, so no per-sample division.
  final silentLevel = silenceRms * 32768;
  final silentSumSquares = silentLevel * silentLevel * pcm16FrameSamples;

  int? bestMid;
  var runStart = -1;
  for (var f = 0; f <= frameCount; f++) {
    var isSilent = false;
    if (f < frameCount) {
      final base = fromByte + f * frameBytes;
      var sumSquares = 0;
      for (var s = 0; s < pcm16FrameSamples; s++) {
        final v = pcm.getInt16(base + s * _bytesPerSample, Endian.little);
        sumSquares += v * v;
      }
      isSilent = sumSquares < silentSumSquares;
    }
    if (isSilent) {
      if (runStart == -1) runStart = f;
    } else if (runStart != -1) {
      final runLength = f - runStart;
      if (runLength >= minPauseFrames) {
        // Later pauses win: the longer the slice, the fewer the uploads.
        bestMid = fromByte + (runStart + runLength ~/ 2) * frameBytes;
      }
      runStart = -1;
    }
  }
  return bestMid;
}
