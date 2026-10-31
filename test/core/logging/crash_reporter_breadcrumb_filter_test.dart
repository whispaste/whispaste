/// A secret inside a breadcrumb removes that breadcrumb only. Breadcrumbs
/// carry the log lines around a crash, so one log line with a token-like
/// word must not cost the crash its report (the whole event used to be
/// dropped). A secret in the exception or message still drops the event.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';

SentryEvent _crash({
  required String exceptionValue,
  required List<String> breadcrumbs,
}) => SentryEvent(
  level: SentryLevel.error,
  exceptions: [SentryException(type: 'StateError', value: exceptionValue)],
  breadcrumbs: [
    for (final text in breadcrumbs)
      Breadcrumb(message: text, level: SentryLevel.info),
  ],
  fingerprint: const ['breadcrumb-filter-test'],
);

List<String?> _messages(SentryEvent event) => [
  for (final b in event.breadcrumbs ?? const <Breadcrumb>[]) b.message,
];

void main() {
  setUp(CrashReporter.resetThrottlesForTesting);

  test('a breadcrumb with a token is removed and the crash is still sent', () {
    final event = _crash(
      exceptionValue: 'Bad state: model not loaded',
      breadcrumbs: const [
        'stt: model loaded',
        'settings: token=abc123secret',
        'stt: retry scheduled',
      ],
    );

    final sent = CrashReporter.beforeSend(event, Hint());

    expect(sent, isNotNull, reason: 'the crash must not be dropped');
    final messages = _messages(sent!);
    expect(messages, ['stt: model loaded', 'stt: retry scheduled']);
  });

  test('a secret in the exception value still drops the whole event', () {
    final event = _crash(
      exceptionValue: 'request failed with api_key=supersecretvalue',
      breadcrumbs: const ['stt: model loaded'],
    );

    expect(CrashReporter.beforeSend(event, Hint()), isNull);
  });

  test('clean breadcrumbs are kept unchanged', () {
    final event = _crash(
      exceptionValue: 'Bad state: model not loaded',
      breadcrumbs: const ['stt: model loaded', 'hotkey: registered'],
    );

    final sent = CrashReporter.beforeSend(event, Hint());

    expect(sent, isNotNull);
    expect(_messages(sent!), ['stt: model loaded', 'hotkey: registered']);
  });
}
