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

export 'linux_keyring_lock_probe.dart' show KeyringAvailability;

/// Maps AppSettings field names to their secure-storage key names.
const apiKeyMapping = <String, String>{
  'openAiApiKey': 'wp_openai_api_key',
  'deepgramApiKey': 'wp_deepgram_api_key',
};

/// Restore token of the Linux RemoteDesktop portal (keyboard consent). A
/// secret, but no API key: never exported, erased with the API keys.
const linuxPortalRestoreTokenKey = 'wp_linux_portal_restore_token';

/// Every secure-storage key a reset erases.
final allSecureKeys = [...apiKeyMapping.values, linuxPortalRestoreTokenKey];

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

/// Thrown when one or more API keys could not be removed from secure storage.
/// [keys] holds the storage names only, never the values.
class SecureKeysNotRemovedException implements Exception {
  const SecureKeysNotRemovedException(this.keys);

  final List<String> keys;

  @override
  String toString() => 'SecureKeysNotRemovedException(${keys.join(', ')})';
}

class SecureKeyStore {
  SecureKeyStore([
    FlutterSecureStorage? storage,
    Future<KeyringAvailability> Function()? probeKeyring,
    DateTime Function()? clock,
  ]) : _storage = storage ?? defaultSecureStorage,
       _probeKeyring = probeKeyring ?? probeLinuxKeyring,
       _clock = clock ?? DateTime.now;

  final FlutterSecureStorage _storage;
  final Future<KeyringAvailability> Function() _probeKeyring;
  final DateTime Function() _clock;

  /// How long an unreachable Secret Service stays marked before it is probed
  /// again. A service that starts late (gnome-keyring after login) must not
  /// disable the keys for the whole session; within the window each call
  /// fails at once, so a factory reset does not wait once per key.
  static const unreachableRetryAfter = Duration(seconds: 30);

  /// When the Secret Service was last found unreachable, or null. A locked
  /// keyring is probed again on every call: that answer is instant, and the
  /// user may unlock it meanwhile.
  DateTime? _unreachableSince;

  /// Never hand a locked or unreachable keyring to the plugin: on Linux it
  /// would unlock it, or wait for the Secret Service, synchronously on the
  /// GTK main thread and freeze the app, before its window appears (GitHub
  /// #151) or during a recording (XP-7-01). Callers already treat
  /// `KeyringLocked` as "keys unavailable for now".
  Future<void> _ensureKeyringUnlocked() async {
    final since = _unreachableSince;
    if (since != null && _clock().difference(since) < unreachableRetryAfter) {
      throw _keyringUnavailable('unreachable');
    }
    switch (await _probeKeyring()) {
      case KeyringAvailability.usable:
        _unreachableSince = null;
        return;
      case KeyringAvailability.locked:
        _unreachableSince = null;
        throw _keyringUnavailable('locked');
      case KeyringAvailability.unreachable:
        _unreachableSince = _clock();
        throw _keyringUnavailable('unreachable');
    }
  }

  static PlatformException _keyringUnavailable(String state) =>
      PlatformException(
        code: 'KeyringLocked',
        message: 'Default keyring is $state; not calling it from the UI thread',
      );

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

/// Deletes every API key and the other secrets in [allSecureKeys], trying
/// all of them even after a failure. Returns the storage names that could
/// not be removed (never the values). A free function so the
/// [SecureKeyStore] interface stays unchanged for fakes.
Future<List<String>> deleteAllApiKeys(SecureKeyStore store) async {
  final failed = <String>[];
  for (final secureKey in allSecureKeys) {
    try {
      await store.deleteKey(secureKey);
    } catch (_) {
      failed.add(secureKey);
    }
  }
  return failed;
}

/// Riverpod provider for the secure key store.
final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => SecureKeyStore(),
);
