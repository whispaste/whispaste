/// Pure helper for trimming a growing raw-PCM buffer down to a fixed
/// trailing time window.
///
/// Used by the live-transcript-during-recording preview
/// (`live_transcript_previewer.dart`): the app keeps the FULL captured PCM
/// for the final, unchanged batch decode (see `WavFileWriter`), but the
/// intermediate preview decode must only ever look at the last ~20-30 s —
/// otherwise its own decode time keeps growing for the rest of a long
/// dictation. Pure and allocation-light so it is trivially unit-testable
/// without any audio/FFI dependency.
library;

import 'dart:typed_data';

/// Returns the trailing slice of [buffer] (16-bit PCM, little-endian, mono)
/// covering at most [windowSeconds] seconds at [sampleRate] Hz, dropping any
/// older bytes. Returns [buffer] unchanged (same instance) if it is already
/// within the window.
///
/// The cut point is aligned to whole samples ([bytesPerSample] bytes each)
/// so a trim can never split a sample in half.
Uint8List trimPcmToWindow(
  Uint8List buffer, {
  required int sampleRate,
  required double windowSeconds,
  int bytesPerSample = 2,
}) {
  if (sampleRate <= 0 || windowSeconds <= 0) return buffer;

  final maxBytesRaw = (sampleRate * windowSeconds * bytesPerSample).round();
  final maxBytes = maxBytesRaw - (maxBytesRaw % bytesPerSample);
  if (maxBytes <= 0 || buffer.length <= maxBytes) return buffer;

  return Uint8List.sublistView(buffer, buffer.length - maxBytes);
}
