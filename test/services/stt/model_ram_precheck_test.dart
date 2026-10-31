import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/stt/memory_pressure.dart';
import 'package:whispaste/services/stt/model_ram_precheck.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_model_registry.dart';

void main() {
  group('onDeviceRamEstimateMB', () {
    test('whisper uses the per-model estimate', () {
      expect(
        onDeviceRamEstimateMB(
          engine: OnDeviceEngine.whisper,
          modelId: 'whisper-medium',
        ),
        1500,
      );
    });

    test('an unknown whisper model has no estimate', () {
      expect(
        onDeviceRamEstimateMB(
          engine: OnDeviceEngine.whisper,
          modelId: 'whisper-unknown',
        ),
        isNull,
      );
    });

    test('parakeet uses its model file total, rounded up to whole MB', () {
      final expected =
          (parakeetModelTotalBytes + 1024 * 1024 - 1) ~/ (1024 * 1024);
      expect(
        onDeviceRamEstimateMB(
          engine: OnDeviceEngine.parakeet,
          modelId: 'parakeet-tdt-0.6b-v3',
        ),
        expected,
      );
    });
  });

  group('ramClearlyShort', () {
    const snapshot = MemorySnapshot(totalMB: 8192, availableMB: 1000);

    test('an estimate above available plus the margin is clearly short', () {
      expect(ramClearlyShort(estimateMB: 2600, snapshot: snapshot), isTrue);
    });

    test('the margin absorbs a near miss up to available plus margin', () {
      expect(
        ramClearlyShort(
          estimateMB: 1000 + kModelRamPrecheckMarginMB,
          snapshot: snapshot,
        ),
        isFalse,
      );
      expect(
        ramClearlyShort(
          estimateMB: 1000 + kModelRamPrecheckMarginMB + 1,
          snapshot: snapshot,
        ),
        isTrue,
      );
    });

    test('an estimate that fits is not short', () {
      expect(ramClearlyShort(estimateMB: 900, snapshot: snapshot), isFalse);
    });

    test('unknown free memory is never short', () {
      expect(ramClearlyShort(estimateMB: 2600, snapshot: null), isFalse);
    });

    test('an unknown estimate is never short', () {
      expect(ramClearlyShort(estimateMB: null, snapshot: snapshot), isFalse);
    });
  });
}
