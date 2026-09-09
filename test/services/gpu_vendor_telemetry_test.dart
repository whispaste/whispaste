/// Tests for the GPU-vendor-distribution telemetry signal (Ticket 10).
///
/// Feeds a later, data-driven CUDA-build decision — this ticket only adds
/// the anonymous "vendor" + "platform" signal, over the *existing* opt-out
/// Sentry channel (same consent gate / anonymous device id as
/// `hw.initHardwareInfoTelemetry`'s gpuDetectionFailed path — see
/// `hardware_info_service_capture_test.dart`, whose capture-pipeline pattern
/// this file mirrors).
///
/// Two concerns are pinned here:
/// - the OS gate (Windows/Linux only — macOS has a fundamentally different
///   GPU landscape and is not a target of the CUDA-build decision) as a
///   pure predicate, testable without mocking `Platform`;
/// - the Sentry payload shape: exactly the two documented fields, nothing
///   else — regression protection against accidentally capturing PII.
library;

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

const _nvidiaGpu = hw.GpuInfo(
  vendor: hw.GpuVendor.nvidia,
  name: 'NVIDIA RTX 4090',
  vramMB: 24576,
  cudaAvailable: true,
  vulkanAvailable: true,
);

void main() {
  group('shouldReportGpuVendorTelemetry — OS gate (pure)', () {
    test('true for windows and linux', () {
      expect(hw.shouldReportGpuVendorTelemetry('windows'), isTrue);
      expect(hw.shouldReportGpuVendorTelemetry('linux'), isTrue);
    });

    test('false for macos (PRD: different GPU landscape, not a target)', () {
      expect(hw.shouldReportGpuVendorTelemetry('macos'), isFalse);
    });

    test('false for any other/unknown platform string', () {
      expect(hw.shouldReportGpuVendorTelemetry('android'), isFalse);
      expect(hw.shouldReportGpuVendorTelemetry(''), isFalse);
    });
  });

  group('reportGpuVendorTelemetry — capture pipeline', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUpAll(() async {
      await SentryFlutter.init((options) {
        options.dsn = 'https://abc123@sentry.example.invalid/0';
        options.environment = 'test';
        options.beforeSend = _spyBeforeSend;
      });
      CrashReporter.init();
      CrashReporter.instance!.consentGranted = true;
    });

    tearDownAll(() async {
      await CrashReporter.instance?.dispose();
    });

    setUp(() {
      _capturedEvents.clear();
      hw.resetGpuVendorTelemetryForTesting();
    });

    tearDown(() {
      hw.resetGpuVendorTelemetryForTesting();
    });

    test(
      'Windows/Linux: exactly one info event with only the documented fields',
      () async {
        hw.reportGpuVendorTelemetry(_nvidiaGpu, operatingSystem: 'windows');
        await CrashReporter.instance!.flush();

        expect(_capturedEvents, hasLength(1));
        final ev = _capturedEvents.single;

        expect(ev.fingerprint, [gpuVendorTelemetry]);
        expect(ev.level, SentryLevel.info);

        final extrasCtx = ev.contexts['extras'] as Map?;
        expect(extrasCtx, isNotNull);
        // Regression protection: exactly {vendor, platform} — no device
        // name, no serial, no other field ever sneaks in here.
        expect(extrasCtx!.keys.toSet(), {'vendor', 'platform'});
        expect(extrasCtx['vendor'], 'nvidia');
        expect(extrasCtx['platform'], 'windows');
      },
    );

    test('Linux is also reported (not just Windows)', () async {
      hw.reportGpuVendorTelemetry(_nvidiaGpu, operatingSystem: 'linux');
      await CrashReporter.instance!.flush();

      expect(_capturedEvents, hasLength(1));
      expect(
        (_capturedEvents.single.contexts['extras'] as Map)['platform'],
        'linux',
      );
    });

    test('macOS: no event is sent at all (OS gate)', () async {
      hw.reportGpuVendorTelemetry(_nvidiaGpu, operatingSystem: 'macos');
      await CrashReporter.instance!.flush();

      expect(_capturedEvents, isEmpty);
    });

    test('once-per-session guard: a second call within the same session does '
        'NOT add a second event', () async {
      hw.reportGpuVendorTelemetry(_nvidiaGpu, operatingSystem: 'windows');
      hw.reportGpuVendorTelemetry(_nvidiaGpu, operatingSystem: 'linux');
      await CrashReporter.instance!.flush();

      expect(_capturedEvents, hasLength(1));
    });

    test('resetGpuVendorTelemetryForTesting re-arms the guard for a fresh '
        'session', () async {
      hw.reportGpuVendorTelemetry(_nvidiaGpu, operatingSystem: 'windows');
      await CrashReporter.instance!.flush();
      expect(_capturedEvents, hasLength(1));

      hw.resetGpuVendorTelemetryForTesting();
      hw.reportGpuVendorTelemetry(_nvidiaGpu, operatingSystem: 'linux');
      await CrashReporter.instance!.flush();

      expect(_capturedEvents, hasLength(2));
    });

    test('respects the existing opt-out consent gate — no event when '
        'consent is revoked', () async {
      CrashReporter.instance!.consentGranted = false;
      addTearDown(() => CrashReporter.instance!.consentGranted = true);

      hw.reportGpuVendorTelemetry(_nvidiaGpu, operatingSystem: 'windows');
      await CrashReporter.instance!.flush();

      expect(_capturedEvents, isEmpty);
    });
  });
}
