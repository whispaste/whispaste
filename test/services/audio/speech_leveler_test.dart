/// Automatic level of a finished recording (#1611): speech is raised to about
/// -20 dBFS, at most +24 dB, never lowered, peaks stay at or below -1 dBFS,
/// silence and pure noise stay as they are.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/speech_leveler.dart';

/// Ceiling of the limiter in int16 units (-1 dBFS).
final double _ceiling = 32767 * math.pow(10, -1 / 20).toDouble();

/// Speech-like PCM: 300 ms tone bursts at [speechDbFs] RMS, separated by
/// 200 ms of uniform noise of amplitude [noise] (0 = digital silence).
ByteData _speech({
  required double speechDbFs,
  int noise = 20,
  int bursts = 6,
  int seed = 1,
}) {
  final random = math.Random(seed);
  final amplitude = 32768 * math.pow(10, speechDbFs / 20) * math.sqrt2;
  final samples = <int>[];
  for (var b = 0; b < bursts; b++) {
    for (var i = 0; i < 3200; i++) {
      samples.add(noise == 0 ? 0 : random.nextInt(2 * noise + 1) - noise);
    }
    for (var i = 0; i < 4800; i++) {
      samples.add(
        (amplitude * math.sin(2 * math.pi * 220 * i / 16000)).round(),
      );
    }
  }
  return _pcm(samples);
}

ByteData _pcm(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data;
}

/// RMS in dBFS of the samples whose frames are louder than [aboveDbFs].
double _speechRmsDbFs(ByteData pcm, {double aboveDbFs = -60}) {
  var sum = 0.0;
  var count = 0;
  for (var f = 0; f + 320 <= pcm.lengthInBytes ~/ 2; f += 320) {
    var frame = 0.0;
    for (var s = 0; s < 320; s++) {
      final v = pcm.getInt16((f + s) * 2, Endian.little);
      frame += v * v;
    }
    final db = 10 * math.log(frame / 320 / (32768 * 32768)) / math.ln10;
    if (db > aboveDbFs) {
      sum += frame;
      count += 320;
    }
  }
  return 10 * math.log(sum / count / (32768 * 32768)) / math.ln10;
}

int _peak(ByteData pcm) {
  var peak = 0;
  for (var i = 0; i < pcm.lengthInBytes ~/ 2; i++) {
    peak = math.max(peak, pcm.getInt16(i * 2, Endian.little).abs());
  }
  return peak;
}

