/// Resilience tests for the Windows GPU detection path.
///
/// These tests exercise the parallel `wmic` + `powershell` probe logic
/// introduced by issue 02 of the reliability sprint, without touching the
/// host machine's actual hardware. The injected [hw.ProcessRunner] returns
/// canned [ProcessResult]s — including timeout simulations — so the
/// guarantees we care about (no „not compatible" outcome, the fast probe wins
/// when the other blocks, the CPU fallback when both fail) hold across platforms.
/// Timeouts run on simulated time (fakeAsync).
///
/// Test seam contract (see `hardware_info_service.dart`):
///   - `setProcessRunnerForTesting` swaps `Process.run` for a fake.
///   - `detectGpuWindowsForTesting()` runs `_detectWindows()` regardless of
///     the host OS so macOS / Linux CI runners can verify the Windows path.
///   - `kWindowsGpuProbeTimeout` is the per-probe cap (8 s); we set up
///     blocking futures that resolve well past it.
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;

// ---------------------------------------------------------------------------
// Canned [ProcessResult] builders
// ---------------------------------------------------------------------------

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult _empty() => ProcessResult(0, 0, '', '');

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
    test('PowerShell wins when wmic blocks past the 8 s timeout', () {
      fakeAsync((async) {
        // wmic never answers, so the kWindowsGpuProbeTimeout (8 s) cap
        // collapses it to null via TimeoutException; PowerShell answers at
        // once with a valid Intel iGPU. Without the parallel `Future.wait`
        // refactor this used to block the entire detect call for 8 s.
        hw.setProcessRunnerForTesting((exe, args) {
          if (exe == 'wmic') return Completer<ProcessResult>().future;
          // powershell
          return Future.value(_ok(_powershellIntel));
        });

        hw.GpuInfo? gpu;
        unawaited(hw.detectGpuWindowsForTesting().then((g) => gpu = g));
        async.elapse(const Duration(seconds: 15));

        // PowerShell result wins — Intel.
        expect(gpu?.vendor, hw.GpuVendor.intel);
        expect(gpu?.name, contains('Intel'));
      });
    });
  });

  group('detectGpuWindowsForTesting — both probes time out', () {
    test(
      'returns GpuVendor.none CPU fallback when both block past the timeout',
      () {
        fakeAsync((async) {
          // Both probes block past the 8 s per-probe cap. Future.wait must
          // collapse them to null (via TimeoutException) and the function
          // must surface the CPU-fallback `GpuInfo`, not throw or hang.
          // Neither probe ever answers — the timeout wins.
          hw.setProcessRunnerForTesting(
            (exe, args) => Completer<ProcessResult>().future,
          );

          hw.GpuInfo? gpu;
          unawaited(hw.detectGpuWindowsForTesting().then((g) => gpu = g));
          async.elapse(const Duration(seconds: 15));

          expect(gpu?.vendor, hw.GpuVendor.none);
          expect(gpu?.name.toLowerCase(), contains('cpu'));
        });
      },
    );
  });
}
