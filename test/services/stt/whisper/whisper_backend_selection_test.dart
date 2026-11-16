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

  // Befund 28 (Maintainer 10a, 2026-10-25): without a usable wp_ffi_guard no
  // GPU backend may be initialised, because whisper_init with use_gpu would
  // run vendor code outside the C++ exception guard.
  group('guard gate (Befund 28)', () {
    test('without a usable guard modern NVIDIA is not selected for CUDA', () {
      expect(
        selectWhisperBackend(
          gpuPreference: 'auto',
          gpu: _rtx,
          guardUsable: false,
        ),
        WhisperBackend.cpu,
      );
    });

    test('without a usable guard an explicitly enabled GPU is still CPU', () {
      expect(
        selectWhisperBackend(
          gpuPreference: 'enabled',
          gpu: _kepler,
          guardUsable: false,
        ),
        WhisperBackend.cpu,
      );
    });

    test('with a usable guard the GPU selection is unchanged', () {
      expect(
        selectWhisperBackend(
          gpuPreference: 'auto',
          gpu: _rtx,
          guardUsable: true,
        ),
        WhisperBackend.cuda,
      );
      expect(
        selectWhisperBackend(
          gpuPreference: 'enabled',
          gpu: _kepler,
          guardUsable: true,
        ),
        WhisperBackend.vulkan,
      );
    });

    test('backendAllowedByGuard gates every GPU backend, CPU passes', () {
      for (final gpu in [
        WhisperBackend.cuda,
        WhisperBackend.vulkan,
        WhisperBackend.metal,
      ]) {
        expect(
          backendAllowedByGuard(gpu, guardUsable: false),
          WhisperBackend.cpu,
        );
        expect(backendAllowedByGuard(gpu, guardUsable: true), gpu);
      }
      expect(
        backendAllowedByGuard(WhisperBackend.cpu, guardUsable: false),
        WhisperBackend.cpu,
      );
    });
  });
}
