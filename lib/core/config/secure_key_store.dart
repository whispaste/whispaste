/// Secure storage wrapper for API keys.
///
/// Uses platform-native credential stores (Windows Credential Manager,
/// macOS Keychain, Linux libsecret) via [FlutterSecureStorage].
/// All keys are namespaced with a `wp_` prefix.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Maps AppSettings field names to their secure-storage key names.
const apiKeyMapping = <String, String>{
  'openAiApiKey': 'wp_openai_api_key',
  'groqApiKey': 'wp_groq_api_key',
  'deepgramApiKey': 'wp_deepgram_api_key',
};

class SecureKeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> readKey(String key) => _storage.read(key: key);

  Future<void> writeKey(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<void> deleteKey(String key) => _storage.delete(key: key);

  /// Reads all API keys and returns a map of secure-storage key → value.
  Future<Map<String, String>> readAllApiKeys() async {
    final result = <String, String>{};
    for (final secureKey in apiKeyMapping.values) {
      final value = await _storage.read(key: secureKey);
      if (value != null && value.isNotEmpty) {
        result[secureKey] = value;
      }
    }
    return result;
  }
}

/// Riverpod provider for the secure key store.
final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => SecureKeyStore(),
);
