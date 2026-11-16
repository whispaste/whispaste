import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:whispaste/core/logging/crash_error_redaction.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';

/// Transcript-like bound parameter. Kept in one place so every assertion
/// checks the same secret-looking text.
const _transcript = 'Mein Geheimtext vom Diktat';

SqliteException _insertFailure() => SqliteException(
  extendedResultCode: 1555,
  message: 'UNIQUE constraint failed: history_entries.id',
  operation: 'executing',
  causingStatement: 'INSERT INTO history_entries (id, content) VALUES (?, ?)',
  parametersToStatement: const ['entry-1', _transcript],
);

void main() {
  // The rendered SqliteException, exactly as `'$e'` interpolation produces it.
  final rendered = '${_insertFailure()}';

  group('redactSqliteParametersInText', () {
    test('the fixture really renders its parameters', () {
      expect(rendered, contains(_transcript));
    });

    test('removes parameters and keeps the statement and the message', () {
      final text = redactSqliteParametersInText('Save failed: $rendered');

      expect(text, isNot(contains(_transcript)));
      expect(text, isNot(contains('entry-1')));
      expect(text, contains('INSERT INTO history_entries'));
      expect(text, contains('UNIQUE constraint failed'));
      expect(text, contains(', parameters: <redacted>'));
    });

    test('removes parameters that span several lines', () {
      final multiline = SqliteException(
        extendedResultCode: 1,
        message: 'boom',
        causingStatement: 'UPDATE t SET c = ?',
        parametersToStatement: const ['Zeile eins\nZeile zwei Geheim'],
      ).toString();

      final text = redactSqliteParametersInText(multiline);

      expect(text, isNot(contains('Zeile zwei Geheim')));
      expect(text, isNot(contains('Zeile eins')));
    });

    test('leaves text without a SqliteException rendering unchanged', () {
      const plain = 'Recording started (sessionId=abc123), parameters: none';
      expect(redactSqliteParametersInText(plain), plain);
    });
  });

  group('CrashReporter.beforeSend', () {
    test('strips parameters from an unhandled SqliteException event', () {
      final event = SentryEvent(
        exceptions: [SentryException(type: 'SqliteException', value: rendered)],
        message: SentryMessage('Unhandled: $rendered'),
        breadcrumbs: [Breadcrumb(message: 'history: $rendered')],
      );

      final result = CrashReporter.beforeSend(event, Hint());

      expect(result, isNotNull, reason: 'the event itself is still reported');
      final dump = [
        result!.exceptions!.single.value,
        result.message!.formatted,
        result.breadcrumbs!.single.message,
      ].join('\n');
      expect(dump, isNot(contains(_transcript)));
      expect(dump, isNot(contains('entry-1')));
      expect(dump, contains('UNIQUE constraint failed'));
    });
  });
}
