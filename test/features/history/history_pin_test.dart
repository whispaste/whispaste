/// Unit tests for the pure History-PIN primitives: format validation, the
/// PBKDF2 hash/verify round-trip, and the throttle schedule.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/data/history_pin.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('isValidHistoryPin', () {
    test('accepts 4 to 8 digits', () {
      for (final pin in ['1234', '12345', '00000000']) {
        expect(isValidHistoryPin(pin), isTrue, reason: pin);
      }
    });

    test('rejects too short, too long, non-digits and whitespace', () {
      for (final pin in ['', '123', '123456789', '12a4', ' 1234', '١٢٣٤']) {
        expect(isValidHistoryPin(pin), isFalse, reason: pin);
      }
    });
  });

  group('pbkdf2HmacSha256', () {
    // RFC 7914 §11, PBKDF2-HMAC-SHA-256 vector 1 (first 32 bytes).
    test('matches the RFC 7914 test vector', () {
      final dk = pbkdf2HmacSha256(
        utf8.encode('passwd'),
        utf8.encode('salt'),
        1,
      );
      expect(
        _hex(dk),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc',
      );
    });
  });

  group('hashHistoryPin / verifyHistoryPin', () {
    test('round-trips the correct PIN and rejects a wrong one', () {
      final stored = hashHistoryPin('4711', iterations: 10);
      expect(verifyHistoryPin('4711', stored), isTrue);
      expect(verifyHistoryPin('4712', stored), isFalse);
    });

    test('never stores the PIN itself and salts every hash', () {
      final a = hashHistoryPin('4711', iterations: 10);
      final b = hashHistoryPin('4711', iterations: 10);
      expect(a, isNot(contains('4711')));
      expect(a, isNot(b), reason: 'a fresh random salt per hash');
      expect(verifyHistoryPin('4711', b), isTrue);
    });

    test('an empty or malformed stored value never verifies', () {
      for (final stored in ['', 'garbage', r'pbkdf2-sha256$x$y$z']) {
        expect(verifyHistoryPin('4711', stored), isFalse, reason: stored);
      }
    });
  });

  group('historyPinLockout', () {
    test('no lockout for the first four misses', () {
      for (var n = 0; n <= 4; n++) {
        expect(historyPinLockout(n), Duration.zero, reason: '$n');
      }
    });

    test('30 s from the 5th miss, doubling, capped at 15 min', () {
      expect(historyPinLockout(5), const Duration(seconds: 30));
      expect(historyPinLockout(6), const Duration(seconds: 60));
      expect(historyPinLockout(7), const Duration(seconds: 120));
      expect(historyPinLockout(10), const Duration(minutes: 15));
      expect(historyPinLockout(1000), const Duration(minutes: 15));
    });
  });
}
