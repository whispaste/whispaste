/// Opting out of error reporting must stop Sentry entirely, not only the
/// Dart-side `beforeSend` gate: native crashes (sentry-cocoa/sentry-native),
/// app-hang reports and release-health sessions bypass Dart callbacks, and
/// everything before the settings are loaded used to go out by default.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:whispaste/core/logging/app_monitoring.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';
import 'package:whispaste/core/logging/crash_reporting_consent.dart';

void main() {
  // The Sentry branch installs the cascade guard on the binding's handlers.
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late CrashReportingConsentMarker marker;
  var sentryInitCalls = 0;
  var appRan = false;

  Future<void> fakeSentryInit(
    FlutterOptionsConfiguration configure, {
    AppRunner? appRunner,
  }) async {
    sentryInitCalls++;
    await appRunner?.call();
  }

  FlutterExceptionHandler? flutterOnError;
  ErrorCallback? platformOnError;

  setUp(() {
    flutterOnError = FlutterError.onError;
    platformOnError = binding.platformDispatcher.onError;
    dir = Directory.systemTemp.createTempSync('wp_consent_');
    marker = CrashReportingConsentMarker(directory: dir.path);
    sentryInitCalls = 0;
    appRan = false;
  });

  tearDown(() async {
    FlutterError.onError = flutterOnError;
    binding.platformDispatcher.onError = platformOnError;
    await CrashReporter.instance?.dispose();
    dir.deleteSync(recursive: true);
  });

  group('CrashReportingConsentMarker', () {
    test('defaults to not opted out', () {
      expect(marker.optedOut, isFalse);
    });

    test('records an opt-out and an opt-in again', () {
      marker.record(granted: false);
      expect(marker.optedOut, isTrue);
      marker.record(granted: true);
      expect(marker.optedOut, isFalse);
    });

    test('an unwritable location never throws', () {
      final broken = CrashReportingConsentMarker(
        directory: '${dir.path}/missing/\u0000',
      );
      expect(() => broken.record(granted: false), returnsNormally);
      expect(broken.optedOut, isFalse);
    });
  });

  /// Settings as `AppDatabase` persists them: one key-value row per field.
  void writeStoredSettings(Map<String, String> rows) {
    final db = sqlite3.open(p.join(dir.path, 'history.db'));
    db.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    for (final row in rows.entries) {
      db.execute('INSERT INTO app_settings (key, value) VALUES (?, ?)', [
        row.key,
        row.value,
      ]);
    }
    db.close();
  }

  group('opt-out stored before the marker existed', () {
    test('is picked up from the settings database and migrated', () {
      writeStoredSettings({'error_reporting': 'false', 'theme': 'dark'});

      expect(marker.resolveOptedOut(), isTrue);
      expect(marker.optedOut, isTrue);
    });

    test('an opted-in or fresh profile stays opted in', () {
      expect(marker.resolveOptedOut(), isFalse);
      writeStoredSettings({'error_reporting': 'true'});
      expect(marker.resolveOptedOut(), isFalse);
      expect(marker.optedOut, isFalse);
    });

    test('an unreadable settings database fails open', () {
      File(p.join(dir.path, 'history.db')).writeAsStringSync('not sqlite');
      expect(marker.resolveOptedOut(), isFalse);
    });

    test('startMonitoring never initialises Sentry for it', () async {
      writeStoredSettings({'error_reporting': 'false'});

      await AppMonitoring.startMonitoring(
        appRunner: () async => appRan = true,
        consentMarker: marker,
        sentryInit: fakeSentryInit,
      );

      expect(sentryInitCalls, 0);
      expect(appRan, isTrue);
      expect(CrashReporter.instance!.consentGranted, isFalse);
    });
  });

  group('AppMonitoring.startMonitoring', () {
    test('stored opt-out: Sentry is never initialised, the app still runs, '
        'and early errors are not captured', () async {
      marker.record(granted: false);

      await AppMonitoring.startMonitoring(
        appRunner: () async => appRan = true,
        consentMarker: marker,
        sentryInit: fakeSentryInit,
      );

      expect(sentryInitCalls, 0);
      expect(appRan, isTrue);
      expect(Sentry.isEnabled, isFalse);
      final reporter = CrashReporter.instance!;
      expect(reporter.consentGranted, isFalse);
      // A bootstrap error before the settings are loaded is dropped.
      expect(
        CrashReporter.beforeSend(
          SentryEvent(message: SentryMessage('x')),
          Hint(),
        ),
        isNull,
      );
    });

    test('no stored opt-out: Sentry wraps the app runner', () async {
      await AppMonitoring.startMonitoring(
        appRunner: () async => appRan = true,
        consentMarker: marker,
        sentryInit: fakeSentryInit,
      );

      expect(sentryInitCalls, 1);
      expect(appRan, isTrue);
      expect(CrashReporter.instance!.consentGranted, isTrue);
    });
  });

  group('runtime toggle', () {
    test('opt-out persists the marker and shuts Sentry down', () async {
      await SentryFlutter.init((o) {
        o.dsn = 'https://abc123@sentry.example.invalid/0';
      });
      final reporter = CrashReporter.init(consentMarker: marker);
      expect(Sentry.isEnabled, isTrue);

      reporter.consentGranted = false;
      await pumpEventQueue();

      expect(marker.optedOut, isTrue);
      expect(Sentry.isEnabled, isFalse);
      expect(reporter.restartRequired, isFalse);
    });

    test(
      'opt-in without a running Sentry takes effect on the next start',
      () async {
        marker.record(granted: false);
        final reporter = CrashReporter.init(
          consentGranted: false,
          consentMarker: marker,
        );
        expect(reporter.restartRequired, isFalse);

        reporter.consentGranted = true;

        expect(marker.optedOut, isFalse);
        expect(reporter.restartRequired, isTrue);
      },
    );
  });
}
