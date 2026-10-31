/// Unit tests for [AutomationApiTokenStore] against a fake [SecureKeyStore]
/// (same fake pattern as `test/services/transcription/openai_transcriber_test.dart`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/services/automation_api/automation_api_token_store.dart';

class _FakeSecureKeyStore implements SecureKeyStore {
  final Map<String, String> store = {};

  @override
  Future<String?> readKey(String key) async => store[key];

  @override
  Future<void> writeKey(String key, String value) async => store[key] = value;

  @override
  Future<void> deleteKey(String key) async => store.remove(key);

  @override
  Future<Map<String, String>> readAllApiKeys() async => Map.of(store);
}

void main() {
  group('AutomationApiTokenStore', () {
    test(
      'readToken() is null before a token has ever been generated',
      () async {
        final fake = _FakeSecureKeyStore();
        final store = AutomationApiTokenStore(fake);

        expect(await store.readToken(), isNull);
      },
    );

    test('regenerate() persists a token under the dedicated secure-storage '
        'key and returns it', () async {
      final fake = _FakeSecureKeyStore();
      final store = AutomationApiTokenStore(fake);

      final token = await store.regenerate();

      expect(token, isNotEmpty);
      expect(fake.store[automationApiTokenKey], token);
      expect(await store.readToken(), token);
    });

    test('regenerate() overwrites the previous token — the old one no '
        'longer reads back', () async {
      final fake = _FakeSecureKeyStore();
      final store = AutomationApiTokenStore(fake);

      final first = await store.regenerate();
      final second = await store.regenerate();

      expect(first, isNot(second));
      expect(await store.readToken(), second);
    });

    test(
      'two generated tokens are not equal (randomness sanity check)',
      () async {
        final store = AutomationApiTokenStore(_FakeSecureKeyStore());
        final a = await store.regenerate();
        final b = await store.regenerate();
        expect(a, isNot(b));
      },
    );

    test(
      'revoke() deletes the token — readToken() returns null again',
      () async {
        final fake = _FakeSecureKeyStore();
        final store = AutomationApiTokenStore(fake);
        await store.regenerate();

        await store.revoke();

        expect(await store.readToken(), isNull);
        expect(fake.store.containsKey(automationApiTokenKey), isFalse);
      },
    );
  });
}
