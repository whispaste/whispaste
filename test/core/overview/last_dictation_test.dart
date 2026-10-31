import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/overview/last_dictation.dart';

void main() {
  group('LastDictation stored form', () {
    test('round-trips every processing kind', () {
      for (final processing in DictationProcessing.values) {
        for (final fellBack in [true, false]) {
          final value = LastDictation(
            processing: processing,
            fellBack: fellBack,
            processingMs: 1234,
          );
          final decoded = LastDictation.decode(value.encode());
          expect(decoded?.processing, processing);
          expect(decoded?.fellBack, fellBack);
          expect(decoded?.processingMs, 1234);
        }
      }
    });

    test('damaged or unknown values decode to nothing', () {
      expect(LastDictation.decode(null), isNull);
      expect(LastDictation.decode(''), isNull);
      expect(LastDictation.decode('v2|gpu|0|10'), isNull);
      expect(LastDictation.decode('v1|tpu|0|10'), isNull);
      expect(LastDictation.decode('v1|gpu|0|-5'), isNull);
      expect(LastDictation.decode('v1|gpu|0|abc'), isNull);
      expect(LastDictation.decode('v1|gpu|0'), isNull);
    });
  });

  group('whisperGpuWanted', () {
    test(
      'wants the GPU only with a GPU backend and the setting allowing it',
      () {
        expect(
          whisperGpuWanted(optimalBackend: 'metal', gpuAcceleration: 'auto'),
          isTrue,
        );
        expect(
          whisperGpuWanted(optimalBackend: 'vulkan', gpuAcceleration: null),
          isTrue,
        );
        expect(
          whisperGpuWanted(optimalBackend: 'cuda', gpuAcceleration: 'disabled'),
          isFalse,
        );
        expect(
          whisperGpuWanted(optimalBackend: 'cpu', gpuAcceleration: 'auto'),
          isFalse,
        );
        expect(
          whisperGpuWanted(optimalBackend: null, gpuAcceleration: 'auto'),
          isFalse,
        );
      },
    );
  });

  group('resolveLocalProcessing', () {
    test('GPU active is GPU without fallback', () {
      final r = resolveLocalProcessing(gpuWanted: true, gpuActive: true);
      expect(r.processing, DictationProcessing.gpu);
      expect(r.fellBack, isFalse);
    });

    test('GPU wanted but CPU used is a fallback', () {
      final r = resolveLocalProcessing(gpuWanted: true, gpuActive: false);
      expect(r.processing, DictationProcessing.cpu);
      expect(r.fellBack, isTrue);
    });

    test('CPU by choice is not a fallback', () {
      final r = resolveLocalProcessing(gpuWanted: false, gpuActive: false);
      expect(r.processing, DictationProcessing.cpu);
      expect(r.fellBack, isFalse);
    });
  });
}