void main() {
  group('analyzeSpeechLevel', () {
    test('quiet speech is raised to about -20 dBFS', () {
      final pcm = _speech(speechDbFs: -40);
      final plan = analyzeSpeechLevel(pcm);
      expect(plan.boostDb, closeTo(20, 0.5));

      applyGainWithSoftLimit(pcm, plan.gain);
      expect(
        _speechRmsDbFs(pcm, aboveDbFs: -35),
        closeTo(levelTargetDbFs, 0.5),
      );
    });

    test('the boost stops at +24 dB', () {
      final plan = analyzeSpeechLevel(_speech(speechDbFs: -55, noise: 2));
      expect(plan.boostDb, closeTo(levelMaxBoostDb, 0.01));
    });

    test('the noise floor is never lifted above -40 dBFS', () {
      // Speech at -38 dBFS wants +18 dB; uniform noise of amplitude 100
      // (about -55 dBFS) allows only about +15 dB.
      final plan = analyzeSpeechLevel(_speech(speechDbFs: -38, noise: 100));
      final floor = plan.noiseFloorDbFs!;
      expect(plan.boosts, isTrue);
      expect(floor + plan.boostDb, lessThanOrEqualTo(-40 + 0.01));
      expect(plan.boostDb, lessThan(17));
    });

    test('loud speech is never lowered', () {
      final plan = analyzeSpeechLevel(_speech(speechDbFs: -12));
      expect(plan.gain, 1.0);
      expect(plan.boosts, isFalse);
    });

    test('digital silence stays as it is', () {
      final plan = analyzeSpeechLevel(_pcm(List<int>.filled(32000, 0)));
      expect(plan.gain, 1.0);
    });

    test('pure noise is not amplified', () {
      final random = math.Random(3);
      final noise = [for (var i = 0; i < 48000; i++) random.nextInt(601) - 300];
      expect(analyzeSpeechLevel(_pcm(noise)).gain, 1.0);
    });

    test('speech between digitally silent gaps is still leveled', () {
      final plan = analyzeSpeechLevel(_speech(speechDbFs: -40, noise: 0));
      expect(plan.boostDb, closeTo(20, 0.5));
    });

    test('digital silence at the start does not lift the room noise '
        '(waking microphone, #1777)', () {
      // Quiet room noise (about -46 dBFS RMS) between speech at -30 dBFS:
      // the noise-floor cap limits the boost.
      final noisy = _speech(speechDbFs: -30, noise: 300);
      final withoutStart = analyzeSpeechLevel(noisy);
      expect(withoutStart.boostDb, lessThan(8));

      // The same recording after 0.6 s of digital zeros from a microphone
      // that was still waking up gets the same boost, not a larger one.
      final samples = List<int>.filled(9600, 0, growable: true);
      for (var i = 0; i < noisy.lengthInBytes ~/ 2; i++) {
        samples.add(noisy.getInt16(i * 2, Endian.little));
      }
      final withStart = analyzeSpeechLevel(_pcm(samples));
      expect(withStart.boostDb, closeTo(withoutStart.boostDb, 0.5));
    });

    test('a recording shorter than 200 ms stays as it is', () {
      final short = _speech(speechDbFs: -40, bursts: 1);
      final pcm = ByteData.sublistView(short, 0, 3000 * 2);
      expect(analyzeSpeechLevel(pcm).gain, 1.0);
    });

    test('loud peaks cap the boost so they stay at or below -1 dBFS', () {
      final samples = <int>[];
      final speech = _speech(speechDbFs: -40);
      for (var i = 0; i < speech.lengthInBytes ~/ 2; i++) {
        samples.add(speech.getInt16(i * 2, Endian.little));
      }
      // Loud clicks (about -4 dBFS) inside the speech, 0.6 % of all samples.
      for (var i = 0; i < samples.length; i += 100) {
        if (i % 8000 >= 3200) samples[i] = 20000;
      }
      final pcm = _pcm(samples);
      final plan = analyzeSpeechLevel(pcm);
      expect(plan.boostDb, lessThan(20));
      expect(plan.boostDb, greaterThan(0));

      applyGainWithSoftLimit(pcm, plan.gain);
      expect(_peak(pcm), lessThanOrEqualTo(_ceiling.ceil()));
    });

    test('counts samples at the int16 limits as overdriven input', () {
      final plan = analyzeSpeechLevel(
        _pcm([...List<int>.filled(3200, 100), 32767, -32768, 32767]),
      );
      expect(plan.fullScaleSamples, 3);
      expect(plan.sampleCount, 3203);
    });
  });

  group('softLimitSample', () {
    test('passes quiet samples unchanged', () {
      expect(softLimitSample(1000), 1000);
      expect(softLimitSample(-15000), -15000);
    });

    test('bends loud samples below the ceiling instead of cutting them', () {
      final a = softLimitSample(30000);
      final b = softLimitSample(60000);
      final c = softLimitSample(300000);
      expect(a, lessThan(b));
      expect(b, lessThan(c));
      expect(c, lessThanOrEqualTo(_ceiling));
      expect(softLimitSample(-300000), greaterThanOrEqualTo(-_ceiling));
    });
  });

  group('applyGainWithSoftLimit', () {
    test('counts samples that would have left the int16 range', () {
      final pcm = _pcm([1000, 20000, -20000, 0]);
      final overdriven = applyGainWithSoftLimit(pcm, 4);
      expect(overdriven, 2);
      expect(pcm.getInt16(0, Endian.little), 4000);
      expect(
        pcm.getInt16(2, Endian.little),
        inInclusiveRange(20000, _ceiling.ceil()),
      );
      expect(
        pcm.getInt16(4, Endian.little),
        inInclusiveRange(-_ceiling.ceil(), -20000),
      );
    });
  });

  group('SpeechLevelAnalyzer (#1642, pieces instead of the whole file)', () {
    void expectSamePlan(SpeechLevelPlan a, SpeechLevelPlan b) {
      expect(a.gain, b.gain);
      expect(a.sampleCount, b.sampleCount);
      expect(a.fullScaleSamples, b.fullScaleSamples);
      expect(a.speechDbFs, b.speechDbFs);
      expect(a.noiseFloorDbFs, b.noiseFloorDbFs);
    }

    SpeechLevelPlan inPieces(ByteData pcm, int pieceBytes) {
      final analyzer = SpeechLevelAnalyzer();
      for (var o = 0; o < pcm.lengthInBytes; o += pieceBytes) {
        final end = math.min(o + pieceBytes, pcm.lengthInBytes);
        analyzer.add(ByteData.sublistView(pcm, o, end));
      }
      return analyzer.finish();
    }

    test('any split gives the plan of one pass, also mid-sample', () {
      final pcm = _speech(speechDbFs: -38, bursts: 12);
      final whole = analyzeSpeechLevel(pcm);
      expect(whole.boosts, isTrue);
      // Odd sizes cut samples and frames apart.
      for (final piece in [1, 3, 641, 4097, 1 << 20]) {
        expectSamePlan(inPieces(pcm, piece), whole);
      }
    });

    test('a trailing odd byte is ignored as in one pass', () {
      final pcm = _speech(speechDbFs: -38);
      final odd = ByteData(pcm.lengthInBytes + 1);
      for (var i = 0; i < pcm.lengthInBytes; i++) {
        odd.setUint8(i, pcm.getUint8(i));
      }
      odd.setUint8(pcm.lengthInBytes, 0x7f);
      expectSamePlan(inPieces(odd, 999), analyzeSpeechLevel(odd));
      expect(inPieces(odd, 999).sampleCount, pcm.lengthInBytes ~/ 2);
    });

    test('negative samples split across pieces keep their sign', () {
      final pcm = _pcm([for (var i = 0; i < 4000; i++) i.isEven ? -32768 : -1]);
      expectSamePlan(inPieces(pcm, 3), analyzeSpeechLevel(pcm));
      expect(inPieces(pcm, 3).fullScaleSamples, 2000);
    });
  });
}
