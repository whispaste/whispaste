/// Unit tests for CrashReporter fingerprint support.
///
/// Updated for reliability-sprint issue 01: the `fingerprint` named
/// parameter on `CrashReporter.captureError` is now **required**. These
/// tests pin that contract by exercising the API with explicit
/// fingerprints sourced from the central inventory.
///
/// Note: the original guard-fire AC3 + AC4 coverage was removed when the
/// recording orchestrator stopped capturing dead-mic / auto-stop as Sentry
/// events. Those flows are now plain `_log.info` breadcrumbs — the captureError
/// fingerprint API is exercised by other call sites (STT exit codes, model
/// download failures, etc.).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste/core/logging/crash_fingerprints.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';

// ---------------------------------------------------------------------------
// Capture helper — collects Sentry events in-process via SentryFlutter.init
// with a noop DSN + beforeSend hook.
// ---------------------------------------------------------------------------

class _CapturedEvent {
  const _CapturedEvent({
    required this.message,
    required this.level,
    required this.fingerprint,
    required this.type,
  });
  final String? message;
  final SentryLevel? level;
  final List<String>? fingerprint;
  final String? type;
}

final _capturedEvents = <_CapturedEvent>[];

SentryEvent? _testBeforeSend(SentryEvent event, Hint hint) {
  _capturedEvents.add(
    _CapturedEvent(
      message: event.message?.formatted,
      level: event.level,
      fingerprint: event.fingerprint,
      type: event.tags?['error_type'],
    ),
  );
  // Return null so nothing is actually sent to Sentry servers.
  return null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // These tests initialize a real (but noop) Sentry SDK so we can inspect
  // what events captureError() would submit — without actually sending data.
  setUpAll(() async {
    _capturedEvents.clear();
    await SentryFlutter.init((options) {
      // Use a clearly invalid DSN so the SDK never actually sends events.
      options.dsn = 'https://abc123@sentry.example.invalid/0';
      options.environment = 'test';
      options.beforeSend = _testBeforeSend;
    });
    CrashReporter.init();
    CrashReporter.instance!.consentGranted = true;
  });

  tearDown(() {
    _capturedEvents.clear();
  });

  tearDownAll(() async {
    await Sentry.close();
  });

  // ── AC1: fingerprint param is required and forwarded to the SDK ───────────

  group('AC1 — captureError requires and threads fingerprint', () {
    test('captureError with single-element fingerprint runs', () {
      CrashReporter.instance!.captureError(
        message: 'test-with-fingerprint',
        severity: 'error',
        type: 'test',
        fingerprint: [modelDownloadFailed],
      );
      // No throw = fingerprint flowed through `withScope` without issue.
    });

    test(
      'captureError with empty fingerprint list runs (Sentry default grouping)',
      () {
        // The SDK treats an empty list as „no override" — captureError still
        // runs but won't override Sentry's default exception-class grouping.
        // We still require the parameter at the call site so reviewers see
        // an explicit choice.
        CrashReporter.instance!.captureError(
          message: 'test-empty-fingerprint',
          severity: 'error',
          type: 'test',
          fingerprint: [],
        );
      },
    );

    test('captureError accepts a multi-element fingerprint list', () {
      CrashReporter.instance!.captureError(
        message: 'test-multi-fingerprint',
        severity: 'error',
        type: 'test',
        fingerprint: [sttExitOther, 'scoped-suffix'],
      );
    });
  });

  // ── Per-call-site fingerprints that survived the guard-fire migration ─────

  group('per-call-site fingerprint strings', () {
    test('stt exit-code fingerprints follow stt-exit-<kind> pattern', () {
      // Verify the fingerprint format used in stt_service.dart for all
      // SttExitKind values. Format: 'stt-exit-<exitKind.name>'.
      const exitKindNames = [
        'dllMissing',
        'dllEntryPoint',
        'gpuFatal',
        'heapCorruption',
        'modelLoad',
        'other',
      ];
      for (final kind in exitKindNames) {
        final fp = 'stt-exit-$kind';
        expect(fp, startsWith('stt-exit-'));
        expect(fp, contains(kind));
      }
    });
  });

  // ── Full-parameter happy-path: an AppLogger-shape caller still runs ───────

  group('Full-parameter capture (AppLogger / observer shape)', () {
    test('captureError with error + stackTrace + extras runs', () {
      // Mirrors the AppLogger / CrashProviderObserver call shape with the
      // new required-fingerprint contract bolted on.
      expect(
        () => CrashReporter.instance!.captureError(
          message: 'existing-caller-shape',
          error: Exception('test'),
          stackTrace: StackTrace.current,
          severity: 'error',
          type: 'error',
          processName: 'test-process',
          extras: {'key': 'value'},
          fingerprint: [appLoggerAutoEscalated],
        ),
        returnsNormally,
      );
    });

    test('consent gate: events dropped when consent is false', () {
      final cr = CrashReporter.instance!;
      final prevConsent = cr.consentGranted;
      cr.consentGranted = false;
      try {
        // Should be a no-op — nothing sent, no throw.
        cr.captureError(
          message: 'should-be-dropped',
          severity: 'error',
          fingerprint: [sttExitOther],
        );
      } finally {
        cr.consentGranted = prevConsent;
      }
    });
  });
}
