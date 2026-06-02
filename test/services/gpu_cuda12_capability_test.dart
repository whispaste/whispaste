/// Unit tests for the CUDA-12 capability heuristic on [GpuInfo].
///
/// CUDA 12 dropped Fermi (sm_2x) and Kepler (sm_3x). Handing the prebuilt
/// cuda12 whisper-server to those cards aborts on launch — the root cause
/// behind the GTX-650 crash loop (FLUTTER_WHISPASTE-80 / -6V / -6X). These
/// tests pin which GPUs route to the CUDA backend versus the Vulkan fallback.
///
/// Pure logic — no filesystem or subprocess, so this runs on every platform
/// (unlike `hardware_info_service_test.dart`, which is Windows-only).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/hardware_info_service.dart';

GpuInfo _nvidia(String name, {bool cuda = true}) =>
    GpuInfo(vendor: GpuVendor.nvidia, name: name, cudaAvailable: cuda);

void main() {
  group('GpuInfo.supportsCuda12', () {
    test('Kepler GeForce GTX 6xx → false', () {
      expect(_nvidia('NVIDIA GeForce GTX 650').supportsCuda12, isFalse);
      expect(_nvidia('NVIDIA GeForce GTX 680').supportsCuda12, isFalse);
    });

    test('Fermi/Kepler GeForce 4xx/5xx/7xx → false', () {
      expect(_nvidia('NVIDIA GeForce GTX 480').supportsCuda12, isFalse);
      expect(_nvidia('NVIDIA GeForce GTX 560 Ti').supportsCuda12, isFalse);
      expect(_nvidia('NVIDIA GeForce GT 730').supportsCuda12, isFalse);
      expect(_nvidia('NVIDIA GeForce GTX 760').supportsCuda12, isFalse);
    });

    test('Kepler professional cards (Quadro K / Tesla K) → false', () {
      expect(_nvidia('Quadro K2200').supportsCuda12, isFalse);
      expect(_nvidia('Tesla K80').supportsCuda12, isFalse);
    });

    test('Maxwell GTX 9xx and newer → true', () {
      expect(_nvidia('NVIDIA GeForce GTX 960').supportsCuda12, isTrue);
      expect(_nvidia('NVIDIA GeForce GTX 980 Ti').supportsCuda12, isTrue);
    });

    test('Pascal / Turing / Ada (4-digit models) → true', () {
      expect(_nvidia('NVIDIA GeForce GTX 1060').supportsCuda12, isTrue);
      expect(_nvidia('NVIDIA GeForce GTX 1650').supportsCuda12, isTrue);
      expect(_nvidia('NVIDIA GeForce RTX 4090').supportsCuda12, isTrue);
      expect(_nvidia('NVIDIA GeForce RTX 4070').supportsCuda12, isTrue);
    });

    test('unknown discrete NVIDIA (hybrid laptop) → true (assume capable)', () {
      expect(
        _nvidia('Intel(R) Iris(R) Xe + NVIDIA (discrete)').supportsCuda12,
        isTrue,
      );
    });

    test('NVIDIA without CUDA runtime → false', () {
      expect(
        _nvidia('NVIDIA GeForce RTX 4090', cuda: false).supportsCuda12,
        isFalse,
      );
    });

    test('non-NVIDIA vendors → false', () {
      const amd = GpuInfo(
        vendor: GpuVendor.amd,
        name: 'AMD Radeon RX 7900 XTX',
      );
      const apple = GpuInfo(vendor: GpuVendor.apple, name: 'Apple M2 Pro');
      const none = GpuInfo(vendor: GpuVendor.none, name: 'No GPU');
      expect(amd.supportsCuda12, isFalse);
      expect(apple.supportsCuda12, isFalse);
      expect(none.supportsCuda12, isFalse);
    });
  });

  group('optimalBackend respects CUDA-12 capability', () {
    test('Kepler GTX 650 → vulkan (not cuda)', () {
      expect(_nvidia('NVIDIA GeForce GTX 650').optimalBackend, 'vulkan');
    });

    test('modern NVIDIA + CUDA → cuda', () {
      expect(_nvidia('NVIDIA GeForce RTX 4090').optimalBackend, 'cuda');
    });

    test('NVIDIA without CUDA → vulkan', () {
      expect(
        _nvidia('NVIDIA GeForce RTX 4090', cuda: false).optimalBackend,
        'vulkan',
      );
    });
  });

  group('serverAssetPatterns skips cuda12 for Kepler', () {
    test('Kepler GTX 650 (WhisPaste) → vulkan first, no cuda12', () {
      final patterns = serverAssetPatterns(
        _nvidia('NVIDIA GeForce GTX 650'),
        'auto',
        true,
      );
      expect(patterns, ['vulkan', 'cpu']);
      expect(patterns, isNot(contains('cuda12')));
    });

    test('modern NVIDIA (WhisPaste) → cuda12 first', () {
      final patterns = serverAssetPatterns(
        _nvidia('NVIDIA GeForce RTX 4090'),
        'auto',
        true,
      );
      expect(patterns, ['cuda12', 'vulkan', 'cpu']);
    });

    test('Kepler GTX 650 (upstream) → vulkan first, no cublas-12', () {
      final patterns = serverAssetPatterns(
        _nvidia('NVIDIA GeForce GTX 650'),
        'auto',
        false,
      );
      expect(patterns, ['vulkan', 'blas-bin']);
    });
  });
}
