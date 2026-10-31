/// Unit tests for [readIntPrefSafe]/[readBoolPrefSafe] — the type-tolerant
/// readers introduced to fix Sentry FLUTTER_WHISPASTE-BP/-BQ (a fatal
/// TypeError crash loop when a bundle-ID-migrated preference, persisted as a
/// String, was read with the raw `getInt`/`getBool`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/shared_prefs_safe_read.dart';

void main() {
  group('readIntPrefSafe', () {
    test('returns the value untouched when natively stored as int', () async {
      SharedPreferences.setMockInitialValues({'k': 42});
      final prefs = await SharedPreferences.getInstance();

      expect(readIntPrefSafe(prefs, 'k'), 42);
    });

    test('parses a migrated String value', () async {
      SharedPreferences.setMockInitialValues({'k': '42'});
      final prefs = await SharedPreferences.getInstance();

      expect(readIntPrefSafe(prefs, 'k'), 42);
    });

    test(
      'returns null for an unparseable String instead of throwing',
      () async {
        SharedPreferences.setMockInitialValues({'k': 'not-a-number'});
        final prefs = await SharedPreferences.getInstance();

        expect(readIntPrefSafe(prefs, 'k'), isNull);
      },
    );

    test('returns null when the key is absent', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(readIntPrefSafe(prefs, 'k'), isNull);
    });
  });

  group('readBoolPrefSafe', () {
    test('returns the value untouched when natively stored as bool', () async {
      SharedPreferences.setMockInitialValues({'k': true});
      final prefs = await SharedPreferences.getInstance();

      expect(readBoolPrefSafe(prefs, 'k'), isTrue);
    });

    test('parses a migrated String value', () async {
      SharedPreferences.setMockInitialValues({'k': 'true'});
      final prefs = await SharedPreferences.getInstance();

      expect(readBoolPrefSafe(prefs, 'k'), isTrue);
    });

    test('parses a migrated "false" String value', () async {
      SharedPreferences.setMockInitialValues({'k': 'false'});
      final prefs = await SharedPreferences.getInstance();

      expect(readBoolPrefSafe(prefs, 'k'), isFalse);
    });

    test(
      'returns null for an unparseable String instead of throwing',
      () async {
        SharedPreferences.setMockInitialValues({'k': 'maybe'});
        final prefs = await SharedPreferences.getInstance();

        expect(readBoolPrefSafe(prefs, 'k'), isNull);
      },
    );
  });
}
