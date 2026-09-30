import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/secure_key_store.dart';

void main() {
  group('SecureKeyStore default storage', () {
    test('avoids the macOS data-protection keychain', () {
      // Regression: with usesDataProtectionKeychain=true (plugin default)
      // every keychain write fails with errSecMissingEntitlement (-34018)
      // because the non-sandboxed Runner has no keychain-access-groups
      // entitlement — API keys silently never persist and reads return
      // null, breaking all cloud STT providers on macOS.
      final mOptions = defaultSecureStorage.mOptions;

      expect(mOptions, isA<MacOsOptions>());
      expect(
        (mOptions as MacOsOptions).usesDataProtectionKeychain,
        isFalse,
        reason:
            'The data-protection keychain requires a keychain-access-groups '
            'entitlement that the WhisPaste Runner does not ship with.',
      );
    });
  });

  // Regression test for GitHub #151 (Linux: process alive, no window, no
  // tray, log ends at "Single instance lock acquired"). The Linux plugin
  // unlocks a locked default collection with a *synchronous*
  // secret_service_unlock_sync on the GTK main thread; when the unlock
  // prompt never shows up, that call never returns and freezes the whole
  // platform thread — window_manager's show() included. A channel that
  // never answers stands in for that frozen thread here.
  group('SecureKeyStore with a locked keyring', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final pluginCalls = <String>[];

    setUp(() {
      pluginCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
            pluginCalls.add(call.method);
            return Completer<Object?>().future; // frozen platform thread
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'fails fast with KeyringLocked instead of calling the plugin',
      () async {
        final store = SecureKeyStore(null, () async => true);

        for (final op in <Future<Object?> Function()>[
          store.readAllApiKeys,
          () => store.readKey('wp_openai_api_key'),
          () => store.deleteKey('wp_groq_api_key'),
          () => store.writeKey('wp_openai_api_key', 'sk-test'),
        ]) {
          await expectLater(
            op().timeout(const Duration(seconds: 2)),
            throwsA(
              isA<PlatformException>().having(
                (e) => e.code,
                'code',
                'KeyringLocked',
              ),
            ),
          );
        }
        expect(pluginCalls, isEmpty);
      },
    );

    test(
      'still delegates to the plugin when the keyring is unlocked',
      () async {
        final store = SecureKeyStore(null, () async => false);

        unawaited(store.readKey('wp_openai_api_key'));
        await pumpEventQueue();

        expect(pluginCalls, ['read']);
      },
    );
  });
}
