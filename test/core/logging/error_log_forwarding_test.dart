/// Framework and zone errors reach the app log, with error reporting on or
/// off, and a storm of them is throttled (#439).
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste/core/logging/app_monitoring.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';
import 'package:whispaste/core/logging/crash_reporting_consent.dart';
import 'package:whispaste/core/logging/error_log_forwarding.dart';

// Models the wrapper received from Drift's database isolate, without using
// its private constructor. The cause remains a typed SQLite exception.
class _RemoteDatabaseError implements DriftRemoteException {
  _RemoteDatabaseError(this.remoteCause);

  @override
  final Object remoteCause;

  @override
  StackTrace? get remoteStackTrace => StackTrace.empty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final records = <LogRecord>[];
  late StreamSubscription<LogRecord> sub;
  late Level previousLevel;

  List<LogRecord> uncaught() =>
      records.where((r) => r.loggerName == 'UncaughtError').toList();

  setUp(() {
    records.clear();
    previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() async {
    await sub.cancel();
    Logger.root.level = previousLevel;
  });

  FlutterErrorDetails details(Object error) =>
      FlutterErrorDetails(exception: error, stack: StackTrace.empty);

  group('framework errors', () {
    test('are logged as a warning and still reach the next handler', () {
      final seen = <FlutterErrorDetails>[];
      final handler = wrapFlutterErrorHandler(
        seen.add,
        throttle: ErrorLogThrottle(),
      );

      handler(details(StateError('build failed')));

      expect(seen, hasLength(1));
      final logged = uncaught().single;
      // Warning, not severe: a severe line would become a Sentry event.
      expect(logged.level, Level.WARNING);
      expect(logged.message, contains('StateError'));
      // Kind and stack only, never the message text.
      expect(logged.error, isNull);
      expect(logged.stackTrace, isNotNull);
    });
  });

  group('zone errors', () {
    test('are logged and keep the previous handler result', () {
      final handler = wrapPlatformErrorHandler(
        (_, _) => true,
        throttle: ErrorLogThrottle(),
      );

      expect(handler(const FormatException('x'), StackTrace.empty), isTrue);
      expect(uncaught().single.message, contains('FormatException'));
    });

    test('without a previous handler stay unhandled after logging', () {
      final handler = wrapPlatformErrorHandler(
        null,
        throttle: ErrorLogThrottle(),
      );

      expect(handler(StateError('lost'), StackTrace.empty), isFalse);
      expect(uncaught(), hasLength(1));
    });
  });

  test('SQLite result codes survive remote wrappers without private data', () {
    final sqlite = SqliteException(
      extendedResultCode: 13,
      message: 'PRIVATE message',
      causingStatement: 'INSERT PRIVATE statement',
      parametersToStatement: const ['PRIVATE argument'],
    );
    for (final error in [sqlite, _RemoteDatabaseError(sqlite)]) {
      records.clear();
      wrapPlatformErrorHandler(null, throttle: ErrorLogThrottle())(
        error,
        StackTrace.empty,
      );
      final record = uncaught().single;
      expect(record.message, contains('SqliteException(code 13)'));
      expect(record.message, isNot(contains('PRIVATE')));
      expect(record.error, isNull);
      records.clear();
      wrapFlutterErrorHandler((_) {}, throttle: ErrorLogThrottle())(
        details(error),
      );
      expect(uncaught().single.message, contains('SqliteException(code 13)'));
      expect(uncaught().single.message, isNot(contains('PRIVATE')));
      expect(uncaught().single.error, isNull);
    }
  });

  group('storm throttle', () {
    test('logs a few, one notice, then the dropped count once the window '
        'has passed', () {
      fakeAsync((async) {
        final handler = wrapPlatformErrorHandler(
          (_, _) => true,
          throttle: ErrorLogThrottle(
            maxPerWindow: 3,
            window: const Duration(seconds: 10),
          ),
        );

        for (var i = 0; i < 20; i++) {
          handler(StateError('storm'), StackTrace.empty);
        }
        // Three entries plus the one burst notice.
        expect(uncaught(), hasLength(4));
        expect(uncaught().last.message, contains('burst'));

        async.elapse(const Duration(seconds: 10));
        handler(StateError('after'), StackTrace.empty);

        expect(uncaught(), hasLength(5));
        expect(uncaught().last.message, contains('17 earlier ones'));
      });
    });

    test('a slow trickle is never dropped', () {
      fakeAsync((async) {
        final handler = wrapFlutterErrorHandler(
          (_) {},
          throttle: ErrorLogThrottle(
            maxPerWindow: 2,
            window: const Duration(seconds: 10),
          ),
        );
        for (var i = 0; i < 6; i++) {
          handler(details(StateError('slow')));
          async.elapse(const Duration(seconds: 6));
        }
        expect(uncaught(), hasLength(6));
        expect(
          uncaught().every((r) => r.message.contains('StateError')),
          isTrue,
        );
      });
    });
  });

  group('AppMonitoring installs the forwarding', () {
    late Directory dir;
    late CrashReportingConsentMarker marker;
    FlutterExceptionHandler? flutterOnError;
    ErrorCallback? platformOnError;

    setUp(() {
      flutterOnError = FlutterError.onError;
      platformOnError = PlatformDispatcher.instance.onError;
      dir = Directory.systemTemp.createTempSync('wp_errlog_');
      marker = CrashReportingConsentMarker(directory: dir.path);
    });

    tearDown(() async {
      FlutterError.onError = flutterOnError;
      PlatformDispatcher.instance.onError = platformOnError;
      await CrashReporter.instance?.dispose();
      dir.deleteSync(recursive: true);
    });

    Future<void> fakeSentryInit(
      FlutterOptionsConfiguration configure, {
      AppRunner? appRunner,
    }) async => appRunner?.call();

    for (final optedOut in [true, false]) {
      test('with error reporting ${optedOut ? 'off' : 'on'}', () async {
        marker.record(granted: !optedOut);
        // Keep the test framework's own handler out of the chain.
        FlutterError.onError = (_) {};
        PlatformDispatcher.instance.onError = (_, _) => true;

        await AppMonitoring.startMonitoring(
          appRunner: () async {},
          consentMarker: marker,
          sentryInit: fakeSentryInit,
        );
        FlutterError.onError!(details(StateError('frame')));
        PlatformDispatcher.instance.onError!(
          StateError('async'),
          StackTrace.empty,
        );

        expect(uncaught().map((r) => r.message), [
          contains('Framework error'),
          contains('Zone error'),
        ]);
      });
    }
  });
}
