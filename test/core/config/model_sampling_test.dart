import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/config/model_sampling.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/settings/widgets/model_sampling_dialog.dart'
    show parseSamplingInput;

/// A minimal GGUF v3 header with [kv] (key → (type, value)).
Uint8List _gguf(List<(String, int, Object)> kv) {
  final b = BytesBuilder();
  void u32(int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u64(int v) =>
      b.add((ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List());
  void str(String s) {
    final bytes = utf8.encode(s);
    u64(bytes.length);
    b.add(bytes);
  }

  u32(0x46554747);
  u32(3);
  u64(0);
  u64(kv.length);
  for (final (key, type, value) in kv) {
    str(key);
    u32(type);
    switch (type) {
      case 4:
        u32(value as int);
      case 6:
        b.add(
          (ByteData(4)..setFloat32(0, value as double, Endian.little)).buffer
              .asUint8List(),
        );
      case 8:
        str(value as String);
      case 9:
        // array of strings, like a tokenizer vocabulary
        final items = value as List<String>;
        u32(8);
        u64(items.length);
        items.forEach(str);
    }
  }
  return b.toBytes();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('model_sampling_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String write(Uint8List bytes) {
    final path = p.join(tmp.path, 'm.gguf');
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  group('GGUF general.sampling.* (#2204)', () {
    test('reads the vendor values next to other keys and arrays', () {
      final path = write(
        _gguf([
          ('general.architecture', 8, 'gemma3'),
          ('tokenizer.ggml.tokens', 9, ['a', 'b', 'c']),
          ('general.sampling.temp', 6, 1.0),
          ('general.sampling.top_k', 4, 64),
          ('general.sampling.top_p', 6, 0.95),
          ('general.sampling.min_p', 6, 0.0),
          ('tokenizer.chat_template', 8, '{{x}}'),
        ]),
      );
      final rec = readGgufSampling(path)!;
      expect(rec.values.temperature, 1.0);
      expect(rec.values.topK, 64);
      expect(rec.values.topP, closeTo(0.95, 1e-6));
      expect(rec.values.minP, 0);
      expect(rec.keys, {'temperature', 'top_k', 'top_p', 'min_p'});
    });

    test('no sampling keys, a broken file or a missing file give null', () {
      expect(
        readGgufSampling(write(_gguf([('general.architecture', 8, 'x')]))),
        isNull,
      );
      expect(readGgufSampling(write(Uint8List.fromList([1, 2, 3]))), isNull);
      expect(readGgufSampling(p.join(tmp.path, 'none.gguf')), isNull);
    });

    test('out-of-range vendor values are ignored, not clamped', () {
      final rec = recommendationFrom({'temperature': 7, 'top_k': 40});
      expect(rec!.keys, {'top_k'});
      expect(rec.values.temperature, SmartModeSampling.whispaste.temperature);
      expect(recommendationFrom({'top_p': 0}), isNull);
      expect(recommendationFrom({'top_k': 2.5}), isNull);
    });
  });

  group('precedence of the effective values', () {
    const vendor = SamplingRecommendation(
      values: SmartModeSampling(temperature: 1, topK: 64, topP: 0.95),
      keys: {'temperature'},
    );

    test('catalog and own models without a choice keep WhisPaste values', () {
      expect(effectiveSampling(null, vendor), SmartModeSampling.whispaste);
      expect(
        SmartModeSampling.whispaste,
        const SmartModeSampling(temperature: 0.3, topK: 64, topP: 0.95),
      );
      expect(SmartModeSampling.whispaste.minP, 0);
      expect(SmartModeSampling.whispaste.repeatPenalty, 1);
    });

    test('vendor applies the recommendation, without one WhisPaste', () {
      const choice = ModelSamplingChoice(preset: SamplingPreset.vendor);
      expect(effectiveSampling(choice, vendor), vendor.values);
      expect(effectiveSampling(choice, null), SmartModeSampling.whispaste);
    });

    test('custom uses the stored values, clamped', () {
      const choice = ModelSamplingChoice(
        preset: SamplingPreset.custom,
        custom: SmartModeSampling(temperature: 9, topK: 10, topP: 0.5),
      );
      final v = effectiveSampling(choice, vendor);
      expect(v.temperature, SamplingRange.temperature.max);
      expect(v.topK, 10);
    });
  });

  group('range validation of typed values', () {
    test('accepts numbers in range, comma or point', () {
      expect(parseSamplingInput('0,7', SamplingRange.temperature), 0.7);
      expect(parseSamplingInput('1.1', SamplingRange.repeatPenalty), 1.1);
      expect(parseSamplingInput('40', SamplingRange.topK, whole: true), 40);
    });

    test('rejects out-of-range, non-numbers and fractions for top-k', () {
      expect(parseSamplingInput('2.5', SamplingRange.temperature), isNull);
      expect(parseSamplingInput('abc', SamplingRange.topP), isNull);
      expect(parseSamplingInput('0.9', SamplingRange.repeatPenalty), isNull);
      expect(
        parseSamplingInput('4.5', SamplingRange.topK, whole: true),
        isNull,
      );
    });
  });

  group('per-model persistence', () {
    test('round-trips through the settings storage map', () {
      const s = SmartModeSettings(
        modelSampling: {
          'gemma': ModelSamplingChoice(preset: SamplingPreset.vendor),
          'user-ab12': ModelSamplingChoice(
            preset: SamplingPreset.custom,
            custom: SmartModeSampling(
              temperature: 0.5,
              topK: 40,
              topP: 0.9,
              minP: 0.05,
              repeatPenalty: 1.1,
            ),
          ),
        },
      );
      final back = SmartModeSettings.fromMap(s.toMap());
      expect(back, s);
      expect(back.modelSampling['user-ab12']!.custom!.minP, 0.05);
    });

    test('missing or damaged JSON means no choice (WhisPaste values)', () {
      expect(SmartModeSettings.fromMap(const {}).modelSampling, isEmpty);
      expect(modelSamplingFromJson('{nope'), isEmpty);
      expect(
        SmartModeSettings.defaults.toMap()['smart_mode_model_sampling'],
        '',
      );
    });
  });
}
