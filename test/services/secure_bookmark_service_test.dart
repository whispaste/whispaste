/// Tests [SecureBookmarkService] against a faked
/// `com.whispaste.secure_bookmark` MethodChannel — no real macOS bookmark
/// APIs are exercised here (that's `SecureBookmarkHost.swift`, verifiable
/// only via a real macOS run/manual acceptance, see Ticket 04).
///
/// [SecureBookmarkService.isSupported] gates every method on
/// `Platform.isMacOS`, so on Windows/Linux runners the channel is never
/// invoked and every assertion below would fail — restricted to macOS via
/// `@TestOn` rather than run everywhere. The "never called on Windows/Linux"
/// half of the contract is instead verified structurally at the controller
/// level (see `settings_portability_controller_test.dart`'s
/// `bookmarksSupported: false` scenario), because `Platform.isMacOS` cannot
/// be flipped from a test.
@TestOn('mac-os')
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/secure_bookmark_service.dart';

void _setMock(
  String channelName,
  Future<dynamic> Function(MethodCall)? handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MethodChannel(channelName), handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'com.whispaste.secure_bookmark';
  const service = SecureBookmarkService();

  tearDown(() => _setMock(channelName, null));

  group('isSupported', () {
    test('is true on this (macOS) test platform', () {
      expect(service.isSupported, isTrue);
    });
  });

  group('create', () {
    test('returns the base64 bookmark from a successful native call', () async {
      MethodCall? received;
      _setMock(channelName, (call) async {
        received = call;
        return 'YmFzZTY0LWJvb2ttYXJr';
      });

      final result = await service.create('/tmp/export.json');

      expect(result, 'YmFzZTY0LWJvb2ttYXJr');
      expect(received?.method, 'create');
      expect((received?.arguments as Map)['path'], '/tmp/export.json');
    });

    test('returns null on PlatformException', () async {
      _setMock(
        channelName,
        (call) async => throw PlatformException(code: 'BOOKMARK_FAILED'),
      );

      final result = await service.create('/tmp/export.json');

      expect(result, isNull);
    });

    test(
      'returns null on MissingPluginException (no host registered)',
      () async {
        _setMock(channelName, null);

        final result = await service.create('/tmp/export.json');

        expect(result, isNull);
      },
    );
  });

  group('resolve', () {
    test('parses path and isStale from a successful native call', () async {
      _setMock(
        channelName,
        (call) async => {'path': '/tmp/resolved.json', 'isStale': true},
      );

      final result = await service.resolve('some-bookmark');

      expect(result, isNotNull);
      expect(result!.path, '/tmp/resolved.json');
      expect(result.isStale, isTrue);
    });

    test(
      'returns null for an empty bookmark without calling the channel',
      () async {
        var called = false;
        _setMock(channelName, (call) async {
          called = true;
          return null;
        });

        final result = await service.resolve('');

        expect(result, isNull);
        expect(called, isFalse);
      },
    );

    test('returns null when the native side returns malformed data', () async {
      _setMock(channelName, (call) async => {'path': 123, 'isStale': 'nope'});

      final result = await service.resolve('some-bookmark');

      expect(result, isNull);
    });

    test('returns null on PlatformException', () async {
      _setMock(
        channelName,
        (call) async => throw PlatformException(code: 'RESOLVE_FAILED'),
      );

      final result = await service.resolve('some-bookmark');

      expect(result, isNull);
    });
  });

  group('startAccess / stopAccess', () {
    test('startAccess returns the native bool result', () async {
      MethodCall? received;
      _setMock(channelName, (call) async {
        received = call;
        return true;
      });

      final result = await service.startAccess('some-bookmark');

      expect(result, isTrue);
      expect(received?.method, 'startAccess');
      expect((received?.arguments as Map)['bookmark'], 'some-bookmark');
    });

    test('startAccess returns false on PlatformException', () async {
      _setMock(
        channelName,
        (call) async => throw PlatformException(code: 'START_ACCESS_FAILED'),
      );

      final result = await service.startAccess('some-bookmark');

      expect(result, isFalse);
    });

    test('startAccess returns false on MissingPluginException', () async {
      _setMock(channelName, null);

      final result = await service.startAccess('some-bookmark');

      expect(result, isFalse);
    });

    test('stopAccess invokes the channel with the same bookmark', () async {
      MethodCall? received;
      _setMock(channelName, (call) async {
        received = call;
        return null;
      });

      await service.stopAccess('some-bookmark');

      expect(received?.method, 'stopAccess');
      expect((received?.arguments as Map)['bookmark'], 'some-bookmark');
    });

    test('stopAccess swallows PlatformException without throwing', () async {
      _setMock(
        channelName,
        (call) async => throw PlatformException(code: 'STOP_ACCESS_FAILED'),
      );

      await expectLater(service.stopAccess('some-bookmark'), completes);
    });

    test('stopAccess is a no-op for an empty bookmark', () async {
      var called = false;
      _setMock(channelName, (call) async {
        called = true;
        return null;
      });

      await service.stopAccess('');

      expect(called, isFalse);
    });
  });
}
