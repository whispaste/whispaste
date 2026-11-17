/// Automatic level for a finished recording (#1611): lifts quiet speech to a
/// steady level before the WAV goes to recognition, the saved file and
/// "Anhören".
///
/// Pure data: no I/O, no Riverpod. The input is 16-bit mono little-endian
/// PCM (no WAV header). `wav_leveler.dart` applies it to the finished file.
///
/// Rules (issue #1611):
/// - Speech is raised to about [levelTargetDbFs] RMS, by at most
///   [levelMaxBoostDb]. The level is never lowered.
/// - Peaks stay at or below [levelCeilingDbFs]: the gain is capped so nearly
///   all samples fit, and [softLimitSample] bends the rest instead of cutting
///   them off.
/// - Silence and pure noise are not raised: without frames clearly above the
///   noise floor there is no speech to level. The noise floor itself is never
///   lifted above [levelMaxNoiseFloorDbFs], which keeps pauses quiet enough
///   for the pause split of long uploads (`pcm16_pause_finder.dart`).
/// - Digital silence at the very start is the microphone waking up, not the
///   room (#1777): it is left out of the analysis. Counted, it set the noise
///   floor to digital zero, so the cap above no longer held and the room
///   noise of the rest was raised with the speech.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Speech level the leveler aims for, as RMS of the speech frames.
const double levelTargetDbFs = -20;

/// Largest boost the leveler applies.
const double levelMaxBoostDb = 24;

/// Highest peak after leveling.
const double levelCeilingDbFs = -1;

/// Highest noise floor after leveling. Below the pause threshold of the long
/// upload split (`pcm16SilenceRms`, about -36.5 dBFS).
const double levelMaxNoiseFloorDbFs = -40;

/// Boosts smaller than this are not worth rewriting the file for.
const double levelMinBoostDb = 0.5;

/// Frame length of the analysis: 20 ms at 16 kHz.
const int _frameSamples = 320;

/// A frame counts as speech when it is this far above the noise floor.
const double _speechAboveFloorDb = 10;

/// Speech frames below this absolute level are not speech (a dead input).
const double _speechMinDbFs = -60;

/// Fewest speech frames (160 ms) that make a level worth estimating.
const int _minSpeechFrames = 8;

/// Fewest frames (200 ms) a recording needs before it is analysed at all.
const int _minFrames = 10;

/// Share of samples allowed above the ceiling before the gain is capped.
const double _peakQuantile = 0.999;

/// Full-scale int16 magnitude used for dBFS.
const double _fullScale = 32768;

/// Output ceiling in int16 units.
final double _ceiling = 32767 * math.pow(10, levelCeilingDbFs / 20).toDouble();

/// Samples up to this magnitude pass the limiter unchanged (about -4 dBFS).
final double _knee = _ceiling * 0.7;

/// Converts a gain in dB into a linear factor.
double dbToGain(double db) => math.pow(10, db / 20).toDouble();

/// Converts a linear factor into dB. `-inf` for a factor of 0 or less.
double gainToDb(double gain) =>
    gain <= 0 ? double.negativeInfinity : 20 * math.log(gain) / math.ln10;

/// Soft limiter for one sample on the int16 scale.
///
/// Up to the knee the sample passes unchanged; above it the magnitude bends
/// smoothly towards the ceiling (-1 dBFS) and never reaches it. Replaces the
/// hard cut at the int16 limits, which sounded like crackle.
double softLimitSample(double x) {
  final magnitude = x.abs();
  if (magnitude <= _knee) return x;
  final room = _ceiling - _knee;
  final bent = _knee + room * _tanh((magnitude - _knee) / room);
  return x < 0 ? -bent : bent;
}

double _tanh(double v) {
  if (v > 20) return 1;
  final e = math.exp(2 * v);
  return (e - 1) / (e + 1);
}

/// Rounds a limited sample into the int16 range.
int _toInt16(double v) {
  final r = v.round();
  if (r > 32767) return 32767;
  if (r < -32768) return -32768;
  return r;
}

/// Outcome of [analyzeSpeechLevel].
class SpeechLevelPlan {
  const SpeechLevelPlan({
    required this.gain,
    required this.sampleCount,
    required this.fullScaleSamples,
    this.speechDbFs,
    this.noiseFloorDbFs,
  });

  /// Linear gain to apply; exactly `1.0` when the recording stays as it is.
  final double gain;

  /// Samples analysed.
  final int sampleCount;

  /// Samples at the int16 limits in the input: the microphone itself was
  /// driven too hard. Feeds the "too loud" hint.
  final int fullScaleSamples;

  /// RMS level of the speech frames, `null` when no speech was found.
  final double? speechDbFs;

  /// Noise floor (the quietest frames), `null` for too short recordings.
  final double? noiseFloorDbFs;

  /// Whether the recording gets louder.
  bool get boosts => gain > 1.0;

  /// Applied boost in dB (0 when nothing changes).
  double get boostDb => boosts ? gainToDb(gain) : 0;
}

/// Decides how much to raise the PCM in [pcm] (16-bit mono LE, no header).
SpeechLevelPlan analyzeSpeechLevel(ByteData pcm) =>
    (SpeechLevelAnalyzer()..add(pcm)).finish();

/// [analyzeSpeechLevel] in pieces (#1642): a long recording is read from disk
/// chunk by chunk instead of being held whole. Feeding the PCM in any split
/// gives exactly the plan of one [analyzeSpeechLevel] call over all of it.
class SpeechLevelAnalyzer {
  /// Magnitude histogram for the peak quantile: one pass, no sort.
  final Uint32List _histogram = Uint32List(32769);
  Float64List _frameMeanSquares = Float64List(1024);
  int _frameCount = 0;
  int _sampleCount = 0;
  int _fullScale = 0;

