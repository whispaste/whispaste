import 'package:drift/native.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';

const _secret = 'sk-test-secret-value';

/// Secure storage whose deletes always fail, as a locked or refusing keychain
/// does. Reads and writes are not used by these tests.
class FailingDeleteSecureKeyStore extends SecureKeyStore {
  @override
  Future<void> deleteKey(String key) async {
    throw PlatformException(code: 'denied', message: 'keychain refused');
  }
}

void main() {
  late HistoryDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        secureKeyStoreProvider.overrideWithValue(FailingDeleteSecureKeyStore()),
      ],
    );
    await container.read(settingsProvider.future);
    await container.read(settingsProvider.notifier).secureKeysFuture;
  });

  tearDown(() {
    container.dispose();
  });

  test(
    'resetToDefaults reports keys that could not be removed, not success',
    () async {
      final notifier = container.read(settingsProvider.notifier);

      await expectLater(
        notifier.resetToDefaults(),
        throwsA(
          isA<SecureKeysNotRemovedException>().having(
            (e) => e.keys,
            'keys',
            unorderedEquals(allSecureKeys),
          ),
        ),
      );
    },
  );

  test('the reset itself still completes when key removal fails', () async {
    final notifier = container.read(settingsProvider.notifier);

    await expectLater(
      notifier.resetToDefaults(),
      throwsA(isA<SecureKeysNotRemovedException>()),
    );

    final settings = container.read(settingsProvider).value;
    expect(settings!.locale, 'en');
    expect(settings.showOverlay, false);
  });

  test('eraseSecureStore reports failure instead of swallowing it', () async {
    await expectLater(
      container.read(settingsProvider.notifier).eraseSecureStore(),
      throwsA(isA<SecureKeysNotRemovedException>()),
    );
  });

  test('the failure report never contains a key value', () async {
    final exception = SecureKeysNotRemovedException(
      apiKeyMapping.values.toList(),
    );
    expect(exception.toString(), isNot(contains(_secret)));
    expect(exception.toString(), contains('wp_openai_api_key'));
  });
}
