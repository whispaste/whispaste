/// Guards the shared Sentry error quota (rule 2026-10-27): Sentry receives
/// crashes and errors only, and one error repeating on one device cannot use
/// up the organisation's monthly budget.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';

SentryEvent _event(String text, {SentryLevel? level = SentryLevel.error}) =>
    SentryEvent(
      level: level,
      message: SentryMessage(text),
      fingerprint: const ['app-logger-auto-escalated'],
    );

bool _sent(SentryEvent event) =>
    CrashReporter.beforeSend(event, Hint()) != null;

void main() {
  setUp(CrashReporter.resetThrottlesForTesting);

  group('beforeSend level filter', () {
    test('drops info and warning events', () {
      expect(_sent(_event('GPU vendor', level: SentryLevel.info)), isFalse);
      expect(_sent(_event('fallback', level: SentryLevel.warning)), isFalse);
      expect(_sent(_event('trace', level: SentryLevel.debug)), isFalse);
    });

    test('keeps errors, fatals and events without a level', () {
      expect(_sent(_event('broken')), isTrue);
      expect(_sent(_event('crash', level: SentryLevel.fatal)), isTrue);
      expect(_sent(_event('unhandled', level: null)), isTrue);
    });
  });

  group('per-session ceilings', () {
    test('the same error is sent three times per session', () {
      final results = [for (var i = 0; i < 5; i++) _sent(_event('same'))];
      expect(results, [true, true, true, false, false]);
    });

    test('errors sharing the catch-all fingerprint keep their own share', () {
      for (var i = 0; i < 3; i++) {
        expect(_sent(_event('first')), isTrue);
      }
      expect(_sent(_event('first')), isFalse);
      expect(_sent(_event('second')), isTrue);
    });

    test('a session sends at most 30 events in total', () {
      var now = DateTime.now();
      CrashReporter.clock = () => now;
      addTearDown(() => CrashReporter.clock = DateTime.now);
      var sent = 0;
      // Batches of 10 stay under the 10-per-2-s cascade throttle.
      for (var batch = 0; batch < 4; batch++) {
        for (var i = 0; i < 10; i++) {
          if (_sent(_event('error $batch-$i'))) sent++;
        }
        now = now.add(const Duration(milliseconds: 2100));
      }
      expect(sent, 30);
    });

    test('a new session (init) starts with a fresh share', () async {
      for (var i = 0; i < 3; i++) {
        _sent(_event('again'));
      }
      expect(_sent(_event('again')), isFalse);

      await SentryFlutter.init((options) {
        options.dsn = 'https://abc123@sentry.example.invalid/0';
        options.environment = 'test';
      });
      CrashReporter.init();
      addTearDown(() => CrashReporter.instance?.dispose());
      expect(_sent(_event('again')), isTrue);
    });
  });
}
