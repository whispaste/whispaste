/// Unit tests for GpuInfo core logic.
///
/// Tests the pure-Dart GPU detection types and binary compatibility logic.
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/probes/gpu_info.dart';

const _nvidiaWithCuda = GpuInfo(
  vendor: GpuVendor.nvidia,
  name: 'NVIDIA RTX 4090',
  vramMB: 24576,
  cudaAvailable: true,
  vulkanAvailable: true,
);

const _nvidiaNoCuda = GpuInfo(
  vendor: GpuVendor.nvidia,
  name: 'NVIDIA GeForce GT 730',
  vramMB: 2048,
  cudaAvailable: false,
  vulkanAvailable: true,
);

const _amdGpu = GpuInfo(
  vendor: GpuVendor.amd,
  name: 'AMD Radeon RX 7900 XTX',
  cudaAvailable: false,
  vulkanAvailable: true,
);

const _intelGpu = GpuInfo(
  vendor: GpuVendor.intel,
  name: 'Intel Iris Xe Graphics',
  vulkanAvailable: true,
);

const _appleGpu = GpuInfo(vendor: GpuVendor.apple, name: 'Apple M2 Pro');

const _noGpu = GpuInfo(vendor: GpuVendor.none, name: 'No GPU detected');

void main() {
  group('GpuInfo.optimalBackend', () {
    test('NVIDIA + CUDA → cuda', () {
      expect(_nvidiaWithCuda.optimalBackend, 'cuda');
    });

    test('NVIDIA without CUDA → vulkan', () {
      expect(_nvidiaNoCuda.optimalBackend, 'vulkan');
    });

    test('AMD → vulkan', () {
      expect(_amdGpu.optimalBackend, 'vulkan');
    });

    test('Intel → vulkan', () {
      expect(_intelGpu.optimalBackend, 'vulkan');
    });

    test('Apple → metal', () {
      expect(_appleGpu.optimalBackend, 'metal');
    });

    test('No GPU → cpu', () {
      expect(_noGpu.optimalBackend, 'cpu');
    });
  });

  group('GpuInfo.hasGpu', () {
    test('true for all vendors except none', () {
      expect(_nvidiaWithCuda.hasGpu, isTrue);
      expect(_amdGpu.hasGpu, isTrue);
      expect(_intelGpu.hasGpu, isTrue);
      expect(_appleGpu.hasGpu, isTrue);
      expect(_noGpu.hasGpu, isFalse);
    });
  });

  group('serverAssetPatterns', () {
    test('NVIDIA + CUDA → [cuda12, vulkan, cpu]', () {
      expect(serverAssetPatterns(_nvidiaWithCuda, 'auto', true), [
        'cuda12',
        'vulkan',
        'cpu',
      ]);
    });

    test('disabled GPU mode → [cpu] regardless of GPU', () {
      expect(serverAssetPatterns(_nvidiaWithCuda, 'disabled', true), ['cpu']);
    });

    test('AMD → [vulkan, cpu]', () {
      expect(serverAssetPatterns(_amdGpu, 'auto', true), ['vulkan', 'cpu']);
    });
  });

  group('shouldUseGpu', () {
    // Kepler/Fermi NVIDIA → false (proactive CPU routing)
    test('Kepler GTX 650 (CUDA) → false', () {
      const gpu = GpuInfo(
        vendor: GpuVendor.nvidia,
        name: 'NVIDIA GeForce GTX 650',
        cudaAvailable: true,
      );
      expect(shouldUseGpu(gpu), isFalse);
    });

    test('Kepler GTX 760 (CUDA) → false', () {
      const gpu = GpuInfo(
        vendor: GpuVendor.nvidia,
        name: 'NVIDIA GeForce GTX 760',
        cudaAvailable: true,
      );
      expect(shouldUseGpu(gpu), isFalse);
    });

    test('Fermi GTX 480 (CUDA) → false', () {
      const gpu = GpuInfo(
        vendor: GpuVendor.nvidia,
        name: 'NVIDIA GeForce GTX 480',
        cudaAvailable: true,
      );
      expect(shouldUseGpu(gpu), isFalse);
    });

    test('Kepler professional (Quadro K2200) → false', () {
      const gpu = GpuInfo(
        vendor: GpuVendor.nvidia,
        name: 'Quadro K2200',
        cudaAvailable: true,
      );
      expect(shouldUseGpu(gpu), isFalse);
    });

    // Modern NVIDIA → true
    test('RTX 4090 (CUDA) → true', () {
      expect(shouldUseGpu(_nvidiaWithCuda), isTrue);
    });

    test('GTX 1060 (CUDA) → true', () {
      const gpu = GpuInfo(
        vendor: GpuVendor.nvidia,
        name: 'NVIDIA GeForce GTX 1060',
        cudaAvailable: true,
      );
      expect(shouldUseGpu(gpu), isTrue);
    });

    // Old AMD GCN (Tahiti/Cape Verde) → false
    test('Old AMD GCN (Radeon HD 7970) → false', () {
      const gpu = GpuInfo(
        vendor: GpuVendor.amd,
        name: 'AMD Radeon HD 7970',
        vulkanAvailable: true,
      );
      expect(shouldUseGpu(gpu), isFalse);
    });

    test('Old AMD GCN (Radeon HD 8570) → false', () {
      const gpu = GpuInfo(
        vendor: GpuVendor.amd,
        name: 'AMD Radeon HD 8570',
        vulkanAvailable: true,
      );
      expect(shouldUseGpu(gpu), isFalse);
    });

    // Modern AMD → true
    test('Modern AMD RX 7900 XTX → true', () {
      expect(shouldUseGpu(_amdGpu), isTrue);
    });

    test('Modern AMD RX 580 → true', () {
      const gpu = GpuInfo(
        vendor: GpuVendor.amd,
        name: 'AMD Radeon RX 580',
        vulkanAvailable: true,
      );
      expect(shouldUseGpu(gpu), isTrue);
    });

    // Intel, Apple → true (conservative, GPU allowed)
    test('Intel GPU → true', () {
      expect(shouldUseGpu(_intelGpu), isTrue);
    });

    test('Apple GPU → true', () {
      expect(shouldUseGpu(_appleGpu), isTrue);
    });

    // No GPU vendor → false (nothing to accelerate)
    test('No GPU → false', () {
      expect(shouldUseGpu(_noGpu), isFalse);
    });

    // Unknown NVIDIA name → conservative: true
    test('Unknown NVIDIA (discrete hybrid) → true (conservative)', () {
      const gpu = GpuInfo(
        vendor: GpuVendor.nvidia,
        name: 'Intel Iris Xe + NVIDIA (discrete)',
        cudaAvailable: true,
      );
      expect(shouldUseGpu(gpu), isTrue);
    });
  });

  group('firstUnresolvableBackendLoaderDllFor', () {
    bool allResolve(String _) => true;
    bool noneResolve(String _) => false;

    test('vulkan with dll present → null', () {
      expect(
        firstUnresolvableBackendLoaderDllFor(
          backend: 'vulkan',
          resolve: allResolve,
        ),
        isNull,
      );
    });

    test('vulkan with dll missing → names it', () {
      expect(
        firstUnresolvableBackendLoaderDllFor(
          backend: 'vulkan',
          resolve: noneResolve,
        ),
        'vulkan-1.dll',
      );
    });

    test('cpu / blas-bin / metal → null (no GPU-loader deps)', () {
      for (final backend in const ['cpu', 'blas-bin', 'metal']) {
        expect(
          firstUnresolvableBackendLoaderDllFor(
            backend: backend,
            resolve: noneResolve,
          ),
          isNull,
          reason: '$backend must not trip the GPU-loader gate',
        );
      }
    });

    test('null/empty backend → null', () {
      expect(
        firstUnresolvableBackendLoaderDllFor(
          backend: null,
          resolve: noneResolve,
        ),
        isNull,
      );
    });
  });
}
