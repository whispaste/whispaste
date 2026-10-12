/// Unit tests for GpuInfo core logic.
///
/// Tests the pure-Dart GPU detection types and binary compatibility logic.
library;

import 'dart:ffi';
import 'dart:io';

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

    test('Kepler GT 730 without CUDA runtime → false', () {
      expect(shouldUseGpu(_nvidiaNoCuda), isFalse);
    });

    test('Modern NVIDIA without CUDA runtime stays on GPU (Vulkan)', () {
      const gpu = GpuInfo(
        vendor: GpuVendor.nvidia,
        name: 'NVIDIA GeForce RTX 3060',
        vulkanAvailable: true,
      );
      expect(shouldUseGpu(gpu), isTrue);
      expect(gpu.optimalBackend, 'vulkan');
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

  group('macOS detection — arch must not depend on a subprocess', () {
    // Skipped off actual macOS: `_detectMacOS()` short-circuits on
    // `Platform.isWindows` never being true here, but the vendor branch
    // this guards is macOS-only logic and only meaningful when the test
    // host really is macOS.
    final onMacOS = Platform.isMacOS;

    tearDown(() {
      setProcessRunnerForTesting(null);
      clearGpuCache();
    });

    test('every subprocess call failing does not misreport Apple Silicon as '
        'Intel', () async {
      if (!onMacOS) {
        markTestSkipped('macOS-only');
        return;
      }
      if (Abi.current() != Abi.macosArm64) {
        markTestSkipped('Apple-Silicon-only (host is Intel Mac)');
        return;
      }

      // Simulate the fork()+exec() hazard `_runProcessGuarded` guards
      // against (see its doc comment): every subprocess call — including
      // `uname -m` — fails. Detection must still recognize Apple Silicon
      // via Abi.current(), never falling through to the Intel/Vulkan
      // path below (no Vulkan whisper-server variant exists on macOS, so
      // that path fails to load on every session).
      setProcessRunnerForTesting((executable, arguments) async {
        throw ProcessException(executable, arguments, 'simulated failure');
      });

      final gpu = await detectGpuMacOSForTesting();

      expect(gpu.vendor, GpuVendor.apple);
      expect(gpu.optimalBackend, 'metal');
    });
  });

  // Windows vendor classification, driven through the real wmic parser with
  // a fake ProcessRunner (the classifier itself is private).
  group('Windows vendor classification (_classifyVendor via wmic)', () {
    void fakeWindowsAdapters(List<String> adapterNames) {
      setProcessRunnerForTesting((executable, arguments) async {
        if (executable == 'wmic') {
          return ProcessResult(
            0,
            0,
            adapterNames
                .map((n) => 'Name=$n\nAdapterRAM=1073741824\n\n')
                .join(),
            '',
          );
        }
        return ProcessResult(0, 1, '', ''); // powershell: no answer
      });
    }

    setUp(() {
      clearGpuCache();
    });

    tearDown(() {
      setProcessRunnerForTesting(null);
      setGpuDetectionFailureCallback(null);
      clearGpuCache();
    });

    final cases = <String, GpuVendor>{
      // Newly recognised vendor strings.
      'ATI Technologies Inc. Radeon HD 5770': GpuVendor.amd,
      'ATI Technologies Inc.': GpuVendor.amd,
      'GTX 1060 6GB': GpuVendor.nvidia,
      'Arc A380': GpuVendor.intel,
      // Already recognised; pinned so a later edit cannot drop them.
      'Radeon(TM) 780M Graphics': GpuVendor.amd,
      'NVIDIA GeForce GTX 1650': GpuVendor.nvidia,
      'Intel(R) Arc(TM) A770 Graphics': GpuVendor.intel,
      'Intel(R) UHD Graphics 770': GpuVendor.intel,
      'Intel(R) Iris(R) Xe Graphics': GpuVendor.intel,
      // Word-boundary guard: substrings inside ordinary words stay unknown.
      'Marcus Virtual Display': GpuVendor.none,
      // Virtual, software and ARM adapters stay on the CPU path.
      'Microsoft Basic Display Adapter': GpuVendor.none,
      'Parallels Display Adapter (WDDM)': GpuVendor.none,
      'VMware SVGA 3D': GpuVendor.none,
      'VirtualBox Graphics Adapter (WDDM)': GpuVendor.none,
      'Qualcomm(R) Adreno(TM) 690 GPU': GpuVendor.none,
      'Snapdragon X Adreno GPU': GpuVendor.none,
    };

    for (final entry in cases.entries) {
      test('"${entry.key}" classifies as ${entry.value.name}', () async {
        fakeWindowsAdapters([entry.key]);
        final gpu = await detectGpuWindowsForTesting();
        expect(gpu.vendor, entry.value);
      });
    }

    test('an unclassified adapter reports every raw adapter name to the '
        'failure callback', () async {
      fakeWindowsAdapters([
        'Qualcomm(R) Adreno(TM) 690 GPU',
        'Microsoft Basic Display Adapter',
      ]);
      List<String>? reported;
      setGpuDetectionFailureCallback(({
        required String reason,
        bool cudaAvailable = false,
        List<String> adapterNames = const [],
      }) {
        reported = adapterNames;
      });

      final gpu = await detectGpuWindowsForTesting();

      expect(gpu.vendor, GpuVendor.none);
      expect(reported, [
        'Qualcomm(R) Adreno(TM) 690 GPU',
        'Microsoft Basic Display Adapter',
      ]);
    });

    test(
      'a recognised adapter does not trigger the failure callback',
      () async {
        fakeWindowsAdapters(['Radeon(TM) 780M Graphics']);
        var calls = 0;
        setGpuDetectionFailureCallback(({
          required String reason,
          bool cudaAvailable = false,
          List<String> adapterNames = const [],
        }) {
          calls++;
        });

        final gpu = await detectGpuWindowsForTesting();

        expect(gpu.vendor, GpuVendor.amd);
        expect(calls, 0);
      },
    );
  });
}