  /// Sum and sample count of the frame not yet complete.
  double _frameSum = 0;
  int _frameFill = 0;

  /// Whether a frame with any sound was seen. Digitally silent frames before
  /// it are the device start-up and are not analysed (#1777).
  bool _soundSeen = false;

  /// The low byte of a sample split across two [add] calls.
  int? _pendingByte;
  bool _finished = false;

  /// Adds the next piece of PCM (16-bit mono LE). A piece may end in the
  /// middle of a sample; the next one continues it.
  void add(ByteData pcm) {
    if (_finished) throw StateError('analyzer already finished');
    var offset = 0;
    final length = pcm.lengthInBytes;
    final pending = _pendingByte;
    if (pending != null && length > 0) {
      final raw = pending | (pcm.getUint8(0) << 8);
      _addSample(raw >= 0x8000 ? raw - 0x10000 : raw);
      _pendingByte = null;
      offset = 1;
    }
    while (offset + 1 < length) {
      _addSample(pcm.getInt16(offset, Endian.little));
      offset += 2;
    }
    if (offset < length) _pendingByte = pcm.getUint8(offset);
  }

  void _addSample(int v) {
    _sampleCount++;
    final m = v.abs();
    _histogram[m]++;
    if (m >= 32767) _fullScale++;
    _frameSum += v * v;
    if (++_frameFill == _frameSamples) {
      if (!_soundSeen && _frameSum == 0) {
        _frameFill = 0;
        return;
      }
      _soundSeen = true;
      if (_frameCount == _frameMeanSquares.length) {
        _frameMeanSquares = Float64List(_frameCount * 2)
          ..setAll(0, _frameMeanSquares);
      }
      _frameMeanSquares[_frameCount++] = _frameSum / _frameSamples;
      _frameSum = 0;
      _frameFill = 0;
    }
  }

  /// The plan for everything added so far. Samples after the last full frame
  /// count for the peaks, not for the frame levels.
  SpeechLevelPlan finish() {
    _finished = true;
    return _plan(
      Float64List.sublistView(_frameMeanSquares, 0, _frameCount),
      _histogram,
      _sampleCount,
      _fullScale,
    );
  }
}

SpeechLevelPlan _plan(
  Float64List frameMeanSquares,
  Uint32List histogram,
  int sampleCount,
  int fullScale,
) {
  final frameCount = frameMeanSquares.length;
  SpeechLevelPlan unchanged({double? speech, double? floor}) => SpeechLevelPlan(
    gain: 1.0,
    sampleCount: sampleCount,
    fullScaleSamples: fullScale,
    speechDbFs: speech,
    noiseFloorDbFs: floor,
  );

  if (frameCount < _minFrames) return unchanged();

  // Frame levels in dBFS. Digital silence (a noise gate, a muted start)
  // counts as the lowest level, so it marks the floor instead of hiding it.
  final sorted = <double>[for (final ms in frameMeanSquares) _frameDbFs(ms)]
    ..sort();
  final floor = sorted[(sorted.length * 0.15).floor()];

  final threshold = math.max(floor + _speechAboveFloorDb, _speechMinDbFs);
  var speechSum = 0.0;
  var speechFrames = 0;
  for (final ms in frameMeanSquares) {
    if (ms > 0 && _meanSquareToDbFs(ms) >= threshold) {
      speechSum += ms;
      speechFrames++;
    }
  }
  if (speechFrames < _minSpeechFrames) return unchanged(floor: floor);
  final speech = _meanSquareToDbFs(speechSum / speechFrames);

  var boostDb = levelTargetDbFs - speech;
  boostDb = math.min(boostDb, levelMaxBoostDb);
  boostDb = math.min(boostDb, levelMaxNoiseFloorDbFs - floor);
  final peak = _quantileMagnitude(histogram, sampleCount, _peakQuantile);
  if (peak > 0) {
    boostDb = math.min(boostDb, gainToDb(_ceiling / peak));
  }
  if (boostDb < levelMinBoostDb) return unchanged(speech: speech, floor: floor);
  return SpeechLevelPlan(
    gain: dbToGain(boostDb),
    sampleCount: sampleCount,
    fullScaleSamples: fullScale,
    speechDbFs: speech,
    noiseFloorDbFs: floor,
  );
}

/// Level given to a digitally silent frame.
const double _silentFrameDbFs = -120;

double _frameDbFs(double meanSquare) =>
    meanSquare > 0 ? _meanSquareToDbFs(meanSquare) : _silentFrameDbFs;

double _meanSquareToDbFs(double meanSquare) =>
    10 * math.log(meanSquare / (_fullScale * _fullScale)) / math.ln10;

/// Smallest magnitude that at least [quantile] of all samples stay at or below.
int _quantileMagnitude(Uint32List histogram, int total, double quantile) {
  if (total == 0) return 0;
  final wanted = (total * quantile).ceil();
  var seen = 0;
  for (var m = 0; m < histogram.length; m++) {
    seen += histogram[m];
    if (seen >= wanted) return m;
  }
  return histogram.length - 1;
}

/// Multiplies the 16-bit samples in [pcm] by [gain] in place and passes each
/// through [softLimitSample]. Returns how many samples would have left the
/// int16 range without the limiter. A trailing odd byte stays untouched.
int applyGainWithSoftLimit(ByteData pcm, double gain) {
  final sampleCount = pcm.lengthInBytes ~/ 2;
  var overdriven = 0;
  for (var i = 0; i < sampleCount; i++) {
    final scaled = pcm.getInt16(i * 2, Endian.little) * gain;
    if (scaled > 32767 || scaled < -32768) overdriven++;
    pcm.setInt16(i * 2, _toInt16(softLimitSample(scaled)), Endian.little);
  }
  return overdriven;
}
