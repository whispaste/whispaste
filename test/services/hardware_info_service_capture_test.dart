/// Capture-pipeline test for the GPU-detection-failed path.
///
/// Hardware-debugging audit (2026-05): a Windows host that cannot reach
/// `wmic` or `powershell` (corporate AV, group-policy lockdown, broken WMI)
/// falls back to the CPU. That fallback works, so it is no Sentry event
/// (rule 2026-10-27: Sentry receives crashes and critical errors only); the
/// warning stays in the local log and as a breadcrumb for a later real error.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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

  test(
    'blind GPU detection falls back to the CPU without a Sentry event',
    () async {
      hw.setProcessRunnerForTesting((_, _) async => _empty());

      await hw.detectGpuWindowsForTesting();
      await CrashReporter.instance!.flush();

      expect(_capturedEvents, isEmpty);
    },
  );
}
