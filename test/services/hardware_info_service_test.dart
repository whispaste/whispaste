/// Unit tests for hardware_info_service — GPU detection, asset pattern
/// selection, binary compatibility checking, and metadata round-trip.
///
/// These tests cover the **pure logic** functions that don't require
/// spawning real GPU detection processes. Platform detection (wmic, sysctl,
/// lspci) is NOT tested here because it requires real hardware; instead
/// we test every function that accepts [GpuInfo] as a parameter.
@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/hardware_info_service.dart';

// ---------------------------------------------------------------------------
// Test GPU fixtures
// ---------------------------------------------------------------------------

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
  vramMB: 24576,
  cudaAvailable: false,
  vulkanAvailable: true,
);

const _intelGpu = GpuInfo(
  vendor: GpuVendor.intel,
  name: 'Intel Iris Xe Graphics',
  vramMB: 4096,
  cudaAvailable: false,
  vulkanAvailable: true,
);

const _appleGpu = GpuInfo(
  vendor: GpuVendor.apple,
  name: 'Apple M2 Pro',
  vramMB: 16384,
);

const _noGpu = GpuInfo(vendor: GpuVendor.none, name: 'No GPU detected');

void main() {
  // =========================================================================
  // GpuInfo — optimalBackend and computed properties
  // =========================================================================

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

  group('GpuInfo computed properties', () {
    test('hasGpu returns true for all vendors except none', () {
      expect(_nvidiaWithCuda.hasGpu, isTrue);
      expect(_amdGpu.hasGpu, isTrue);
      expect(_intelGpu.hasGpu, isTrue);
      expect(_appleGpu.hasGpu, isTrue);
      expect(_noGpu.hasGpu, isFalse);
    });

    test('supportsFlashAttn only for NVIDIA + CUDA', () {
      expect(_nvidiaWithCuda.supportsFlashAttn, isTrue);
      expect(_nvidiaNoCuda.supportsFlashAttn, isFalse);
      expect(_amdGpu.supportsFlashAttn, isFalse);
      expect(_intelGpu.supportsFlashAttn, isFalse);
    });

    test('toString includes all fields', () {
      final str = _nvidiaWithCuda.toString();
      expect(str, contains('nvidia'));
      expect(str, contains('NVIDIA RTX 4090'));
      expect(str, contains('24576'));
      expect(str, contains('cuda=true'));
    });
  });

  // =========================================================================
  // serverAssetPatterns — binary variant selection
  // =========================================================================

  group('serverAssetPatterns', () {
    group('WhisPaste repo', () {
      test('NVIDIA + CUDA: cuda12, vulkan, cpu', () {
        final patterns = serverAssetPatterns(_nvidiaWithCuda, 'auto', true);
        expect(patterns, ['cuda12', 'vulkan', 'cpu']);
      });

      test('NVIDIA without CUDA: vulkan, cpu', () {
        final patterns = serverAssetPatterns(_nvidiaNoCuda, 'auto', true);
        expect(patterns, ['vulkan', 'cpu']);
      });

      test('AMD: vulkan, cpu', () {
        final patterns = serverAssetPatterns(_amdGpu, 'auto', true);
        expect(patterns, ['vulkan', 'cpu']);
      });

      test('Intel: vulkan, cpu', () {
        final patterns = serverAssetPatterns(_intelGpu, 'auto', true);
        expect(patterns, ['vulkan', 'cpu']);
      });

      test('Apple: metal, cpu', () {
        final patterns = serverAssetPatterns(_appleGpu, 'auto', true);
        expect(patterns, ['metal', 'cpu']);
      });

      test('No GPU: cpu only', () {
        final patterns = serverAssetPatterns(_noGpu, 'auto', true);
        expect(patterns, ['cpu']);
      });
    });

    group('Upstream whisper.cpp repo', () {
      test('NVIDIA + CUDA: cublas-12, vulkan, blas-bin', () {
        final patterns = serverAssetPatterns(_nvidiaWithCuda, 'auto', false);
        expect(patterns, ['cublas-12', 'vulkan', 'blas-bin']);
      });

      test('Intel: vulkan, blas-bin', () {
        final patterns = serverAssetPatterns(_intelGpu, 'auto', false);
        expect(patterns, ['vulkan', 'blas-bin']);
      });

      test('No GPU: blas-bin only', () {
        final patterns = serverAssetPatterns(_noGpu, 'auto', false);
        expect(patterns, ['blas-bin']);
      });
    });

    group('gpuMode=disabled', () {
      test('WhisPaste: cpu only regardless of GPU', () {
        final patterns = serverAssetPatterns(_nvidiaWithCuda, 'disabled', true);
        expect(patterns, ['cpu']);
      });

      test('Upstream: blas-bin only regardless of GPU', () {
        final patterns = serverAssetPatterns(
          _nvidiaWithCuda,
          'disabled',
          false,
        );
        expect(patterns, ['blas-bin']);
      });
    });

    group('gpuMode=enabled', () {
      test('same as auto — GPU-aware selection', () {
        final patterns = serverAssetPatterns(_amdGpu, 'enabled', true);
        expect(patterns, ['vulkan', 'cpu']);
      });
    });
  });

  // =========================================================================
  // writeServerBinaryInfo / readServerBinaryInfo — metadata round-trip
  // =========================================================================

  group('Server binary info metadata', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('hw_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('readServerBinaryInfo returns null when no file exists', () {
      expect(readServerBinaryInfo(tmpDir.path), isNull);
    });

    test('write + read round-trip preserves all fields', () async {
      await writeServerBinaryInfo(
        tmpDir.path,
        _nvidiaWithCuda,
        sourceRepo: 'whispaste/whispaste',
        assetName: 'whisper-server-cuda12-x64.zip',
      );

      final info = readServerBinaryInfo(tmpDir.path);
      expect(info, isNotNull);
      expect(info!['backend'], 'cuda');
      expect(info['gpu_vendor'], 'nvidia');
      expect(info['gpu_name'], 'NVIDIA RTX 4090');
      expect(info['cuda_available'], true);
      expect(info['vulkan_available'], true);
      expect(info['source_repo'], 'whispaste/whispaste');
      expect(info['asset_name'], 'whisper-server-cuda12-x64.zip');
      expect(info['downloaded_at'], isNotNull);
    });

    test('write without optional fields omits them', () async {
      await writeServerBinaryInfo(tmpDir.path, _intelGpu);

      final info = readServerBinaryInfo(tmpDir.path);
      expect(info, isNotNull);
      expect(info!['backend'], 'vulkan');
      expect(info['gpu_vendor'], 'intel');
      expect(info.containsKey('source_repo'), isFalse);
      expect(info.containsKey('asset_name'), isFalse);
    });

    test('readServerBinaryInfo returns null for corrupted JSON', () {
      final infoFile = File(p.join(tmpDir.path, '.server-info.json'));
      infoFile.writeAsStringSync('not valid json!!!');

      expect(readServerBinaryInfo(tmpDir.path), isNull);
    });
  });

  // =========================================================================
  // isServerBinaryCompatible — 2-layer validation
  // =========================================================================

  group('isServerBinaryCompatible', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('hw_compat_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('returns true when no binary exists', () {
      expect(isServerBinaryCompatible(tmpDir.path, _nvidiaWithCuda), isTrue);
    });

    test(
      'returns true when binary exists with matching backend (Vulkan)',
      () async {
        // Use Intel/Vulkan — no DLL heuristic to complicate things.
        File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
        File(p.join(tmpDir.path, 'ggml-vulkan.dll')).createSync();
        await writeServerBinaryInfo(tmpDir.path, _intelGpu);

        expect(isServerBinaryCompatible(tmpDir.path, _intelGpu), isTrue);
      },
    );

    test('returns false when metadata backend mismatches GPU', () async {
      File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
      // Downloaded for Vulkan (Intel), but now on NVIDIA+CUDA.
      await writeServerBinaryInfo(tmpDir.path, _intelGpu);

      expect(isServerBinaryCompatible(tmpDir.path, _nvidiaWithCuda), isFalse);
    });

    test('returns false when CPU binary on Vulkan-capable GPU', () async {
      File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
      await writeServerBinaryInfo(tmpDir.path, _noGpu);

      expect(isServerBinaryCompatible(tmpDir.path, _intelGpu), isFalse);
    });

    // --- Layer 2: DLL heuristic (Windows-only) ---

    test('returns false when CUDA DLLs present on non-NVIDIA GPU', () async {
      File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
      // No metadata → Layer 1 passes, but Layer 2 should catch it.
      File(p.join(tmpDir.path, 'cublas64_12.dll')).createSync();
      File(p.join(tmpDir.path, 'ggml-cuda.dll')).createSync();

      expect(isServerBinaryCompatible(tmpDir.path, _intelGpu), isFalse);
    });

    test('returns true when metadata matches even without CUDA DLLs', () async {
      File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
      // Write metadata saying "cuda" — backend matches GPU.
      await writeServerBinaryInfo(tmpDir.path, _nvidiaWithCuda);

      // Metadata match short-circuits: trust our own download metadata.
      // Runtime DLL_NOT_FOUND is handled by stt_service if DLLs are missing.
      expect(isServerBinaryCompatible(tmpDir.path, _nvidiaWithCuda), isTrue);
    });

    test('returns true when CUDA DLLs present on NVIDIA system', () async {
      File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
      await writeServerBinaryInfo(tmpDir.path, _nvidiaWithCuda);
      // Create CUDA DLLs — binary and metadata both say CUDA.
      File(p.join(tmpDir.path, 'cublas64_12.dll')).createSync();
      File(p.join(tmpDir.path, 'cublaslt64_12.dll')).createSync();
      File(p.join(tmpDir.path, 'ggml-cuda.dll')).createSync();

      expect(isServerBinaryCompatible(tmpDir.path, _nvidiaWithCuda), isTrue);
    });

    test('returns true for Vulkan binary on Intel (no CUDA DLLs)', () async {
      File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
      File(p.join(tmpDir.path, 'ggml-vulkan.dll')).createSync();
      await writeServerBinaryInfo(tmpDir.path, _intelGpu);

      expect(isServerBinaryCompatible(tmpDir.path, _intelGpu), isTrue);
    });

    // --- Layer 3: Vulkan DLL heuristic ---

    test(
      'returns false when no ggml-vulkan.dll on Vulkan-capable GPU',
      () async {
        File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
        // CPU/OpenBLAS DLLs but no Vulkan DLL — legacy upstream download.
        File(p.join(tmpDir.path, 'libopenblas.dll')).createSync();
        File(p.join(tmpDir.path, 'ggml-blas.dll')).createSync();

        expect(isServerBinaryCompatible(tmpDir.path, _intelGpu), isFalse);
      },
    );

    test('returns false when no Vulkan DLL on AMD GPU', () async {
      File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
      File(p.join(tmpDir.path, 'libopenblas.dll')).createSync();

      expect(isServerBinaryCompatible(tmpDir.path, _amdGpu), isFalse);
    });

    test(
      'returns true when ggml-vulkan.dll present without metadata',
      () async {
        File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
        File(p.join(tmpDir.path, 'ggml-vulkan.dll')).createSync();
        // No .server-info.json — relies on DLL heuristic only.

        expect(isServerBinaryCompatible(tmpDir.path, _intelGpu), isTrue);
      },
    );

    test(
      'returns true when metadata says vulkan even without DLL (static link)',
      () async {
        File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
        await writeServerBinaryInfo(tmpDir.path, _intelGpu);
        // Metadata says vulkan, GPU needs vulkan → match.
        // No ggml-vulkan.dll because Vulkan is statically linked in the binary.
        // L1 metadata match short-circuits — this is the exact scenario that
        // previously caused an infinite download-delete loop.
        expect(isServerBinaryCompatible(tmpDir.path, _intelGpu), isTrue);
      },
    );
  });

  // =========================================================================
  // deleteServerBinary — cleanup logic
  // =========================================================================

  group('deleteServerBinary', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('hw_delete_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('deletes exe, dll, and info files', () async {
      File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
      File(p.join(tmpDir.path, 'cublas64_12.dll')).createSync();
      File(p.join(tmpDir.path, 'ggml-cuda.dll')).createSync();
      File(
        p.join(tmpDir.path, '.server-info.json'),
      ).writeAsStringSync('{"backend":"cuda"}');

      await deleteServerBinary(tmpDir.path);

      expect(
        File(p.join(tmpDir.path, 'whisper-server.exe')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(tmpDir.path, 'cublas64_12.dll')).existsSync(),
        isFalse,
      );
      expect(File(p.join(tmpDir.path, 'ggml-cuda.dll')).existsSync(), isFalse);
      expect(
        File(p.join(tmpDir.path, '.server-info.json')).existsSync(),
        isFalse,
      );
    });

    test('preserves non-binary files (models, configs)', () async {
      File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
      File(p.join(tmpDir.path, 'ggml-small.bin')).createSync();
      File(
        p.join(tmpDir.path, 'config.json'),
      ).writeAsStringSync('{"key":"val"}');

      await deleteServerBinary(tmpDir.path);

      expect(
        File(p.join(tmpDir.path, 'whisper-server.exe')).existsSync(),
        isFalse,
      );
      // Non-binary files must survive.
      expect(File(p.join(tmpDir.path, 'ggml-small.bin')).existsSync(), isTrue);
      expect(File(p.join(tmpDir.path, 'config.json')).existsSync(), isTrue);
    });

    test('handles non-existent directory gracefully', () async {
      final fakePath = p.join(tmpDir.path, 'does_not_exist');
      // Should not throw.
      await deleteServerBinary(fakePath);
    });
  });

  // =========================================================================
  // GPU cache management
  // =========================================================================

  group('GPU cache', () {
    test('clearGpuCache resets cached info', () {
      clearGpuCache();
      expect(cachedGpuInfo, isNull);
    });

    test('detectGpu populates cache', () async {
      clearGpuCache();
      final gpu = await detectGpu();
      expect(cachedGpuInfo, isNotNull);
      expect(cachedGpuInfo, same(gpu));
    });

    test('detectGpu returns same instance on second call', () async {
      clearGpuCache();
      final first = await detectGpu();
      final second = await detectGpu();
      expect(identical(first, second), isTrue);
    });
  });

  // =========================================================================
  // Integration-style: validateAndCleanIncompatibleBinary
  // =========================================================================

  group('validateAndCleanIncompatibleBinary', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('hw_validate_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('returns false when no binary exists', () async {
      final deleted = await validateAndCleanIncompatibleBinary(tmpDir.path);
      expect(deleted, isFalse);
    });

    test('returns false when binary matches real hardware', () async {
      // Detect the REAL GPU on this machine.
      clearGpuCache();
      final realGpu = await detectGpu();

      // Write a binary + matching metadata for the real GPU.
      File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();
      await writeServerBinaryInfo(tmpDir.path, realGpu);

      // If the real GPU is NVIDIA+CUDA, we also need CUDA DLLs to pass
      // Layer 2. For non-NVIDIA, just the metadata match is enough.
      if (realGpu.vendor == GpuVendor.nvidia && realGpu.cudaAvailable) {
        File(p.join(tmpDir.path, 'cublas64_12.dll')).createSync();
        File(p.join(tmpDir.path, 'cublaslt64_12.dll')).createSync();
        File(p.join(tmpDir.path, 'ggml-cuda.dll')).createSync();
      }

      // If the real GPU needs Vulkan, we need ggml-vulkan.dll to pass
      // Layer 3.
      if (realGpu.optimalBackend == 'vulkan') {
        File(p.join(tmpDir.path, 'ggml-vulkan.dll')).createSync();
      }

      final deleted = await validateAndCleanIncompatibleBinary(tmpDir.path);
      expect(deleted, isFalse);
      // Binary should still exist.
      expect(
        File(p.join(tmpDir.path, 'whisper-server.exe')).existsSync(),
        isTrue,
      );
    });

    test('deletes binary when metadata says wrong backend', () async {
      clearGpuCache();
      final realGpu = await detectGpu();

      File(p.join(tmpDir.path, 'whisper-server.exe')).createSync();

      // Write metadata for a DIFFERENT backend than the real GPU.
      final fakeGpu = realGpu.optimalBackend == 'cpu'
          ? _intelGpu // If CPU, pretend it's Intel Vulkan.
          : _noGpu; // If anything else, pretend it's CPU.
      await writeServerBinaryInfo(tmpDir.path, fakeGpu);

      final deleted = await validateAndCleanIncompatibleBinary(tmpDir.path);
      expect(deleted, isTrue);
      // Binary should be gone.
      expect(
        File(p.join(tmpDir.path, 'whisper-server.exe')).existsSync(),
        isFalse,
      );
    });
  });
}
