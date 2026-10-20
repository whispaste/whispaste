/// XP-6-11: a keyring that never answers must not hold the factory reset.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';

/// Secure storage whose deletes never complete, like a locked keyring
/// waiting on an unlock prompt that never appears.
class _HangingSecureKeyStore extends SecureKeyStore {
  @override
  Future<void> deleteKey(String key) => Completer<void>().future;
}

void main() {
  late ProviderContainer container;

  setUp(() async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        secureKeyStoreProvider.overrideWithValue(_HangingSecureKeyStore()),
      ],
    );
    await container.read(settingsProvider.future);
  });

  tearDown(() {
    container.dispose();
    secureStoreEraseTimeout = kDefaultSecureStoreEraseTimeout;
  });

  test('the default limit is a few seconds', () {
    expect(kDefaultSecureStoreEraseTimeout, const Duration(seconds: 5));
  });

  test('a hanging keyring fails the secure-store step after the limit '
      'and names every key', () async {
    secureStoreEraseTimeout = const Duration(milliseconds: 50);
    final settings = container.read(settingsProvider.notifier);

    final watch = Stopwatch()..start();
    await expectLater(
      settings.eraseSecureStore(),
      throwsA(
        isA<SecureKeysNotRemovedException>().having(
          (e) => e.keys,
          'keys',
          unorderedEquals(apiKeyMapping.values),
        ),
      ),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
