import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller_interface.dart';
import 'package:whispaste/services/desktop_paste/linux_portal_input.dart';

class _MemoryTokenStore implements PortalRestoreTokenStore {
  String? token;
  int writes = 0;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async {
    writes++;
    this.token = token;
  }

  @override
  Future<void> clear() async => token = null;
}

/// In-memory secure store; [locked] plays a locked keyring.
class _Keyring extends SecureKeyStore {
  final values = <String, String>{};
  bool locked = false;

  void _check() {
    if (locked) throw PlatformException(code: 'KeyringLocked');
  }

  @override
  Future<String?> readKey(String key) async {
    _check();
    return values[key];
  }

  @override
  Future<void> writeKey(String key, String value) async {
    _check();
    values[key] = value;
  }

  @override
  Future<void> deleteKey(String key) async {
    _check();
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureRestoreTokenStore', () {
    test('keeps the token in the secure store under its own key', () async {
      final keyring = _Keyring();
      final store = SecureRestoreTokenStore(keyring);

      expect(await store.read(), isNull);
      await store.write('rt-1');
      expect(keyring.values, {linuxPortalRestoreTokenKey: 'rt-1'});
      expect(await store.read(), 'rt-1');
      await store.clear();
      expect(keyring.values, isEmpty);
    });

    test('a locked keyring reads as no token and never throws', () async {
      final keyring = _Keyring()
        ..values[linuxPortalRestoreTokenKey] = 'rt-1'
        ..locked = true;
      final store = SecureRestoreTokenStore(keyring);

      expect(await store.read(), isNull);
      await store.write('rt-2');
      await store.clear();
      keyring.locked = false;
      expect(await store.read(), 'rt-1');
    });
  });

  const channel = MethodChannel('com.whispaste.desktop_paste');

  late List<MethodCall> calls;
  late _MemoryTokenStore store;

  void answer(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  LinuxPortalInput service() =>
      LinuxPortalInput(channel: channel, tokenStore: store);

  setUp(() {
    calls = [];
    store = _MemoryTokenStore();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('isAvailable', () {
    test('passes the native answer through', () async {
      answer((_) async => true);
      expect(await service().isAvailable(), isTrue);
      expect(calls.single.method, 'portalInputAvailable');
    });

    test('is false without a native handler', () async {
      // No mock handler: the channel throws MissingPluginException.
      expect(await service().isAvailable(), isFalse);
    });

    test('is false when the native call fails', () async {
      answer((_) async => throw PlatformException(code: 'boom'));
      expect(await service().isAvailable(), isFalse);
    });

    test('a non-bool answer counts as unavailable', () async {
      answer((_) async => 'yes');
      expect(await service().isAvailable(), isFalse);
    });
  });

  group('connect', () {
    test(
      'first connect sends no restore token and stores the new one',
      () async {
        answer((_) async => {'status': 'connected', 'restoreToken': 'tok-1'});

        final result = await service().connect();

        expect(calls.single.method, 'portalInputConnect');
        expect(calls.single.arguments, {'restoreToken': null});
        expect(result.status, PortalInputConnectStatus.connected);
        expect(result.isConnected, isTrue);
        expect(result.restoreToken, 'tok-1');
        expect(store.token, 'tok-1');
        expect(store.writes, 1);
      },
    );

    test('a stored restore token is passed on the next connect', () async {
      store.token = 'tok-old';
      answer((_) async => {'status': 'connected', 'restoreToken': null});

      final result = await service().connect();

      expect(calls.single.arguments, {'restoreToken': 'tok-old'});
      expect(result.isConnected, isTrue);
      expect(result.restoreToken, isNull);
      // Without a new token the stored one stays.
      expect(store.token, 'tok-old');
      expect(store.writes, 0);
    });

    test(
      'a cancelled dialog keeps the stored token and stores nothing',
      () async {
        store.token = 'tok-old';
        answer((_) async => {'status': 'cancelled', 'restoreToken': null});

        final result = await service().connect();

        expect(result.status, PortalInputConnectStatus.cancelled);
        expect(result.isConnected, isFalse);
        expect(store.token, 'tok-old');
        expect(store.writes, 0);
      },
    );

    test('unavailable is passed through', () async {
      answer((_) async => {'status': 'unavailable', 'restoreToken': null});
      final result = await service().connect();
      expect(result.status, PortalInputConnectStatus.unavailable);
    });

    test('an unknown status counts as failed', () async {
      answer((_) async => {'status': 'weird', 'restoreToken': 'tok-x'});
      final result = await service().connect();
      expect(result.status, PortalInputConnectStatus.failed);
      // A token attached to a non-connected answer is not stored.
      expect(store.writes, 0);
    });

    test('a non-map answer counts as failed', () async {
      answer((_) async => null);
      final result = await service().connect();
      expect(result.status, PortalInputConnectStatus.failed);
    });

    test('no native handler reports unavailable', () async {
      final result = await service().connect();
      expect(result.status, PortalInputConnectStatus.unavailable);
    });

    test('a platform error reports failed', () async {
      answer((_) async => throw PlatformException(code: 'portal'));
      final result = await service().connect();
      expect(result.status, PortalInputConnectStatus.failed);
    });

    test('an empty restore token is not stored', () async {
      answer((_) async => {'status': 'connected', 'restoreToken': ''});
      final result = await service().connect();
      expect(result.isConnected, isTrue);
      expect(result.restoreToken, isNull);
      expect(store.writes, 0);
    });
  });

  group('disconnect and consent', () {
    test('disconnect calls the native side and keeps the token', () async {
      store.token = 'tok-keep';
      answer((_) async => null);

      await service().disconnect();

      expect(calls.single.method, 'portalInputDisconnect');
      expect(store.token, 'tok-keep');
    });

    test('disconnect without a native handler does not throw', () async {
      await service().disconnect();
    });

    test('forgetConsent clears the stored token', () async {
      store.token = 'tok-forget';
      await service().forgetConsent();
      expect(store.token, isNull);
    });
  });

  group('paste over the portal', () {
    test('pasteClipboard sends via=portal, delay and shift', () async {
      answer((_) async => {'status': 'success'});

      final result = await service().pasteClipboard(
        delay: const Duration(milliseconds: 120),
        shift: true,
      );

      expect(calls.single.method, 'pasteClipboard');
      expect(calls.single.arguments, {
        'delayMs': 120,
        'shift': true,
        'via': 'portal',
      });
      expect(result.isSuccess, isTrue);
    });

    test('copySelection defaults to a plain Ctrl+C', () async {
      answer((_) async => {'status': 'success'});

      final result = await service().copySelection(delay: Duration.zero);

      expect(calls.single.method, 'copySelection');
      expect(calls.single.arguments, {
        'delayMs': 0,
        'shift': false,
        'via': 'portal',
      });
      expect(result.isSuccess, isTrue);
    });

    test('a permission answer from the native side is kept', () async {
      answer(
        (_) async => {
          'status': 'permission_missing',
          'detail': 'portal input not connected',
        },
      );

      final result = await service().pasteClipboard(delay: Duration.zero);

      expect(result.status, NativePasteStatus.permissionMissing);
      expect(result.detail, 'portal input not connected');
    });

    test('no native handler gives an unknown status, not a success', () async {
      final result = await service().pasteClipboard(delay: Duration.zero);
      expect(result.status, NativePasteStatus.unknown);
      expect(result.isSuccess, isFalse);
    });

    test('a platform error maps to post failed', () async {
      answer((_) async => throw PlatformException(code: 'paste'));
      final result = await service().pasteClipboard(delay: Duration.zero);
      expect(result.status, NativePasteStatus.postFailed);
    });
  });
}
