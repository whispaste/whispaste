/// Security tests for automation hook URLs (WP-38 / 8.3).
///
/// Only loopback targets may ever receive hook events. These tests pin the
/// save-time check (`isLoopbackHookUrl`) against the usual IP-literal tricks
/// and hostname confusions, and the send-time check
/// (`pinLoopbackHookTarget`) against DNS answers that are not loopback.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/automation_hooks.dart';

void main() {
  group('isLoopbackHookUrl (save time)', () {
    test('accepts IPv4 loopback literals, IPv6 loopback and localhost', () {
      expect(isLoopbackHookUrl('http://127.0.0.1:9000/hook'), isTrue);
      expect(isLoopbackHookUrl('http://127.255.0.9/hook'), isTrue);
      expect(isLoopbackHookUrl('http://[::1]:9000/hook'), isTrue);
      expect(isLoopbackHookUrl('http://localhost:9000/hook'), isTrue);
      expect(isLoopbackHookUrl('http://localhost/'), isTrue);
    });

    test('rejects public and private IPv4 addresses', () {
      expect(isLoopbackHookUrl('http://8.8.8.8/hook'), isFalse);
      expect(isLoopbackHookUrl('http://192.168.1.10/hook'), isFalse);
      expect(isLoopbackHookUrl('http://10.0.0.1/hook'), isFalse);
      expect(isLoopbackHookUrl('http://0.0.0.0/hook'), isFalse);
    });

    test('rejects decimal, hex, octal and shortened IPv4 tricks', () {
      // 2130706433 == 127.0.0.1 as a single decimal number.
      expect(isLoopbackHookUrl('http://2130706433/hook'), isFalse);
      expect(isLoopbackHookUrl('http://0x7f000001/hook'), isFalse);
      expect(isLoopbackHookUrl('http://0x7f.0.0.1/hook'), isFalse);
      expect(isLoopbackHookUrl('http://0177.0.0.1/hook'), isFalse);
      expect(isLoopbackHookUrl('http://127.1/hook'), isFalse);
      expect(isLoopbackHookUrl('http://127.0.1/hook'), isFalse);
    });

    test('rejects hostnames that merely start with localhost', () {
      expect(isLoopbackHookUrl('http://localhost.evil.com/hook'), isFalse);
      expect(isLoopbackHookUrl('http://localhost.localdomain/hook'), isFalse);
      expect(isLoopbackHookUrl('http://localhost./hook'), isFalse);
      expect(isLoopbackHookUrl('http://evil-localhost/hook'), isFalse);
      expect(isLoopbackHookUrl('http://127.0.0.1.evil.com/hook'), isFalse);
    });

    test(
      'rejects other hostnames, even ones that could resolve to loopback',
      () {
        expect(isLoopbackHookUrl('http://example.com/hook'), isFalse);
        expect(isLoopbackHookUrl('http://lvh.me/hook'), isFalse);
        expect(
          isLoopbackHookUrl('http://vault.127.0.0.1.nip.io/hook'),
          isFalse,
        );
      },
    );

    test('rejects IPv6-mapped and IPv4-compatible addresses', () {
      expect(isLoopbackHookUrl('http://[::ffff:127.0.0.1]/hook'), isFalse);
      expect(isLoopbackHookUrl('http://[::ffff:7f00:1]/hook'), isFalse);
      expect(isLoopbackHookUrl('http://[::ffff:8.8.8.8]/hook'), isFalse);
      expect(isLoopbackHookUrl('http://[::127.0.0.1]/hook'), isFalse);
      expect(isLoopbackHookUrl('http://[2001:db8::1]/hook'), isFalse);
      expect(isLoopbackHookUrl('http://[::2]/hook'), isFalse);
    });

    test('rejects userinfo tricks that move the real host', () {
      expect(isLoopbackHookUrl('http://127.0.0.1@evil.com/hook'), isFalse);
      expect(isLoopbackHookUrl('http://localhost@evil.com/hook'), isFalse);
      expect(isLoopbackHookUrl('http://user@127.0.0.1/hook'), isFalse);
    });

    test('rejects non-http schemes and malformed input', () {
      expect(isLoopbackHookUrl('https://127.0.0.1/hook'), isFalse);
      expect(isLoopbackHookUrl('file:///etc/passwd'), isFalse);
      expect(isLoopbackHookUrl('ftp://127.0.0.1/hook'), isFalse);
      expect(isLoopbackHookUrl('127.0.0.1/hook'), isFalse);
      expect(isLoopbackHookUrl(''), isFalse);
      expect(isLoopbackHookUrl('http://'), isFalse);
      expect(isLoopbackHookUrl('http://127.0.0.1:0/hook'), isFalse);
      expect(isLoopbackHookUrl('http://127.0.0.1:70000/hook'), isFalse);
    });
  });

  group('pinLoopbackHookTarget (send time)', () {
    Future<List<InternetAddress>> resolvesTo(List<String> hosts) async => [
      for (final h in hosts) InternetAddress(h),
    ];

    test('a loopback literal passes through unchanged', () async {
      final uri = Uri.parse('http://127.0.0.1:9000/hook');
      final pinned = await pinLoopbackHookTarget(
        uri,
        lookup: (_) async => throw StateError('must not resolve a literal'),
      );
      expect(pinned, uri);
    });

    test('localhost is pinned to the resolved loopback address', () async {
      final pinned = await pinLoopbackHookTarget(
        Uri.parse('http://localhost:9000/hook'),
        lookup: (host) async {
          expect(host, 'localhost');
          return resolvesTo(['127.0.0.1']);
        },
      );
      expect(pinned?.host, '127.0.0.1');
      expect(pinned?.port, 9000);
      expect(pinned?.path, '/hook');
    });

    test('localhost resolving to a public address is rejected', () async {
      final pinned = await pinLoopbackHookTarget(
        Uri.parse('http://localhost:9000/hook'),
        lookup: (_) => resolvesTo(['93.184.216.34']),
      );
      expect(pinned, isNull);
    });

    test(
      'localhost with mixed loopback and public answers is rejected',
      () async {
        final pinned = await pinLoopbackHookTarget(
          Uri.parse('http://localhost:9000/hook'),
          lookup: (_) => resolvesTo(['127.0.0.1', '10.0.0.5']),
        );
        expect(pinned, isNull);
      },
    );

    test('localhost without any answer is rejected', () async {
      final pinned = await pinLoopbackHookTarget(
        Uri.parse('http://localhost:9000/hook'),
        lookup: (_) async => <InternetAddress>[],
      );
      expect(pinned, isNull);
    });

    test('a lookup error is rejected, not thrown into the sender', () async {
      final pinned = await pinLoopbackHookTarget(
        Uri.parse('http://localhost:9000/hook'),
        lookup: (_) async => throw const SocketException('no such host'),
      );
      expect(pinned, isNull);
    });

    test(
      'a URL that failed the save-time rule is rejected without a lookup',
      () async {
        final pinned = await pinLoopbackHookTarget(
          Uri.parse('http://localhost.evil.com:9000/hook'),
          lookup: (_) async => throw StateError('must not resolve'),
        );
        expect(pinned, isNull);
      },
    );
  });
}
