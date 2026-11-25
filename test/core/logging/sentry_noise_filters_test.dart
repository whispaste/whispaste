/// Sentry analysis 2026-11-22: what reaches Sentry, and how it is grouped.
///
/// - Auto-escalated log errors get one group per log site instead of the
///   single catch-all issue FLUTTER_WHISPASTE-80.
/// - Recoverable package records, connection failures of downloads and a
///   locked keyring are user states, not defects, and stay out of Sentry.
/// - Unhandled follow-ups of a history file without its key are dropped;
///   the open reports that case itself.
library;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/logging/app_logger.dart';
import 'package:whispaste/core/logging/crash_fingerprints.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';
import 'package:whispaste/services/download_error_kind.dart';

void main() {
  group('autoEscalationFingerprint', () {
    test('starts with the catch-all value, then logger and template', () {
      expect(
        autoEscalationFingerprint(
          'HotkeyService',
          'Safe-default hotkey also failed to register: boom',
          null,
        ),
        [
          appLoggerAutoEscalated,
          'HotkeyService',
          'Safe-default hotkey also failed to register',
        ],
      );
    });

    test('session ids and numbers do not split one site', () {
      final a = autoEscalationFingerprint(
        'RecordingOrchestrator',
        '[mwr44gwe-d3b8d9ca] Transcription timed out after 68s',
        null,
      );
      final b = autoEscalationFingerprint(
        'RecordingOrchestrator',
        '[mwnsetsz-609645c8] Transcription timed out after 66s',
        null,
      );
      expect(a, b);
      expect(a.last, 'Transcription timed out after #s');
    });

    test('different sites and different error kinds stay apart', () {
      final timeout = autoEscalationFingerprint(
        'RecordingOrchestrator',
        '[x] Capture step timed out after 10000 ms',
        null,
      );
      final transcription = autoEscalationFingerprint(
        'RecordingOrchestrator',
        '[x] Transcription timed out after 68s',
        null,
      );
      expect(timeout, isNot(transcription));

      final platform = autoEscalationFingerprint(
        'AudioService',
        'startStream failed: PlatformException(Record, ...)',
        PlatformException(code: 'Record'),
      );
      final state = autoEscalationFingerprint(
        'AudioService',
        'startStream failed: Bad state',
        StateError('x'),
      );
      expect(platform.last, 'PlatformException(Record)');
      expect(platform, isNot(state));
    });

    test('the exception text after the first colon is not part of it', () {
      final a = autoEscalationFingerprint(
        'Download',
        'Download failed: HandshakeException: terminated',
        null,
      );
      final b = autoEscalationFingerprint(
        'Download',
        'Download failed: SocketException: timed out',
        null,
      );
      expect(a, b);
    });

    test('a long template is capped', () {
      final f = autoEscalationFingerprint('L', 'x' * 300, null);
      expect(f.last.length, 80);
    });
  });

  group('isRecoverablePackageError', () {
    test('flutter_soloud fileAlreadyLoaded is not escalated', () {
      expect(
        isRecoverablePackageError(
          LogRecord(
            Level.SEVERE,
            'loadFile() result: PlayerErrors.fileAlreadyLoaded '
                '(The sound file has already been loaded!)',
            'flutter_soloud.SoLoud',
          ),
        ),
        isTrue,
      );
    });

    test('other SoLoud errors and app loggers still are', () {
      expect(
        isRecoverablePackageError(
          LogRecord(
            Level.SEVERE,
            'loadFile() result: PlayerErrors.fileNotFound',
            'flutter_soloud.SoLoud',
          ),
        ),
        isFalse,
      );
      expect(
        isRecoverablePackageError(
          LogRecord(Level.SEVERE, 'fileAlreadyLoaded', 'SoundFeedback'),
        ),
        isFalse,
      );
    });
  });

  group('isConnectionDownloadFailure', () {
    DioException dio(DioExceptionType type) => DioException(
      requestOptions: RequestOptions(path: '/m'),
      type: type,
    );

    test('offline, lost transfers and timeouts are the connection', () {
      expect(
        isConnectionDownloadFailure(dio(DioExceptionType.connectionError)),
        isTrue,
      );
      expect(
        isConnectionDownloadFailure(dio(DioExceptionType.connectionTimeout)),
        isTrue,
      );
      expect(
        isConnectionDownloadFailure(dio(DioExceptionType.receiveTimeout)),
        isTrue,
      );
    });

    test('unknown errors keep their error level', () {
      expect(isConnectionDownloadFailure(StateError('x')), isFalse);
    });
  });

  test('isKeyringUnavailable matches the skipped keyring calls only', () {
    expect(
      isKeyringUnavailable(
        PlatformException(code: keyringLockedCode, details: 'locked'),
      ),
      isTrue,
    );
    expect(
      isKeyringUnavailable(
        PlatformException(code: keyringLockedCode, details: 'unreachable'),
      ),
      isTrue,
    );
    expect(isKeyringUnavailable(PlatformException(code: 'Other')), isFalse);
    expect(isKeyringUnavailable(StateError('x')), isFalse);
  });

  group('beforeSend', () {
    setUp(CrashReporter.resetThrottlesForTesting);

    SentryEvent unhandled(String type) => SentryEvent(
      level: SentryLevel.error,
      exceptions: [SentryException(type: type, value: 'v')],
    );

    test('drops unhandled follow-ups of a history file without key', () {
      expect(
        CrashReporter.beforeSend(
          unhandled('HistoryKeyUnavailableException'),
          Hint(),
        ),
        isNull,
      );
      expect(
        CrashReporter.beforeSend(
          unhandled('HistoryKeyringUnavailableException'),
          Hint(),
        ),
        isNull,
      );
    });

    test('keeps other unhandled exceptions', () {
      expect(
        CrashReporter.beforeSend(unhandled('StateError'), Hint()),
        isNotNull,
      );
    });
  });
}
