import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/keychain_migration.dart';
import 'package:whispaste/core/config/secure_access_gate.dart';
import 'package:whispaste/core/config/secure_key_store.dart';

/// Hand-over point: plugin channel with one map per macOS keychain as the
/// platform side. `readAll` on the legacy keychain is the one system dialog;
/// [dialogs] counts it, [answer] decides how the user reacts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const keys = ['data_key', 'api_key', 'token'];

  late Map<bool, Map<String, String>> keychains;
  late int dialogs;
  late bool cancel;
  late bool readAllRefused;
  late bool cancelSingle;
  late bool singleFails;
  late Set<String> quietlyReadable;
  // #1674: the plugin's old-keychain storage also reaches the new item (read
  // and delete), as measured in a sandboxed build with an access group.
  late bool aliased;
  late bool newWriteFails;
  late int pluginReadAlls;
  late KeychainMigration migration;
  bool Function(String, String)? verifier;

  Map<String, String> legacyKc() => keychains[false]!;
  Map<String, String> newKc() => keychains[true]!;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    keychains = {true: {}, false: {}};
    dialogs = 0;
    cancel = false;
    readAllRefused = false;
    cancelSingle = false;
    singleFails = false;
    quietlyReadable = {};
    aliased = false;
    newWriteFails = false;
    pluginReadAlls = 0;
    verifier = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = (call.arguments as Map).cast<String, Object?>();
          final options = (args['options']! as Map).cast<String, String>();
          final kc =
              keychains[options['usesDataProtectionKeychain'] == 'true']!;
          final key = args['key'] as String?;
          final isNew = options['usesDataProtectionKeychain'] == 'true';
          switch (call.method) {
            case 'write':
              if (isNew && newWriteFails) {
                throw PlatformException(
                  code: 'Unexpected security result code',
                  message: 'Code: -34018, Message: missing entitlement',
                );
              }
              kc[key!] = args['value']! as String;
              return null;
            case 'read':
              // A dialog only appears for an item that exists.
              if (options['usesDataProtectionKeychain'] != 'true' &&
                  kc.containsKey(key)) {
                dialogs++;
                if (cancelSingle) {
                  throw PlatformException(code: '-128', message: 'canceled');
                }
                if (singleFails) {
                  throw PlatformException(code: '-25308', message: 'no UI');
                }
              }
              return kc[key] ?? (aliased && !isNew ? newKc()[key] : null);
            case 'delete':
              kc.remove(key);
              if (aliased && !isNew) newKc().remove(key);
              return null;
            case 'readAll':
              pluginReadAlls++;
              if (readAllRefused) {
                throw PlatformException(
                  code: 'Unexpected security result code',
                  message: 'Code: -50, Message: errSecParam',
                );
              }
              dialogs++;
              if (cancel) {
                throw PlatformException(code: '-128', message: 'canceled');
              }
              return Map<String, String>.of(kc);
          }
          throw MissingPluginException(call.method);
        });
    final storages = secureStoragesFor(isMacOS: true, hasAccessGroup: true);
    migration = KeychainMigration(
      legacy: storages.legacy!,
      primary: storages.primary,
      keys: keys,
      repairKeys: {'data_key'},
      verify: (key, value) => verifier?.call(key, value) ?? true,
      quietReader: (key) async {
        final value = legacyKc()[key];
        if (value == null) {
          return const QuietReadResult(QuietReadStatus.missing);
        }
        return quietlyReadable.contains(key)
            ? QuietReadResult(QuietReadStatus.ok, value: value)
            : const QuietReadResult(QuietReadStatus.needsConsent);
      },
    );
  });

  /// The old keychain through the native file-keychain query: only ever
  /// the old map, whatever [aliased] says.
  KeychainMigration nativeMigration() {
    final storages = secureStoragesFor(isMacOS: true, hasAccessGroup: true);
    return KeychainMigration(
      legacy: storages.legacy!,
      primary: storages.primary,
      keys: keys,
      oldKeychain: _MapOldKeychain(legacyKc),
      quietReader: (key) async {
        final value = legacyKc()[key];
        return value == null
            ? const QuietReadResult(QuietReadStatus.missing)
            : QuietReadResult(QuietReadStatus.ok, value: value);
      },
    );
  }

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('moves every entry old -> new with one dialog and removes the old '
      'ones', () async {
    legacyKc().addAll({'data_key': 'k', 'api_key': 'a', 'token': 't'});
    final scan = await migration.scan();
    expect(scan.pending, keys);
    expect(dialogs, 0, reason: 'announcing never prompts');

    final outcome = await migration.migratePending(scan.pending);

    expect(outcome, KeychainMigrationOutcome.done);
    expect(dialogs, 1);
    expect(newKc(), {'data_key': 'k', 'api_key': 'a', 'token': 't'});
    expect(legacyKc(), isEmpty);
  });

  test(
    'quietly readable entries move at once, the rest stays pending',
    () async {
      legacyKc().addAll({'data_key': 'k', 'api_key': 'a'});
      quietlyReadable = {'data_key'};
      final scan = await migration.scan();
      expect(scan.movedQuietly, ['data_key']);
      expect(scan.pending, ['api_key']);
      expect(newKc(), {'data_key': 'k'});
      expect(legacyKc(), {'api_key': 'a'});
    },
  );

  test('cancel changes nothing and the move can be started again', () async {
    legacyKc().addAll({'data_key': 'k', 'api_key': 'a'});
    final scan = await migration.scan();
    cancel = true;
    expect(
      await migration.migratePending(scan.pending),
      KeychainMigrationOutcome.declined,
    );
    expect(newKc(), isEmpty);
    expect(legacyKc(), {'data_key': 'k', 'api_key': 'a'});

    cancel = false;
    final again = await migration.scan();
    expect(again.pending, ['data_key', 'api_key']);
    expect(
      await migration.migratePending(again.pending),
      KeychainMigrationOutcome.done,
    );
    expect(newKc(), {'data_key': 'k', 'api_key': 'a'});
    expect(legacyKc(), isEmpty);
  });

  test('restart after a move finds nothing and asks nothing', () async {
    legacyKc().addAll({'data_key': 'k'});
    await migration.migratePending((await migration.scan()).pending);
    final again = await migration.scan();
    expect(again.pending, isEmpty);
    expect(again.movedQuietly, isEmpty);
    expect(
      await migration.migratePending(again.pending),
      KeychainMigrationOutcome.done,
    );
    expect(dialogs, 1, reason: 'no second dialog');
    expect(newKc(), {'data_key': 'k'});
  });

  test('a different value in the new keychain wins, the old entry is '
      'kept (#1461)', () async {
    legacyKc()['api_key'] = 'old';
    newKc()['api_key'] = 'new';
    final outcome = await migration.migratePending(['api_key']);
    expect(outcome, KeychainMigrationOutcome.done);
    expect(newKc()['api_key'], 'new');
    expect(legacyKc(), {'api_key': 'old'});
  });

  test('an equal value in the new keychain removes the old entry', () async {
    legacyKc()['api_key'] = 'same';
    newKc()['api_key'] = 'same';
    await migration.migratePending(['api_key']);
    expect(newKc()['api_key'], 'same');
    expect(legacyKc(), isEmpty);
  });

  test('a wrong data key in the new keychain is replaced by the verified old '
      'one, the wrong one is set aside', () async {
    legacyKc()['data_key'] = 'right';
    newKc()['data_key'] = 'wrong';
    verifier = (key, value) => value == 'right';
    await migration.migratePending(['data_key']);
    expect(newKc()['data_key'], 'right');
    expect(legacyKc(), isEmpty);
    final aside = newKc().entries.where(
      (e) => e.key.startsWith('wp_data_key.set_aside.'),
    );
    expect(aside.single.value, 'wrong');
  });

  test('a failing verifier writes nothing and keeps the old entry', () async {
    legacyKc().addAll({'data_key': 'bad', 'api_key': 'a'});
    verifier = (key, value) => key != 'data_key';
    final outcome = await migration.migratePending(['data_key', 'api_key']);
    expect(outcome, KeychainMigrationOutcome.done);
    expect(newKc(), {'api_key': 'a'});
    expect(legacyKc(), {'data_key': 'bad'});
  });

  test('readAll refused with -50: entries are read one by one and move '
      '(#1461)', () async {
    legacyKc().addAll({'data_key': 'k', 'api_key': 'a', 'token': 't'});
    readAllRefused = true;
    final scan = await migration.scan();
    expect(
      await migration.migratePending(scan.pending),
      KeychainMigrationOutcome.done,
    );
    expect(newKc(), {'data_key': 'k', 'api_key': 'a', 'token': 't'});
    expect(legacyKc(), isEmpty);
  });

  test('a "no" in a single read is declined and nothing is deleted', () async {
    legacyKc().addAll({'data_key': 'k', 'api_key': 'a'});
    readAllRefused = true;
    cancelSingle = true;
    final scan = await migration.scan();
    expect(
      await migration.migratePending(scan.pending),
      KeychainMigrationOutcome.declined,
    );
    expect(newKc(), isEmpty);
    expect(legacyKc(), {'data_key': 'k', 'api_key': 'a'});
  });

  test('a technical error in single reads is failed, not declined', () async {
    legacyKc().addAll({'data_key': 'k'});
    readAllRefused = true;
    singleFails = true;
    final scan = await migration.scan();
    expect(
      await migration.migratePending(scan.pending),
      KeychainMigrationOutcome.failed,
    );
    expect(legacyKc(), {'data_key': 'k'});
  });

  group('#1674: the move sticks', () {
    test('move -> the next read of the new keychain finds the key', () async {
      aliased = true;
      legacyKc()['data_key'] = 'k';
      final migration = nativeMigration();

      final scan = await migration.scan();

      expect(scan.movedQuietly, ['data_key']);
      expect(legacyKc(), isEmpty);
      // Next start: the store reads the same plugin storage the move wrote.
      final store = SecureKeyStore.layered(
        primary: dataProtectionSecureStorage,
        probeKeyring: () async => KeyringAvailability.usable,
      );
      expect(await store.readKey('data_key'), 'k');
      final again = await migration.scan();
      expect(again.movedQuietly, isEmpty, reason: 'nothing moves twice');
      expect(newKc(), {'data_key': 'k'});
    });

    test('a delete that also removes the new entry is not "moved"; the new '
        'entry is written again', () async {
      aliased = true;
      quietlyReadable = {'data_key'};
      newKc()['data_key'] = 'k';
      legacyKc()['data_key'] = 'k';

      final scan = await migration.scan();

      expect(scan.movedQuietly, isEmpty);
      expect(newKc(), {'data_key': 'k'});
    });

    test('#1841: a leftover duplicate whose second delete takes the new entry '
        'too does not lose the key', () async {
      legacyKc()['data_key'] = 'k';
      var deletes = 0;
      final storages = secureStoragesFor(isMacOS: true, hasAccessGroup: true);
      final migration = KeychainMigration(
        legacy: storages.legacy!,
        primary: storages.primary,
        keys: keys,
        oldKeychain: _CallbackOldKeychain(
          read: (key) => legacyKc()[key],
          delete: (key) {
            deletes++;
            // The first delete leaves a duplicate; the second one removes
            // the data-protection item as well.
            if (deletes == 2) {
              legacyKc().remove(key);
              newKc().remove(key);
            }
          },
        ),
        quietReader: (key) async {
          final value = legacyKc()[key];
          return value == null
              ? const QuietReadResult(QuietReadStatus.missing)
              : QuietReadResult(QuietReadStatus.ok, value: value);
        },
      );

      final scan = await migration.scan();

      expect(deletes, 2);
      expect(newKc(), {'data_key': 'k'}, reason: 'the key must survive');
      expect(scan.movedQuietly, isEmpty, reason: 'not reported as moved');
    });

    test('a failed write is not "moved" and keeps the old entry', () async {
      newWriteFails = true;
      legacyKc()['data_key'] = 'k';
      final migration = nativeMigration();

      final scan = await migration.scan();

      expect(scan.movedQuietly, isEmpty);
      expect(legacyKc(), {'data_key': 'k'});
      expect(newKc(), isEmpty);
      expect(
        await migration.migratePending(['data_key']),
        KeychainMigrationOutcome.failed,
      );
      expect(legacyKc(), {'data_key': 'k'});
    });

    test('after consent the native old keychain is read one by one, never '
        'through the plugin readAll', () async {
      aliased = true;
      legacyKc().addAll({'data_key': 'k', 'api_key': 'a'});
      final migration = nativeMigration();

      final outcome = await migration.migratePending(['data_key', 'api_key']);

      expect(outcome, KeychainMigrationOutcome.done);
      expect(pluginReadAlls, 0);
      expect(newKc(), {'data_key': 'k', 'api_key': 'a'});
      expect(legacyKc(), isEmpty);
    });
  });
}

class _CallbackOldKeychain implements OldKeychain {
  _CallbackOldKeychain({
    required String? Function(String) read,
    required void Function(String) delete,
  }) : read_ = read,
       delete_ = delete;

  final String? Function(String) read_;
  final void Function(String) delete_;

  @override
  Future<String?> read(String key) async => read_(key);

  @override
  Future<void> delete(String key) async => delete_(key);
}

class _MapOldKeychain implements OldKeychain {
  _MapOldKeychain(this._kc);

  final Map<String, String> Function() _kc;

  @override
  Future<String?> read(String key) async => _kc()[key];

  @override
  Future<void> delete(String key) async => _kc().remove(key);
}
