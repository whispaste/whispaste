import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/core/config/data_key_store.dart';
import 'package:whispaste/core/config/secure_key_store.dart';

/// In-memory stand-in for the system key store.
class _FakeSecureStore extends SecureKeyStore {
  _FakeSecureStore() : super(null, () async => KeyringAvailability.usable);

  final values = <String, String>{};
  Object? failWith;

  /// Accepts writes but keeps nothing (macOS -34018 behaviour).
  bool dropWrites = false;

  @override
  Future<String?> readKey(String key) async {
    if (failWith != null) throw failWith!;
    return values[key];
  }

  @override
  Future<void> writeKey(String key, String value) async {
    if (failWith != null) throw failWith!;
    if (!dropWrites) values[key] = value;
  }

  @override
  Future<void> deleteKey(String key) async => values.remove(key);
}

PlatformException _keyring(String state) =>
    PlatformException(code: keyringLockedCode, details: state);

void main() {
  late Directory dir;
  late _FakeSecureStore secure;

  DataKeyStore store({bool linux = false}) => DataKeyStore(
    secure,
    dataDir: () => dir.path,
    isLinux: linux,
    posix: !Platform.isWindows,
  );

  File marker() => File(p.join(dir.path, dataKeyMarkerFileName));
  File fallback() => File(p.join(dir.path, dataKeyFallbackFileName));

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp_data_key_');
    secure = _FakeSecureStore();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('system key store', () {
    test('first need creates a random key in the system store', () async {
      final result = await store().obtain();

      expect(result, isA<DataKeyReady>());
      final ready = result as DataKeyReady;
      expect(ready.created, isTrue);
      expect(ready.backend, DataKeyBackend.systemKeyStore);
      expect(ready.usesFileFallback, isFalse);
      expect(ready.key.bytes, hasLength(dataKeyLength));
      expect(base64Decode(secure.values[dataKeyStorageName]!), ready.key.bytes);
      expect(fallback().existsSync(), isFalse);
    });

    test('two keys differ (random, not derived)', () async {
      final a = (await store().obtain()) as DataKeyReady;
      secure.values.clear();
      marker().deleteSync();
      final b = (await store().obtain()) as DataKeyReady;
      expect(a.key.bytes, isNot(b.key.bytes));
    });

    test('reads the same key back in a later session', () async {
      final first = (await store().obtain()) as DataKeyReady;
      final again = await store().obtain();

      expect(again, isA<DataKeyReady>());
      expect((again as DataKeyReady).created, isFalse);
      expect(again.key.bytes, first.key.bytes);
    });

    test('concurrent first needs create only one key', () async {
      final s = store();
      final results = await Future.wait([s.obtain(), s.obtain()]);
      final keys = results.cast<DataKeyReady>().map((r) => r.key.bytes);
      expect(keys.first, keys.last);
    });

    test('a key without marker (interrupted first need) is adopted', () async {
      final bytes = List<int>.generate(dataKeyLength, (i) => i);
      secure.values[dataKeyStorageName] = base64Encode(bytes);

      final result = (await store().obtain()) as DataKeyReady;
      expect(result.key.bytes, bytes);
      expect(result.created, isFalse);
      expect(marker().existsSync(), isTrue);
    });

    test('a write that does not persist leaves no marker', () async {
      secure.dropWrites = true;
      final result = await store().obtain();

      expect(result, isA<DataKeyUnavailable>());
      expect(marker().existsSync(), isFalse);
    });
  });

  group('lost key', () {
    test('deleted from the system store: lost, no new key', () async {
      await store().obtain();
      secure.values.clear();

      final result = await store().obtain();
      expect(result, isA<DataKeyLost>());
      expect((result as DataKeyLost).backend, DataKeyBackend.systemKeyStore);
      expect(secure.values, isEmpty, reason: 'must not create a new key');
    });

    test('replaced by another key: lost, the other key is kept', () async {
      await store().obtain();
      final other = base64Encode(List<int>.filled(dataKeyLength, 7));
      secure.values[dataKeyStorageName] = other;

      expect(await store().obtain(), isA<DataKeyLost>());
      expect(secure.values[dataKeyStorageName], other);
    });

    test('fallback file deleted: lost, no new file', () async {
      secure.failWith = _keyring('unreachable');
      await store(linux: true).obtain();
      fallback().deleteSync();

      final result = await store(linux: true).obtain();
      expect(result, isA<DataKeyLost>());
      expect((result as DataKeyLost).backend, DataKeyBackend.file);
      expect(fallback().existsSync(), isFalse);
    });

    test('unreadable marker: unavailable, nothing overwritten', () async {
      marker().writeAsStringSync('{broken');

      expect(await store().obtain(), isA<DataKeyUnavailable>());
      expect(secure.values, isEmpty);
      expect(marker().readAsStringSync(), '{broken');
    });
  });

  group('locked or unreachable keyring', () {
    test('a locked keyring is reported, never replaced by a file', () async {
      secure.failWith = _keyring('locked');

      final result = await store(linux: true).obtain();
      expect(
        (result as DataKeyUnavailable).reason,
        DataKeyUnavailableReason.keyringLocked,
      );
      expect(fallback().existsSync(), isFalse);
      expect(marker().existsSync(), isFalse);
    });

    test('an existing keyring key that is unreachable is not lost', () async {
      await store(linux: true).obtain();
      secure.failWith = _keyring('unreachable');

      final result = await store(linux: true).obtain();
      expect(
        (result as DataKeyUnavailable).reason,
        DataKeyUnavailableReason.keyringUnreachable,
      );
      expect(fallback().existsSync(), isFalse);
    });

    test('outside Linux a failing store never falls back to a file', () async {
      secure.failWith = PlatformException(code: 'Unexpected');

      final result = await store().obtain();
      expect(
        (result as DataKeyUnavailable).reason,
        DataKeyUnavailableReason.storageFailed,
      );
      expect(fallback().existsSync(), isFalse);
    });
  });

  group('Linux fallback', () {
    for (final cause in [
      _keyring('unreachable'),
      PlatformException(code: 'Libsecret error'),
    ]) {
      test('no Secret Service (${cause.code}/${cause.details}): '
          'owner-only file plus hint', () async {
        secure.failWith = cause;

        final result = (await store(linux: true).obtain()) as DataKeyReady;
        expect(result.backend, DataKeyBackend.file);
        expect(result.usesFileFallback, isTrue);
        expect(result.created, isTrue);
        expect(base64Decode(fallback().readAsStringSync()), result.key.bytes);
        if (!Platform.isWindows) {
          expect(fallback().statSync().mode & 0x1FF, 0x180);
        }
      });
    }

    test('the fallback sticks once the Secret Service appears', () async {
      secure.failWith = _keyring('unreachable');
      final first = (await store(linux: true).obtain()) as DataKeyReady;
      secure.failWith = null;

      final again = (await store(linux: true).obtain()) as DataKeyReady;
      expect(again.backend, DataKeyBackend.file);
      expect(again.usesFileFallback, isTrue);
      expect(again.key.bytes, first.key.bytes);
      expect(secure.values, isEmpty);
    });
  });

  group('restore (#1167)', () {
    List<int> key(int seed) => List<int>.generate(dataKeyLength, (i) => seed);

    test('a fresh data folder gets the key and the same fingerprint', () async {
      final result = await store().restore(key(7));

      expect(result, isA<DataKeyRestored>());
      expect(base64Decode(secure.values[dataKeyStorageName]!), key(7));
      final again = (await store().obtain()) as DataKeyReady;
      expect(again.key.bytes, key(7));
      expect(again.created, isFalse);
      expect(store().recordedBackupAt(), isNotNull);
    });

    test('a lost key comes back, the marker and backup date stay', () async {
      final first = (await store().obtain()) as DataKeyReady;
      await store().recordBackup(first.key, DateTime.utc(2026, 1, 2));
      secure.values.clear();
      expect(await store().obtain(), isA<DataKeyLost>());
      final markerBefore = marker().readAsStringSync();

      final result = await store().restore(first.key.bytes);

      expect(result, isA<DataKeyRestored>());
      expect(marker().readAsStringSync(), markerBefore);
      final again = (await store().obtain()) as DataKeyReady;
      expect(again.key.bytes, first.key.bytes);
    });

    test('a backup of another key is refused, nothing overwritten', () async {
      final first = (await store().obtain()) as DataKeyReady;
      final storedBefore = secure.values[dataKeyStorageName];
      final markerBefore = marker().readAsStringSync();

      final result = await store().restore(key(9));

      expect(result, isA<DataKeyRestoreFailed>());
      expect(
        (result as DataKeyRestoreFailed).failure,
        DataKeyRestoreFailure.otherKey,
      );
      expect(secure.values[dataKeyStorageName], storedBefore);
      expect(marker().readAsStringSync(), markerBefore);
      expect(
        ((await store().obtain()) as DataKeyReady).key.bytes,
        first.key.bytes,
      );
    });

    test('a replaced key in the store is set aside, not overwritten', () async {
      final first = (await store().obtain()) as DataKeyReady;
      final stranger = base64Encode(key(3));
      secure.values[dataKeyStorageName] = stranger;

      await store().restore(first.key.bytes);

      expect(base64Decode(secure.values[dataKeyStorageName]!), first.key.bytes);
      final setAside = secure.values.entries.where(
        (e) => e.key.startsWith(dataKeySetAsidePrefix),
      );
      expect(setAside.single.value, stranger);
    });

    test(
      'a backup matching the marker overwrites a wrong key (#1461)',
      () async {
        final first = (await store().obtain()) as DataKeyReady;
        secure.values[dataKeyStorageName] = base64Encode(key(3));
        expect(await store().obtain(), isA<DataKeyLost>());

        final result = await store().restore(first.key.bytes);

        expect(result, isA<DataKeyRestored>());
        expect(
          base64Decode(secure.values[dataKeyStorageName]!),
          first.key.bytes,
        );
        expect(
          ((await store().obtain()) as DataKeyReady).key.bytes,
          first.key.bytes,
        );
      },
    );

    test('matchesMarker accepts only the marked key', () async {
      expect(store().matchesMarker(base64Encode(key(1))), isTrue); // no marker
      final first = (await store().obtain()) as DataKeyReady;
      expect(store().matchesMarker(base64Encode(first.key.bytes)), isTrue);
      expect(store().matchesMarker(base64Encode(key(1))), isFalse);
      expect(store().matchesMarker('garbage'), isFalse);
    });

    test('a locked keyring is reported and nothing is written', () async {
      secure.failWith = _keyring('locked');

      final result = await store().restore(key(7));

      expect(
        (result as DataKeyRestoreFailed).failure,
        DataKeyRestoreFailure.keyringLocked,
      );
      expect(marker().existsSync(), isFalse);
    });

    test('Linux fallback: the file comes back, a stray file is kept', () async {
      secure.failWith = PlatformException(code: 'no-secret-service');
      final first = (await store(linux: true).obtain()) as DataKeyReady;
      fallback().writeAsStringSync(base64Encode(key(4)));
      expect(await store(linux: true).obtain(), isA<DataKeyLost>());

      final result = await store(linux: true).restore(first.key.bytes);

      expect(result, isA<DataKeyRestored>());
      expect(base64Decode(fallback().readAsStringSync()), first.key.bytes);
      final kept = dir.listSync().whereType<File>().where(
        (f) => p.basename(f.path).endsWith('.lost.secret'),
      );
      expect(base64Decode(kept.single.readAsStringSync()), key(4));
    });
  });

  group('replace lost key (#1167)', () {
    test('only acts when the key is lost', () async {
      final first = (await store().obtain()) as DataKeyReady;

      final result = await store().replaceLostKey();

      expect((result as DataKeyReady).key.bytes, first.key.bytes);
      expect(result.created, isFalse);
    });

    test('keeps the old marker and creates a new key', () async {
      final first = (await store().obtain()) as DataKeyReady;
      final markerBefore = marker().readAsStringSync();
      secure.values.clear();

      final result = await store().replaceLostKey(
        now: DateTime.utc(2026, 11, 10, 14, 23, 1),
      );

      final ready = result as DataKeyReady;
      expect(ready.created, isTrue);
      expect(ready.key.bytes, isNot(first.key.bytes));
      final archived = File(
        p.join(dir.path, 'data_key.20261110T142301Z.lost.json'),
      );
      expect(archived.readAsStringSync(), markerBefore);
      expect(
        ((await store().obtain()) as DataKeyReady).key.bytes,
        ready.key.bytes,
      );
    });

    test('Linux fallback: the old key file is renamed, not deleted', () async {
      secure.failWith = PlatformException(code: 'no-secret-service');
      await store(linux: true).obtain();
      fallback().writeAsStringSync('broken');
      expect(await store(linux: true).obtain(), isA<DataKeyLost>());

      final result = await store(linux: true).replaceLostKey();

      expect(result, isA<DataKeyReady>());
      final kept = dir.listSync().whereType<File>().where(
        (f) => p.basename(f.path).endsWith('.lost.secret'),
      );
      expect(kept.single.readAsStringSync(), 'broken');
    });
  });

  group('secrecy', () {
    test('the key never shows up in toString or the marker', () async {
      final ready = (await store().obtain()) as DataKeyReady;
      final encoded = base64Encode(ready.key.bytes);
      final hex = ready.key.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      for (final text in [
        '${ready.key}',
        '$ready',
        marker().readAsStringSync(),
      ]) {
        expect(text, isNot(contains(encoded)));
        expect(text, isNot(contains(hex)));
      }
      expect(
        (jsonDecode(marker().readAsStringSync())
            as Map<String, Object?>)['fingerprint'],
        dataKeyFingerprint(ready.key.bytes),
      );
    });

    test('the key is neither exported nor erased with the API keys', () {
      expect(apiKeyMapping.values, isNot(contains(dataKeyStorageName)));
      expect(allSecureKeys, isNot(contains(dataKeyStorageName)));
    });
  });
}
