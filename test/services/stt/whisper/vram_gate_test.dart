/// VRAM gate for GPU backends: a model that does not fit the detected GPU
/// memory is kept off the GPU.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/stt/whisper/vram_gate.dart';

const _gpu = GpuInfo(
  vendor: GpuVendor.nvidia,
  name: 'NVIDIA GeForce GTX 1050',
  vramMB: 2048,
  vulkanAvailable: true,
);

void main() {
  group('modelExceedsGpuVram', () {
    test('a model larger than the detected VRAM does not fit', () {
      expect(
        modelExceedsGpuVram(modelId: 'whisper-large-v3-turbo', gpu: _gpu),
        isTrue,
      );
    });

    test('a model within the detected VRAM fits', () {
      expect(modelExceedsGpuVram(modelId: 'whisper-small', gpu: _gpu), isFalse);
    });

    test(
      'unknown VRAM, no GPU or an unknown model never counts as too big',
      () {
        const noVram = GpuInfo(vendor: GpuVendor.amd, name: 'AMD Radeon');
        expect(
          modelExceedsGpuVram(modelId: 'whisper-large-v3-turbo', gpu: noVram),
          isFalse,
        );
        expect(
          modelExceedsGpuVram(modelId: 'whisper-large-v3-turbo', gpu: null),
          isFalse,
        );
        expect(
          modelExceedsGpuVram(modelId: 'unknown-model', gpu: _gpu),
          isFalse,
        );
      },
    );
  });

  group('vramGateNoticeFor', () {
    VramGateNotice? notice({
      OnDeviceEngine engine = OnDeviceEngine.whisper,
      String gpuAcceleration = 'auto',
      String modelId = 'whisper-large-v3-turbo',
      GpuInfo? gpu = _gpu,
    }) => vramGateNoticeFor(
      engine: engine,
      gpuAcceleration: gpuAcceleration,
      modelId: modelId,
      gpu: gpu,
    );

    test('reports required and detected VRAM when the model does not fit', () {
      final result = notice();
      expect(result, isNotNull);
      expect(result!.vramMb, 2048);
      expect(result.requiredMb, greaterThan(2048));
    });

    test('stays silent when the model fits, GPU is off or no GPU is known', () {
      expect(notice(modelId: 'whisper-small'), isNull);
      expect(notice(gpuAcceleration: GpuAcceleration.disabled.value), isNull);
      expect(notice(gpu: null), isNull);
      expect(notice(engine: OnDeviceEngine.parakeet), isNull);
      expect(notice(modelId: 'unknown-model'), isNull);
    });
  });
}
