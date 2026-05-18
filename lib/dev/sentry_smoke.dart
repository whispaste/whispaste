/// Debug-only Sentry pipeline smoke verification hook.
///
/// Fires ONE caught exception + ONE manual transaction (with a Drift query
/// and a Dio call inside) so the post-v9-upgrade pipeline can be observed
/// end-to-end in the Sentry dashboard.
///
/// This file is intentionally short-lived: it is added in the smoke-verify
/// commit and removed again in the cleanup commit. It MUST NOT be referenced
/// from any production code path.
library;

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_dio/sentry_dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/data/database.dart';
import '../core/logging/crash_reporter.dart';

const _smokeOp = 'smoke.test';

String _newCorrelation() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final rand = math.Random.secure().nextInt(0xFFFFFFFF).toRadixString(16);
  return 'smoke-$ts-$rand';
}

void _logCorrelation(String correlation, {required bool consent}) {
  final line =
      '[sentry-smoke] correlation=$correlation consent=$consent '
      'kDebugMode=$kDebugMode';
  // dart:developer log shows up in IDE / DTD log streams.
  dev.log(line, name: 'SentrySmoke');
  // Plain print so it surfaces in `flutter run` stdout / get_app_logs.
  // ignore: avoid_print
  print(line);
}

Future<void> _runSmokeBody(String correlation, HistoryDatabase db) async {
  // Tag scope so search_events can find the event + transaction by tag.
  Sentry.configureScope((scope) {
    scope.setTag('smoke-correlation', correlation);
  });

  // Fire a caught exception — produces an error event.
  try {
    throw Exception('sentry v9 smoke $correlation');
  } catch (e, st) {
    await Sentry.captureException(e, stackTrace: st);
  }

  // Manual transaction that hosts a Drift span and a Dio span.
  final tx = Sentry.startTransaction(
    'smoke-$correlation',
    _smokeOp,
    bindToScope: true,
  );
  tx.setTag('smoke-correlation', correlation);
  try {
    // (a) Drift round-trip — SELECT 1 via customSelect.
    try {
      await db.customSelect('SELECT 1 AS v').get();
    } on Object catch (e, st) {
      dev.log(
        'smoke drift select failed: $e',
        name: 'SentrySmoke',
        error: e,
        stackTrace: st,
      );
    }

    // (b) Dio call — produces a Dio breadcrumb + HTTP span.
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
      dio.addSentry();
      await dio.get<dynamic>('https://httpbin.org/status/200');
    } on Object catch (e, st) {
      dev.log(
        'smoke dio call failed: $e',
        name: 'SentrySmoke',
        error: e,
        stackTrace: st,
      );
    }
  } finally {
    await tx.finish(status: const SpanStatus.ok());
  }
}

/// Fires the smoke hook with consent ON (default).
///
/// kDebugMode-guarded — no-op in release builds. The hook is fire-and-forget;
/// failures inside are swallowed so the host app never crashes from a smoke
/// test attempt.
Future<void> fireSentrySmokeIfDebug({
  required HistoryDatabase database,
  Duration delay = const Duration(seconds: 5),
}) async {
  if (!kDebugMode) return;
  await Future<void>.delayed(delay);
  final correlation = _newCorrelation();
  _logCorrelation(correlation, consent: true);
  try {
    CrashReporter.instance?.consentGranted = true;
    await _runSmokeBody(correlation, database);
  } on Object catch (e, st) {
    dev.log(
      'smoke hook failed (consent=true): $e',
      name: 'SentrySmoke',
      error: e,
      stackTrace: st,
    );
  }
}

/// Fires the smoke hook with consent FORCED OFF.
///
/// Used to prove that the GDPR consent gate blocks transmission end-to-end —
/// when this fires, NO event with the printed correlation should arrive in
/// Sentry. kDebugMode-guarded.
Future<void> fireSentrySmokeIfDebugWithoutConsent({
  required HistoryDatabase database,
  Duration delay = const Duration(seconds: 5),
}) async {
  if (!kDebugMode) return;
  await Future<void>.delayed(delay);
  final correlation = _newCorrelation();
  _logCorrelation(correlation, consent: false);
  try {
    CrashReporter.instance?.consentGranted = false;
    await _runSmokeBody(correlation, database);
  } on Object catch (e, st) {
    dev.log(
      'smoke hook failed (consent=false): $e',
      name: 'SentrySmoke',
      error: e,
      stackTrace: st,
    );
  }
}
