/// Resilience tests for the Windows GPU detection path.
///
/// These tests exercise the parallel `wmic` + `powershell` probe logic
/// introduced by issue 02 of the reliability sprint, without touching the
/// host machine's actual hardware. The injected [hw.ProcessRunner] returns
/// canned [ProcessResult]s — including timeout simulations — so the
/// guarantees we care about (no „not compatible" outcome, sub-1s success
/// when one probe wins, ≤8s cap when both fail) hold across platforms.
///
/// Test seam contract (see `hardware_info_service.dart`):
///   - `setProcessRunnerForTesting` swaps `Process.run` for a fake.
///   - `detectGpuWindowsForTesting()` runs `_detectWindows()` regardless of
///     the host OS so macOS / Linux CI runners can verify the Windows path.
///   - `kWindowsGpuProbeTimeout` is the per-probe cap (8 s); we set up
///     blocking futures that resolve well past it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;

// ---------------------------------------------------------------------------
// Canned [ProcessResult] builders
// ---------------------------------------------------------------------------

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult _empty() => ProcessResult(0, 0, '', '');

/// `wmic /format:list` block for a single NVIDIA RTX 4090.
const String _wmicNvidia = '''
AdapterRAM=25756696576
Name=NVIDIA GeForce RTX 4090

''';

/// PowerShell `Get-CimInstance` output for a single Intel iGPU.
const String _powershellIntel = 'Intel(R) Iris(R) Xe Graphics|1073741824\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    hw.clearGpuCache();
  });

  tearDown(() {
    hw.setProcessRunnerForTesting(null);
    hw.clearGpuCache();
  });

  group('detectGpuWindowsForTesting — both probes empty', () {
    test(
      'returns GpuVendor.none with non-empty CPU fallback name, never throws',
      () async {
        // Both wmic and PowerShell return empty stdout — historically this
        // surfaced as „system not compatible" upstream. The fix returns a
        // usable CPU-fallback `GpuInfo` instead.
        hw.setProcessRunnerForTesting((exe, args) async => _empty());

        final gpu = await hw.detectGpuWindowsForTesting();

        expect(gpu.vendor, hw.GpuVendor.none);
        expect(gpu.name, isNotEmpty);
        // The fallback name must announce CPU usage so the UI/log layer
        // can pick it up without special-casing the generic „Unknown".
        expect(gpu.name.toLowerCase(), contains('cpu'));
      },
    );

    test(
      'serverAssetPatterns for the fallback GpuInfo returns a non-empty list '
      'that contains the CPU/blas variant',
      () async {
        hw.setProcessRunnerForTesting((exe, args) async => _empty());
        final gpu = await hw.detectGpuWindowsForTesting();

        // WhisPaste-binary repo → ['cpu'] variant must be present.
        final whispasteVariants = hw.serverAssetPatterns(gpu, 'auto', true);
        expect(whispasteVariants, isNotEmpty);
        expect(whispasteVariants, contains('cpu'));

        // Upstream whisper.cpp repo → ['blas-bin'] variant must be present.
        final upstreamVariants = hw.serverAssetPatterns(gpu, 'auto', false);
        expect(upstreamVariants, isNotEmpty);
        expect(upstreamVariants, contains('blas-bin'));
      },
    );
  });

  group('detectGpuWindowsForTesting — one probe slow, other fast', () {
    test(
      'PowerShell wins in <1 s when wmic blocks past the 8 s timeout',
      () async {
        // wmic returns after the kWindowsGpuProbeTimeout (8 s) cap so it
        // collapses to null via TimeoutException; PowerShell answers in
        // 200 ms with a valid Intel iGPU. Without the parallel `Future.wait`
        // refactor this used to block the entire detect call for 8 s.
        hw.setProcessRunnerForTesting((exe, args) async {
          if (exe == 'wmic') {
            await Future<void>.delayed(const Duration(milliseconds: 8500));
            return _ok(_wmicNvidia);
          }
          // powershell
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return _ok(_powershellIntel);
        });

        final stopwatch = Stopwatch()..start();
        final gpu = await hw.detectGpuWindowsForTesting();
        stopwatch.stop();

        // PowerShell result wins — Intel.
        expect(gpu.vendor, hw.GpuVendor.intel);
        expect(gpu.name, contains('Intel'));

        // The whole detect call must finish well before wmic's 8 s block —
        // 1 s is a generous tolerance window around the 200 ms PowerShell
        // probe + Future.wait overhead.
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 1)),
          reason:
              'detectGpuWindowsForTesting took ${stopwatch.elapsedMilliseconds} ms '
              'but PowerShell returned in 200 ms — wmic\'s block should not '
              'serialise the call.',
        );
      },
      // Wall-clock based; give the test framework headroom over the 8.5 s
      // wmic delay even though we expect to finish well below 1 s.
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });

  group('detectGpuWindowsForTesting — both probes time out', () {
    test(
      'returns GpuVendor.none CPU fallback after ≤8.5 s when both block past '
      'the timeout',
      () async {
        // Both probes block past the 8 s per-probe cap. Future.wait must
        // collapse them to null (via TimeoutException) and the function
        // must surface the CPU-fallback `GpuInfo`, not throw or hang.
        hw.setProcessRunnerForTesting((exe, args) async {
          await Future<void>.delayed(const Duration(seconds: 10));
          return _ok(_wmicNvidia); // never observed — timeout wins.
        });

        final stopwatch = Stopwatch()..start();
        final gpu = await hw.detectGpuWindowsForTesting();
        stopwatch.stop();

        expect(gpu.vendor, hw.GpuVendor.none);
        expect(gpu.name.toLowerCase(), contains('cpu'));
        // Cap is the per-probe timeout (8 s) + tiny scheduling overhead.
        // We allow 8.5 s to absorb scheduler jitter on slow CI runners.
        expect(
          stopwatch.elapsed,
          lessThanOrEqualTo(const Duration(milliseconds: 8500)),
          reason:
              'detectGpuWindowsForTesting took ${stopwatch.elapsedMilliseconds} ms '
              'but each probe should have given up at the 8 s timeout cap.',
        );
      },
      // Wall-clock based; allow comfortable headroom over the 8.5 s cap.
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });
}
