import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/logging/crash_error_redaction.dart';

void main() {
  group('redactForCrashReport', () {
    // Sentry derives the exception value from `error.toString()`, and
    // SqliteException.toString() appends bound parameters. Bound parameters
    // of history writes are transcript text, so they must never reach a
    // crash report.
    test('drops bound parameters of a SqliteException', () {
      final original = SqliteException(
        extendedResultCode: 1555, // SQLITE_CONSTRAINT_PRIMARYKEY
        message: 'UNIQUE constraint failed: history_entries.id',
        operation: 'executing',
        causingStatement:
            'INSERT INTO history_entries (id, text) VALUES (?, ?)',
        parametersToStatement: const ['entry-1', 'Geheimer Diktattext'],
      );
      expect(original.toString(), contains('Geheimer Diktattext'));

      final redacted = redactForCrashReport(original);

      expect(redacted, isA<SqliteException>());
      final text = redacted.toString();
      expect(text, isNot(contains('Geheimer Diktattext')));
      expect(text, isNot(contains('entry-1')));
      expect(text, isNot(contains('INSERT INTO')));
      expect(text, contains('UNIQUE constraint failed'));
      final sqlite = redacted as SqliteException;
      expect(sqlite.resultCode, original.resultCode);
      expect(sqlite.extendedResultCode, original.extendedResultCode);
      expect(sqlite.parametersToStatement, isNull);
    });

    test('returns every other error object unchanged', () {
      final error = StateError('boom');
      expect(identical(redactForCrashReport(error), error), isTrue);
    });
  });
}
