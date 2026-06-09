/// Capture-pipeline tests for the GPU-detection-failed Sentry path.
///
/// Hardware-debugging audit (2026-05): a Windows host that cannot reach
/// `wmic` or `powershell` (corporate AV, group-policy lockdown, broken
/// WMI subsystem) used to silently return a CPU-fallback `GpuInfo`
/// without telling Sentry. The audit added a one-shot guard that emits
/// exactly one `gpuDetectionFailed` event per app session, plus a
/// re-arm path tied to [hw.clearGpuCache].
///
/// These tests pin the capture contract: shape of the event, the
/// fingerprint, and the once-per-session + post-clearGpuCache behaviour.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:whispaste/core/logging/crash_fingerprints.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;

final _capturedEvents = <SentryEvent>[];

SentryEvent? _spyBeforeSend(SentryEvent event, Hint hint) {
  _capturedEvents.add(event);
  return null;
}

ProcessResult _empty() => ProcessResult(0, 0, '', '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await SentryFlutter.init((options) {
      options.dsn = 'https://abc123@sentry.example.invalid/0';
      options.environment = 'test';
      options.beforeSend = _spyBeforeSend;
    });
    CrashReporter.init();
    CrashReporter.instance!.consentGranted = true;
    // Wire the GPU-detection-failure callback so captureGpuDetectionFailureOnce
    // reaches Sentry via CrashReporter (same as production).
    hw.initHardwareInfoTelemetry();
  });

  tearDownAll(() async {
    await CrashReporter.instance?.dispose();
  });

  setUp(() {
    _capturedEvents.clear();
    hw.clearGpuCache();
  });

  tearDown(() {
    hw.setProcessRunnerForTesting(null);
    hw.clearGpuCache();
  });

  group('GPU-detection failure capture (hardware audit 2026-05)', () {
    test(
      'both Windows probes empty → exactly one gpuDetectionFailed event',
      () async {
        // Simulate the corporate-AV / locked-down-WMI shape: every
        // subprocess returns 0-exit + empty stdout. The vendor classifier
        // resolves to GpuVendor.none, which is the blind-detection path.
        hw.setProcessRunnerForTesting((_, _) async => _empty());

        await hw.detectGpuWindowsForTesting();
        await CrashReporter.instance!.flush();

        expect(
          _capturedEvents,
          hasLength(1),
          reason:
              'Blind GPU detection must surface exactly one Sentry event '
              'under the gpuDetectionFailed bucket so machines that cannot '
              'read their GPU info are visible in Sentry.',
        );

        final ev = _capturedEvents.single;
        expect(
          ev.fingerprint,
          [gpuDetectionFailed],
          reason: 'fingerprint must come from crash_fingerprints.dart',
        );

        final extrasCtx = ev.contexts['extras'] as Map?;
        expect(extrasCtx, isNotNull);
        expect(
          extrasCtx!.keys,
          containsAll([
            'reason',
            'platform',
            'os_version',
            'cuda_available',
            'num_processors',
          ]),
          reason: 'hardware-context extras must accompany the capture',
        );
      },
    );

    test('once-per-session guard: a second blind detection within the '
        'same session does NOT add a second event', () async {
      hw.setProcessRunnerForTesting((_, _) async => _empty());

      await hw.detectGpuWindowsForTesting();
      await hw.detectGpuWindowsForTesting();
      await hw.detectGpuWindowsForTesting();
      await CrashReporter.instance!.flush();

      expect(
        _capturedEvents,
        hasLength(1),
        reason:
            'The once-per-session guard prevents Sentry spam when the '
            'app keeps re-probing the GPU on every recovery / startup.',
      );
    });

    test('clearGpuCache re-arms the guard so a second post-cache-clear '
        'blind detection captures again', () async {
      hw.setProcessRunnerForTesting((_, _) async => _empty());

      await hw.detectGpuWindowsForTesting();
      await CrashReporter.instance!.flush();
      expect(_capturedEvents, hasLength(1));

      // Simulate a server-binary-recovery cache invalidation: the next
      // probe should be observable in Sentry independently from the
      // first one so we know the recovery-time detection is also blind.
      hw.clearGpuCache();
      await hw.detectGpuWindowsForTesting();
      await CrashReporter.instance!.flush();

      expect(
        _capturedEvents,
        hasLength(2),
        reason:
            'clearGpuCache must re-arm the once-per-session guard so a '
            'post-recovery blind detection produces a fresh capture.',
      );
    });

    test('captureGpuDetectionFailureOnce passes the reason field through to '
        'the Sentry event extras', () async {
      hw.captureGpuDetectionFailureOnce(reason: 'unit-test-reason');
      await CrashReporter.instance!.flush();

      expect(_capturedEvents, hasLength(1));
      final extras = _capturedEvents.single.contexts['extras'] as Map?;
      expect(extras?['reason'], 'unit-test-reason');
    });
  });
}
