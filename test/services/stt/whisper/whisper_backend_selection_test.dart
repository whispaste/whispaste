import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/stt/whisper/whisper_engine.dart';
import 'package:whispaste/services/stt/whisper/whisper_isolate_engine.dart';

const _kepler = GpuInfo(
  vendor: GpuVendor.nvidia,
  name: 'NVIDIA GeForce GTX 760',
  cudaAvailable: true,
  vulkanAvailable: true,
);

const _rtx = GpuInfo(
  vendor: GpuVendor.nvidia,
  name: 'NVIDIA GeForce RTX 4070',
  cudaAvailable: true,
  vulkanAvailable: true,
);

void main() {
  group('selectWhisperBackend', () {
    test('auto routes Kepler to CPU before loading', () {
      expect(
        selectWhisperBackend(gpuPreference: 'auto', gpu: _kepler),
        WhisperBackend.cpu,
      );
    });

    test('enabled keeps the detected backend for Kepler', () {
      expect(
        selectWhisperBackend(gpuPreference: 'enabled', gpu: _kepler),
        WhisperBackend.vulkan,
      );
    });

    test('auto keeps CUDA for modern NVIDIA', () {
      expect(
        selectWhisperBackend(gpuPreference: 'auto', gpu: _rtx),
        WhisperBackend.cuda,
      );
    });

    test('disabled always forces CPU', () {
      expect(
        selectWhisperBackend(gpuPreference: 'disabled', gpu: _rtx),
        WhisperBackend.cpu,
      );
    });

    test('unset preference behaves like auto', () {
      expect(
        selectWhisperBackend(gpuPreference: null, gpu: _kepler),
        WhisperBackend.cpu,
      );
    });

    test('no detection result yet falls back to CPU', () {
      expect(
        selectWhisperBackend(gpuPreference: 'auto', gpu: null),
        WhisperBackend.cpu,
      );
    });
  });
}
