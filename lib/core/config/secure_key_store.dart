/// Secure storage wrapper for API keys.
///
/// Uses platform-native credential stores (Windows Credential Manager,
/// macOS Keychain, Linux libsecret) via [FlutterSecureStorage].
/// All keys are namespaced with a `wp_` prefix.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'linux_keyring_lock_probe.dart';

/// Maps AppSettings field names to their secure-storage key names.
const apiKeyMapping = <String, String>{
  'openAiApiKey': 'wp_openai_api_key',
  'deepgramApiKey': 'wp_deepgram_api_key',
};

/// Default storage backend.
///
/// macOS: the plugin default (`usesDataProtectionKeychain: true`) requires a
/// `keychain-access-groups` entitlement that the non-sandboxed WhisPaste
/// Runner does not have — every write fails with errSecMissingEntitlement
/// (-34018) and reads return null, so API keys silently never persist.
/// The file-based login keychain works without entitlements.
@visibleForTesting
const defaultSecureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);

class SecureKeyStore {
  SecureKeyStore([
    FlutterSecureStorage? storage,
    Future<bool> Function()? isKeyringLocked,
  ]) : _storage = storage ?? defaultSecureStorage,
       _isKeyringLocked = isKeyringLocked ?? isLinuxKeyringLocked;

  final FlutterSecureStorage _storage;
  final Future<bool> Function() _isKeyringLocked;

  /// Never hand a locked keyring to the plugin: on Linux it would unlock it
  /// synchronously on the GTK main thread and, without a working prompter,
  /// freeze the app before its window appears (GitHub #151). Callers already
  /// treat `KeyringLocked` as "keys unavailable for now".
  Future<void> _ensureKeyringUnlocked() async {
    if (await _isKeyringLocked()) {
      throw PlatformException(
        code: 'KeyringLocked',
        message: 'Default keyring is locked; not prompting from the UI thread',
      );
    }
  }

  Future<String?> readKey(String key) async {
    await _ensureKeyringUnlocked();
    return _storage.read(key: key);
  }

  Future<void> writeKey(String key, String value) async {
    await _ensureKeyringUnlocked();
    await _storage.write(key: key, value: value);
  }

  Future<void> deleteKey(String key) async {
    await _ensureKeyringUnlocked();
    await _storage.delete(key: key);
  }

  /// Reads all API keys and returns a map of secure-storage key → value.
  Future<Map<String, String>> readAllApiKeys() async {
    await _ensureKeyringUnlocked();
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
