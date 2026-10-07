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

    test('never propagates trace headers to any host', () {
      expect(options.tracePropagationTargets, isEmpty);
    });
  });
}
