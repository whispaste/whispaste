/// Pins the SHA-256 of every Parakeet CPU bundle file.
///
/// The values come from the HuggingFace tree API (`lfs.oid`, which is the
/// SHA-256 of the content) and were cross-checked by downloading the files.
/// A change here must be a deliberate model update, never an accident.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt_parakeet/parakeet_model_registry.dart';

void main() {
  const expected = {
    'encoder.int8.onnx':
        'acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247',
    'decoder.int8.onnx':
        '179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e',
    'joiner.int8.onnx':
        '3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3',
    'tokens.txt':
        'd58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d',
  };

  test(
    'every bundle file has a pinned SHA-256 matching the verified value',
    () {
      expect({
        for (final f in parakeetModelFiles) f.filename: f.sha256,
      }, expected);
    },
  );

  test('pins are lower-case 64-character hex digests', () {
    for (final f in parakeetModelFiles) {
      expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: f.filename);
    }
  });
}
