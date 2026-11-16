// Display shaping of the live level (#394).
//
// Business rule: whatever the microphone gain, normal speech uses the whole
// range of a waveform, from rest to full, with visible variance and without
// sticking to either end. Proven on the repository's German speech reference
// (16 kHz mono) at several gains, through the real meter window (40 ms peak)
// and the shared level curve.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/speech_level_mapper.dart';
import 'package:whispaste/services/audio/wave_level_shaper.dart';

/// 40 ms peak dBFS windows of the speech reference, scaled by [gainDb].
List<double> _peakDb(double gainDb) {
  final bytes = File('assets/benchmark/reference-de.wav').readAsBytesSync();
  var i = 12; // after "RIFF....WAVE"
  var dataStart = -1, dataLen = 0;
  final bd = ByteData.sublistView(bytes);
  while (i + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(i, i + 4));
    final len = bd.getUint32(i + 4, Endian.little);
    if (id == 'data') {
      dataStart = i + 8;
      dataLen = math.min(len, bytes.length - dataStart);
      break;
    }
    i += 8 + len;
  }
  expect(dataStart, greaterThan(0));
  const window = 640; // 40 ms at 16 kHz
  final gain = math.pow(10, gainDb / 20).toDouble();
  final out = <double>[];
  for (var s = 0; s + window <= dataLen ~/ 2; s += window) {
    var peak = 0;
    for (var k = 0; k < window; k++) {
      final v = bd.getInt16(dataStart + 2 * (s + k), Endian.little).abs();
      if (v > peak) peak = v;
    }
    out.add(
      peak == 0
          ? double.negativeInfinity
          : 20 * math.log(peak * gain / 32768) / math.ln10,
    );
  }
  return out;
}

List<double> _shaped(double gainDb) {
  const mapper = SpeechLevelMapper();
  final shaper = WaveLevelShaper();
  return [for (final db in _peakDb(gainDb)) shaper.shape(mapper.map(db), 0.04)];
}

double _quantile(List<double> v, double q) {
  final s = [...v]..sort();
  return s[((s.length - 1) * q).round()];
}

void main() {
  for (final gainDb in [0.0, -10.0, -20.0]) {
    test('speech at $gainDb dB gain uses the full range with variance', () {
      final v = _shaped(gainDb);
      expect(_quantile(v, 0.05), lessThan(0.15), reason: 'reaches rest');
      expect(_quantile(v, 0.95), greaterThan(0.75), reason: 'reaches high');
      expect(v.reduce(math.max), greaterThan(0.85), reason: 'peaks to full');
      final mean = v.reduce((a, b) => a + b) / v.length;
      final sd = math.sqrt(
        v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
            v.length,
      );
      expect(sd, greaterThan(0.22), reason: 'loud and soft syllables differ');
      final stuckTop = v.where((x) => x >= 0.97).length / v.length;
      expect(stuckTop, lessThan(0.2), reason: 'does not stick to the top');
    });
  }

  test('the raw curve is the narrow strip the shaper widens', () {
    const mapper = SpeechLevelMapper();
    final raw = [for (final db in _peakDb(-10)) mapper.map(db)];
    final shaped = _shaped(-10);
    final rawSpread = _quantile(raw, 0.95) - _quantile(raw, 0.25);
    final shapedSpread = _quantile(shaped, 0.95) - _quantile(shaped, 0.25);
    expect(shapedSpread, greaterThan(rawSpread));
  });

  test('a quiet and a loud microphone read alike', () {
    final loud = _shaped(0);
    final quiet = _shaped(-20);
    expect(
      (_quantile(loud, 0.75) - _quantile(quiet, 0.75)).abs(),
      lessThan(0.3),
    );
  });

  test('steady room tone stays at rest instead of drifting up', () {
    final shaper = WaveLevelShaper();
    double last = 1;
    for (var i = 0; i < 25 * 60; i++) {
      last = shaper.shape(0.08, 0.04);
    }
    expect(last, lessThan(0.05));
  });

  test('invalid input and time steps are harmless', () {
    final shaper = WaveLevelShaper();
    expect(shaper.shape(double.nan, double.nan), 0);
    expect(shaper.shape(2, -1), inInclusiveRange(0.0, 1.0));
    shaper.reset();
    expect(shaper.reference, WaveLevelShaper.initialReference);
  });
}
