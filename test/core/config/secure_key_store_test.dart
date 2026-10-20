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
        final store = SecureKeyStore(
          null,
          () async => KeyringAvailability.locked,
        );

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
        final store = SecureKeyStore(
          null,
          () async => KeyringAvailability.usable,
        );

        unawaited(store.readKey('wp_openai_api_key'));
        await pumpEventQueue();

        expect(pluginCalls, ['read']);
      },
    );

    // XP-7-01: a session bus that cannot start the Secret Service made every
    // plugin call wait 25 s on the GTK main thread, so `--toggle` and the end
    // of a recording waited with it. The probe reports that as unreachable.
    test('fails fast without the plugin when the Secret Service is '
        'unreachable, and probes only once within the retry window', () async {
      var probes = 0;
      final store = SecureKeyStore(null, () async {
        probes++;
        return KeyringAvailability.unreachable;
      });

      for (final op in <Future<Object?> Function()>[
        store.readAllApiKeys,
        () => store.deleteKey('wp_openai_api_key'),
        () => store.deleteKey('wp_deepgram_api_key'),
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
      expect(probes, 1);
    });

    // A Secret Service that starts late (gnome-keyring after login) must not
    // disable the keys for the whole session: the unreachable mark expires
    // after the retry window and the next call probes again.
    test('probes an unreachable Secret Service again after the retry window, '
        'so a late start is picked up', () async {
      var now = DateTime(2026, 10, 19, 12);
      var reachable = false;
      var probes = 0;
      final store = SecureKeyStore(null, () async {
        probes++;
        return reachable
            ? KeyringAvailability.usable
            : KeyringAvailability.unreachable;
      }, () => now);

      await expectLater(
        store.readKey('wp_openai_api_key'),
        throwsA(isA<PlatformException>()),
      );
      now = now.add(const Duration(seconds: 29));
      await expectLater(
        store.readKey('wp_openai_api_key'),
        throwsA(isA<PlatformException>()),
      );
      expect(probes, 1, reason: 'still inside the retry window');

      reachable = true;
      now = now.add(const Duration(seconds: 2));
      unawaited(store.readKey('wp_openai_api_key'));
      await pumpEventQueue();

      expect(probes, 2);
      expect(pluginCalls, ['read']);
    });

    test(
      'probes a locked keyring again, so unlocking it later works',
      () async {
        var locked = true;
        final store = SecureKeyStore(
          null,
          () async =>
              locked ? KeyringAvailability.locked : KeyringAvailability.usable,
        );

        await expectLater(
          store.readKey('wp_openai_api_key'),
          throwsA(isA<PlatformException>()),
        );
        locked = false;
        unawaited(store.readKey('wp_openai_api_key'));
        await pumpEventQueue();

        expect(pluginCalls, ['read']);
      },
    );
  });
}
