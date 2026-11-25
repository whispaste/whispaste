import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:whispaste/core/config/data_key_store.dart'
    show dataKeyStorageName;
import 'package:whispaste/core/config/secure_access_gate.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/services/automation_api/automation_api_token_store.dart'
    show automationApiTokenKey, automationWriteTokenKey;
import 'package:whispaste/services/feedback_consent_store.dart'
    show kSecureConsentStateKey;

void main() {
  group('secureStoragesFor (ADR 0036)', () {
    bool dataProtection(FlutterSecureStorage storage) =>
        (storage.mOptions as MacOsOptions).usesDataProtectionKeychain;

    test('macOS with access group writes to the data-protection keychain '
        'and reads the legacy keychain as fallback', () {
      final storages = secureStoragesFor(isMacOS: true, hasAccessGroup: true);
      expect(dataProtection(storages.primary), isTrue);
      expect(storages.legacy, isNotNull);
      expect(dataProtection(storages.legacy!), isFalse);
    });

    test('without access group stays on the legacy keychain only', () {
      // Debug and ad-hoc builds: the data-protection keychain fails there
      // with errSecMissingEntitlement (-34018) and reads return null.
      for (final isMacOS in [true, false]) {
        final storages = secureStoragesFor(
          isMacOS: isMacOS,
          hasAccessGroup: false,
        );
        expect(dataProtection(storages.primary), isFalse);
        expect(storages.legacy, isNull);
      }
      final other = secureStoragesFor(isMacOS: false, hasAccessGroup: true);
      expect(dataProtection(other.primary), isFalse);
      expect(other.legacy, isNull);
    });
  });

  // Hand-over point: the plugin channel, with one map per macOS keychain
  // (data-protection vs. legacy login keychain) as the platform side.
  group('SecureKeyStore over both macOS keychains', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final keychains = <bool, Map<String, String>>{};

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      keychains
        ..clear()
        ..[true] = {}
        ..[false] = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = (call.arguments as Map).cast<String, Object?>();
            final options = (args['options']! as Map).cast<String, String>();
            final keychain =
                keychains[options['usesDataProtectionKeychain'] == 'true']!;
            final key = args['key'] as String?;
            switch (call.method) {
              case 'write':
                keychain[key!] = args['value']! as String;
                return null;
              case 'read':
                return keychain[key];
              case 'delete':
                keychain.remove(key);
                return null;
            }
            throw MissingPluginException(call.method);
          });
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    SecureKeyStore launch() {
      final storages = secureStoragesFor(isMacOS: true, hasAccessGroup: true);
      return SecureKeyStore.layered(
        primary: storages.primary,
        legacy: storages.legacy,
        probeKeyring: () async => KeyringAvailability.usable,
      );
    }

    final everySecret = [
      dataKeyStorageName,
      kSecureConsentStateKey,
      automationApiTokenKey,
      automationWriteTokenKey,
      ...allSecureKeys,
    ];

    test('save, restart, read returns the same value for every secret, '
        'stored in the access group', () async {
      final before = launch();
      for (final key in everySecret) {
        await before.writeKey(key, 'value-of-$key');
      }

      final after = launch(); // a new process: nothing cached in Dart
      for (final key in everySecret) {
        expect(await after.readKey(key), 'value-of-$key', reason: key);
      }
      expect(keychains[true]!.keys, unorderedEquals(everySecret));
      expect(keychains[false], isEmpty);
    });

    test('reads a secret stored before ADR 0036 without copying it', () async {
      keychains[false]!['wp_openai_api_key'] = 'sk-old';
      final store = launch();

      expect(await store.readKey('wp_openai_api_key'), 'sk-old');
      expect(await store.readAllApiKeys(), {'wp_openai_api_key': 'sk-old'});
      expect(keychains[true], isEmpty);
    });

    test('a value in the access group wins over the legacy one', () async {
      keychains[false]!['wp_openai_api_key'] = 'sk-old';
      final store = launch();
      await store.writeKey('wp_openai_api_key', 'sk-new');

      expect(await store.readKey('wp_openai_api_key'), 'sk-new');
    });

    test('delete clears both keychains so no old value reappears', () async {
      keychains[false]!['wp_openai_api_key'] = 'sk-old';
      final store = launch();
      await store.writeKey('wp_openai_api_key', 'sk-new');

      expect(await deleteAllApiKeys(store), isEmpty);
      expect(await launch().readKey('wp_openai_api_key'), isNull);
      expect(keychains[true], isEmpty);
      expect(keychains[false], isEmpty);
    });

    test(
      'closed gate (#1161): access group read as usual, the legacy '
      'keychain only quietly, held-back entries never via the plugin',
      () async {
        keychains[true]!['wp_openai_api_key'] = 'sk-new';
        keychains[false]!['wp_deepgram_api_key'] = 'dg-old';
        final quietReads = <String>[];
        final storages = secureStoragesFor(isMacOS: true, hasAccessGroup: true);
        final store = SecureKeyStore.layered(
          primary: storages.primary,
          legacy: storages.legacy,
          probeKeyring: () async => KeyringAvailability.usable,
          quietReader: (key) async {
            quietReads.add(key);
            return const QuietReadResult(QuietReadStatus.needsConsent);
          },
          gate: SecureAccessGate(),
        );

        expect(await store.readKey('wp_openai_api_key'), 'sk-new');
        expect(await store.readAllApiKeys(), {'wp_openai_api_key': 'sk-new'});
        expect(quietReads, isNot(contains('wp_openai_api_key')));
        expect(quietReads, contains('wp_deepgram_api_key'));
      },
    );
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
            op(),
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

    // #1164: Linux has no quiet reader, so the start must not reach the
    // plugin (which would show the unlock dialog) while the gate is still
    // closed. The log names every entry left unread and the trigger, never a
    // value.
    test('start with a closed gate logs entry names and trigger only, '
        'without the plugin', () async {
      final gate = SecureAccessGate();
      final store = SecureKeyStore(
        null,
        () async => KeyringAvailability.locked,
        null,
        null,
        gate,
      );
      Logger.root.level = Level.ALL;
      final lines = <String>[];
      final sub = Logger.root.onRecord.listen((r) => lines.add(r.message));
      addTearDown(sub.cancel);

      await expectLater(
        withSecureTrigger('settings start', store.readAllApiKeys),
        throwsA(isA<PlatformException>()),
      );

      expect(gate.promptsAllowed, isFalse);
      expect(pluginCalls, isEmpty);
      final line = lines.singleWhere((l) => l.startsWith('Key store read'));
      for (final key in apiKeyMapping.values) {
        expect(line, contains(key));
      }
      expect(line, contains('KeyringLocked'));
      expect(line, contains('(trigger: settings start)'));
    });

    // #1164 edge case: no default collection + old plaintext keys. The
    // migration write would make the plugin create the collection, which
    // shows the system "create keyring" dialog at start.
    test('start-time write without a default collection never reaches the '
        'plugin; a read and a user write still do', () async {
      final gate = SecureAccessGate();
      final store = SecureKeyStore(
        null,
        () async => KeyringAvailability.missing,
        null,
        null,
        gate,
      );

      await expectLater(
        withSecureTrigger(
          'settings start',
          () => withoutKeyringCreation(
            () => store.writeKey('wp_openai_api_key', 'sk-test'),
          ),
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            keyringLockedCode,
          ),
        ),
      );
      expect(pluginCalls, isEmpty);

      unawaited(store.readKey('wp_openai_api_key'));
      await pumpEventQueue();
      unawaited(store.writeKey('wp_openai_api_key', 'sk-test'));
      await pumpEventQueue();
      expect(pluginCalls, ['read', 'write']);
    });

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
          op(),
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
