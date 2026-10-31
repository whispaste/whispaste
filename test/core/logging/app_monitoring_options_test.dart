/// Privacy guard for the Sentry options WhisPaste ships with.
///
/// Crash reports and performance traces are opt-out (`errorReporting`
/// defaults to true), which is only acceptable because they never carry
/// audio, text, history, tags or notes (`docs/zielgruppe.md`). These tests
/// pin the options that would otherwise attach on-screen content.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste/core/logging/app_monitoring.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';

void main() {
  group('AppMonitoring.configureSentryOptions', () {
    late SentryFlutterOptions options;

    setUp(() {
      options = SentryFlutterOptions();
      AppMonitoring.configureSentryOptions(options);
    });

    test('never attaches the view hierarchy (widget keys can carry '
        'user-derived identifiers)', () {
      // ignore: experimental_member_use
      expect(options.attachViewHierarchy, isFalse);
    });

    test('never attaches screenshots', () {
      expect(options.attachScreenshot, isFalse);
    });

    test('never sends default PII', () {
      expect(options.sendDefaultPii, isFalse);
    });

    test('routes errors and transactions through the CrashReporter gates', () {
      expect(options.beforeSend, same(CrashReporter.beforeSend));
      expect(
        options.beforeSendTransaction,
        same(CrashReporter.beforeSendTransaction),
      );
      expect(options.tracesSampler, same(CrashReporter.tracesSampler));
    });

    test('scrubs breadcrumbs as they are recorded, not only in events', () {
      expect(options.beforeBreadcrumb, same(CrashReporter.beforeBreadcrumb));
    });

    test('native app-hang reports start at 5 s, not the SDK default 2 s '
        '(shared Sentry error quota, rule 2026-10-27)', () {
      expect(options.appHangTimeoutInterval, const Duration(seconds: 5));
    });

    test('sends crashes and errors only: no performance traces, no '
        'session tracking', () {
      expect(options.tracesSampleRate, 0.0);
      expect(options.enableAutoPerformanceTracing, isFalse);
      expect(options.enableAutoSessionTracking, isFalse);
    });

    test('never propagates trace headers to any host', () {
      expect(options.tracePropagationTargets, isEmpty);
    });

    test('debug builds skip the native SDK, which crashes when a hot '
        'restart initialises it a second time', () {
      // Tests run in debug mode; release builds keep native capture.
      expect(options.autoInitializeNativeSdk, isFalse);
    });
  });
}
