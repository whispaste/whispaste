/// CrashReporter.beforeSendTransaction must not forward log breadcrumbs.
///
/// Sentry's scope copies the breadcrumb ring onto every event, including
/// performance transactions. Error events run through the sensitive-data
/// scrub in [CrashReporter.beforeSend]; transactions did not, so the log
/// lines would have reached Sentry unchecked. Traces only need timings, so
/// the breadcrumbs are dropped from them entirely.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';

void main() {
  tearDown(() async {
    await CrashReporter.instance?.dispose();
    await Sentry.close();
  });

  test('strips scope breadcrumbs from performance transactions', () async {
    final sent = Completer<SentryTransaction?>();
    await SentryFlutter.init((options) {
      options.dsn = 'https://abc123@sentry.example.invalid/0';
      options.environment = 'test';
      options.tracesSampleRate = 1.0;
      options.beforeSendTransaction = (transaction, hint) {
        final result = CrashReporter.beforeSendTransaction(transaction, hint);
        if (!sent.isCompleted) sent.complete(result);
        // Never hand anything to the (invalid) transport.
        return null;
      };
    });
    CrashReporter.init();
    CrashReporter.instance!.consentGranted = true;

    await Sentry.addBreadcrumb(Breadcrumb(message: 'Some log line'));
    final tx = Sentry.startTransaction('ui.load', 'navigation');
    await tx.finish();

    final result = await sent.future.timeout(const Duration(seconds: 5));
    expect(result, isNotNull, reason: 'consent granted → transaction kept');
    expect(result!.breadcrumbs ?? const <Breadcrumb>[], isEmpty);
  });
}
