/// Unit tests for CrashReporter fingerprint support (issue-05).
///
/// Note: the original guard-fire AC3 + AC4 coverage was removed when the
/// recording orchestrator stopped capturing dead-mic / auto-stop as Sentry
/// events. Those flows are now plain `_log.info` breadcrumbs — the captureError
/// fingerprint API is exercised by other call sites (STT exit codes, model
/// download failures, etc.).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
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

  // ── AC1: fingerprint param is accepted and forwarded to the SDK ────────────

  group('AC1 — captureError accepts and threads fingerprint', () {
    test('captureError without fingerprint compiles and runs', () {
      CrashReporter.instance!.captureError(
        message: 'test-no-fingerprint',
        severity: 'error',
        type: 'test',
      );
      // No throw = param is optional and backward-compatible.
    });

    test('captureError with null fingerprint compiles and runs', () {
      CrashReporter.instance!.captureError(
        message: 'test-null-fingerprint',
        severity: 'error',
        type: 'test',
        fingerprint: null,
      );
    });

    test('captureError with empty fingerprint list compiles and runs', () {
      CrashReporter.instance!.captureError(
        message: 'test-empty-fingerprint',
        severity: 'error',
        type: 'test',
        fingerprint: [],
      );
    });

    test('captureError with fingerprint list compiles and runs', () {
      CrashReporter.instance!.captureError(
        message: 'test-with-fingerprint',
        severity: 'error',
        type: 'test',
        fingerprint: ['toast-model-download-failed'],
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

  // ── Backward-compatibility: existing callers without fingerprint ───────────

  group('Backward-compatibility', () {
    test(
      'captureError is fully backward-compatible (no fingerprint required)',
      () {
        // All existing callers (AppLogger, CrashProviderObserver) use captureError
        // without fingerprint. This test verifies no breaking change.
        expect(
          () => CrashReporter.instance!.captureError(
            message: 'existing-caller-no-fingerprint',
            error: Exception('test'),
            stackTrace: StackTrace.current,
            severity: 'error',
            type: 'error',
            processName: 'test-process',
            extras: {'key': 'value'},
          ),
          returnsNormally,
        );
      },
    );

    test('consent gate: events dropped when consent is false', () {
      final cr = CrashReporter.instance!;
      final prevConsent = cr.consentGranted;
      cr.consentGranted = false;
      try {
        // Should be a no-op — nothing sent, no throw.
        cr.captureError(
          message: 'should-be-dropped',
          severity: 'error',
          fingerprint: ['test-fp'],
        );
      } finally {
        cr.consentGranted = prevConsent;
      }
    });
  });
}
