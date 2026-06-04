/// Contract test: an `UpdateNotifier.checkForUpdate()` network failure
/// (e.g. `SocketException`, GitHub rate-limit) must NOT escalate to
/// Sentry via `CrashReporter.captureError`.
///
/// Rationale: see `.scratch/reliability-sprint/prd.md` — Modul 6. The
/// update poll happens on app start regardless of user intent and runs
/// against a third-party API the user cannot influence; capturing those
/// failures burned Free-Tier issue quota for zero diagnostic value.
///
/// Strategy:
/// - Inject a Dio with a request interceptor that synthesises a
///   `DioException(connectionError)` wrapping a real `SocketException`.
/// - Install a real Sentry SDK (noop DSN) + record every event the
///   `beforeSend` hook receives.
/// - Drive `UpdateNotifier.checkForUpdate()` and assert:
///   - the notifier reaches `UpdatePhase.error` (network failure observed);
///   - zero Sentry events were captured (the contract under test).
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/update_service.dart';

// ---------------------------------------------------------------------------
// Sentry capture spy — records every event that survives `beforeSend`.
// ---------------------------------------------------------------------------

final _capturedEvents = <SentryEvent>[];

SentryEvent? _spyBeforeSend(SentryEvent event, Hint hint) {
  _capturedEvents.add(event);
  // Returning null suppresses transmission. We only care that the SDK
  // saw the event at all (which means CrashReporter.captureError fired).
  return null;
}

// ---------------------------------------------------------------------------
// Dio interceptor that fakes a SocketException network failure.
// ---------------------------------------------------------------------------

class _SocketExceptionInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const SocketException('Network is unreachable (simulated)'),
        message: 'Network is unreachable (simulated)',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HttpClientAdapter that synthesises a fixed HTTP status (no real socket).
// Lets us drive the *production* Dio config — including the `addSentry()`
// FailedRequestInterceptor — against a 5xx response.
// ---------------------------------------------------------------------------

class _StatusCodeAdapter implements HttpClientAdapter {
  _StatusCodeAdapter(this.statusCode);
  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"message":"simulated upstream failure"}',
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() async {
    await SentryFlutter.init((options) {
      options.dsn = 'https://abc123@sentry.example.invalid/0';
      options.environment = 'test';
      options.beforeSend = _spyBeforeSend;
    });
    CrashReporter.init();
    CrashReporter.instance!.consentGranted = true;
  });

  setUp(() {
    _capturedEvents.clear();
    // Make sure the deploy channel is one where the update check actually
    // runs (the `store` channel short-circuits before any HTTP call).
    deployChannelOverride = DeployChannel.installer;
  });

  tearDown(() {
    UpdateNotifier.dioOverrideForTesting = null;
    deployChannelOverride = null;
  });

  tearDownAll(() async {
    await Sentry.close();
  });

  test('checkForUpdate on SocketException reaches UpdatePhase.error '
      'WITHOUT capturing a Sentry event', () async {
    // Inject a Dio that fails every request with a SocketException-shaped
    // DioException — mirrors the GitHub `releases/latest` outage path.
    final injectedDio = Dio()..interceptors.add(_SocketExceptionInterceptor());
    UpdateNotifier.dioOverrideForTesting = injectedDio;

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Trigger the update check.
    await container.read(updateProvider.notifier).checkForUpdate();

    // Observable behaviour 1 — the notifier reports the failure to its UI.
    final state = container.read(updateProvider);
    expect(
      state.phase,
      UpdatePhase.error,
      reason:
          'A SocketException must still surface as an error state — '
          'the contract change is "no Sentry escalation", not '
          '"silent failure".',
    );

    // Observable behaviour 2 (the contract under test) — no Sentry event.
    // Give any fire-and-forget capture a tick to land. CrashReporter
    // sends through Sentry.captureMessage/Exception which are async.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      _capturedEvents,
      isEmpty,
      reason:
          'Update-check network failures must NOT escalate to Sentry. '
          'Observed events: '
          '${_capturedEvents.map((e) => e.message?.formatted ?? e.throwable).toList()}',
    );
  });

  test('checkForUpdate on GitHub 5xx via the PRODUCTION Dio config '
      'WITHOUT capturing a Sentry event', () async {
    // Exercises the real `buildUpdateDio()` — including its `addSentry()`
    // interceptor — against a 503. With `captureFailedRequests` left at its
    // default, the FailedRequestInterceptor (status range 500–599) would
    // auto-capture this; the production config disables it. Guards the
    // interceptor-path half of the Modul-6 contract that the catch-block
    // fix alone did not cover (FLUTTER_WHISPASTE-72).
    final productionDio = UpdateNotifier.buildUpdateDio()
      ..httpClientAdapter = _StatusCodeAdapter(503);
    UpdateNotifier.dioOverrideForTesting = productionDio;

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(updateProvider.notifier).checkForUpdate();

    final state = container.read(updateProvider);
    expect(
      state.phase,
      UpdatePhase.error,
      reason: 'a 5xx must still surface as a graceful error state',
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      _capturedEvents,
      isEmpty,
      reason:
          'A 5xx during the update check must NOT escalate to Sentry via the '
          'addSentry() FailedRequestInterceptor. Observed events: '
          '${_capturedEvents.map((e) => e.message?.formatted ?? e.throwable).toList()}',
    );
  });
}
