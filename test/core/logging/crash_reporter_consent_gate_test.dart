/// Unit tests for CrashReporter.tracesSampler — the primary consent gate
/// for Sentry performance transactions.
///
/// Background: a smoke test on 2026-05-18 against sentry_flutter 9.20 showed
/// that with `bindToScope:true` transactions, child spans (incl. SQL payloads
/// from sentry_drift's SentryQueryInterceptor and Dio HTTP spans) could reach
/// Sentry even after `beforeSendTransaction` returned null. The tracesSampler
/// closes that window by refusing to start a trace when consent is revoked —
/// no trace, no spans, nothing to leak.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';

void main() {
  group('tracesSampler — runtime consent gate', () {
    tearDown(() async {
      // Tests that initialise the singleton dispose it so the next test starts
      // from a clean _instance==null state.
      await CrashReporter.instance?.dispose();
    });

    test('returns null when no CrashReporter instance exists (pre-init)', () {
      // Before CrashReporter.init() has run, the singleton is null. Sampler
      // must fail-open: returning null lets the SDK fall through to the
      // configured tracesSampleRate, so very-early-bootstrap transactions
      // still follow normal sampling. The beforeSend / beforeSendTransaction
      // callbacks become the safety net once consent is known.
      expect(CrashReporter.instance, isNull);
      expect(CrashReporter.tracesSampler(_dummyContext()), isNull);
    });

    test('returns null when consent is granted', () async {
      await _initSentryNoop();
      CrashReporter.init();
      CrashReporter.instance!.consentGranted = true;

      expect(CrashReporter.tracesSampler(_dummyContext()), isNull);
    });

    test('returns 0.0 when consent is revoked', () async {
      await _initSentryNoop();
      CrashReporter.init();
      CrashReporter.instance!.consentGranted = false;

      expect(CrashReporter.tracesSampler(_dummyContext()), 0.0);
    });

    test('flips with the consent setter (runtime toggle behaviour)', () async {
      await _initSentryNoop();
      CrashReporter.init();
      final cr = CrashReporter.instance!;

      cr.consentGranted = true;
      expect(CrashReporter.tracesSampler(_dummyContext()), isNull);

      cr.consentGranted = false;
      expect(CrashReporter.tracesSampler(_dummyContext()), 0.0);

      cr.consentGranted = true;
      expect(CrashReporter.tracesSampler(_dummyContext()), isNull);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Minimal SentrySamplingContext for the sampler's signature. We use the
/// static-mode factory because the app keeps the v9 default
/// (`SentryTraceLifecycle.static`); the sampler's consent path never reads
/// anything off the context anyway.
SentrySamplingContext _dummyContext() {
  return SentrySamplingContext.forTransaction(
    SentryTransactionContext('dummy', 'test'),
  );
}

/// Initialises Sentry with an invalid DSN so no events are transmitted.
/// Required because CrashReporter.init() calls Sentry.configureScope, which
/// asserts the SDK is initialised.
Future<void> _initSentryNoop() async {
  await SentryFlutter.init((options) {
    options.dsn = 'https://abc123@sentry.example.invalid/0';
    options.environment = 'test';
  });
}
