/// Unit tests for device_id_probe.dart (AC6).
///
/// Verifies that `deriveDeviceId` is bit-identical to `crash_reporter._deriveDeviceId`.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/probes/device_id_probe.dart';

void main() {
  group('deriveDeviceId', () {
    test('is bit-identical to crash_reporter formula for a fixed hostname', () {
      // Reproduce the crash_reporter formula inline:
      //   md5("${hostname}_whispaste").toString().substring(0, 12)
      const hostname = 'test-machine';
      final expected = md5
          .convert(utf8.encode('${hostname}_whispaste'))
          .toString()
          .substring(0, 12);

      expect(deriveDeviceId(hostname), expected);
    });

    test('returns exactly 12 characters', () {
      expect(deriveDeviceId('any-hostname').length, 12);
    });

    test('returns lowercase hexadecimal characters only', () {
      final id = deriveDeviceId('my-pc');
      expect(RegExp(r'^[0-9a-f]{12}$').hasMatch(id), isTrue);
    });

    test('is deterministic for the same hostname', () {
      const hostname = 'silvio-macbook';
      expect(deriveDeviceId(hostname), deriveDeviceId(hostname));
    });

    test('differs for different hostnames', () {
      expect(deriveDeviceId('machine-a'), isNot(deriveDeviceId('machine-b')));
    });

    test('matches expected value for a known hostname', () {
      // Pre-computed: md5("desktop-pc_whispaste") = known hash
      // We compute it here so the test is self-contained.
      const hostname = 'desktop-pc';
      final expected = md5
          .convert(utf8.encode('${hostname}_whispaste'))
          .toString()
          .substring(0, 12);
      expect(deriveDeviceId(hostname), expected);
    });
  });
}
