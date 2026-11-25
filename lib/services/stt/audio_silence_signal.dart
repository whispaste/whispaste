/// The audio half of the [SilenceSignal] (#2013): whether a recording holds
/// any voice at all, and how long it is silent at the end.
///
/// Engine-independent, so the orchestrator can pass it for whisper,
/// Parakeet and the cloud engines alike. Reads the PCM backwards in blocks
/// and stops at the first loud frame, so a normal dictation costs a few
/// frames only; an entirely silent recording is read once.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/pcm16_pause_finder.dart'
    show pcm16FrameSamples, pcm16SilenceRms;
import '../audio/pcm_wav_codec.dart' show Pcm16WavView;
import 'transcript_hallucination_filter.dart' show SilenceSignal;

/// Peak level a frame must reach to count as voice: about -49 dBFS, the
/// threshold of the live speech meter (`speech_presence.dart`). Room tone
/// stays below it. Deliberately low: [SilenceSignal.silentAudio] is strong
/// evidence and must not fire for a quiet microphone.
const double kVoicePeakLevel = 0.00355;

/// Measures [pcm] (16 kHz mono 16-bit). A recording shorter than one frame
/// yields [SilenceSignal.none]: there is nothing to judge.
SilenceSignal audioSilenceSignal(Pcm16WavView pcm, {int sampleRate = 16000}) {
  final frameCount = pcm.sampleCount ~/ pcm16FrameSamples;
  if (frameCount == 0) return SilenceSignal.none;

  final peakLimit = (kVoicePeakLevel * 32768).round();
  const pauseLevel = pcm16SilenceRms * 32768;
  const pauseSumSquares = pauseLevel * pauseLevel * pcm16FrameSamples;

  var voiceSeen = false;
  var silentFrames = 0;
  const blockFrames = 64;
  var end = frameCount;
  scan:
  while (end > 0) {
    final start = math.max(0, end - blockFrames);
    final data = pcm.pcmBytes(
      start * pcm16FrameSamples,
      end * pcm16FrameSamples,
    );
    for (var f = end - start - 1; f >= 0; f--) {
      var sumSquares = 0;
      var peak = 0;
      final base = f * pcm16FrameSamples * 2;
      for (var s = 0; s < pcm16FrameSamples; s++) {
        final v = data.getInt16(base + s * 2, Endian.little);
        sumSquares += v * v;
        final a = v < 0 ? -v : v;
        if (a > peak) peak = a;
      }
      if (peak >= peakLimit) voiceSeen = true;
      // A frame above the pause level is always above the voice peak, so
      // [voiceSeen] is settled once the trailing silence ends.
      if (sumSquares >= pauseSumSquares) break scan;
      silentFrames++;
    }
    end = start;
  }

  return SilenceSignal(
    silentAudio: !voiceSeen,
    trailingSilenceMs: silentFrames * pcm16FrameSamples * 1000 ~/ sampleRate,
  );
}

/// [audioSilenceSignal] over the PCM inside [wavBytes]. Never throws: a
/// recording that cannot be read carries no evidence.
SilenceSignal audioSilenceSignalOfWav(List<int> wavBytes) {
  try {
    return audioSilenceSignal(Pcm16WavView(wavBytes));
  } on Object {
    return SilenceSignal.none;
  }
}
