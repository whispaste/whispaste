/// Platform adapters that back [KeyValueStore] with real storage.
///
/// These adapters are wired in `main.dart` and are NOT used in tests —
/// tests inject [FakeKeyValueStore] instances instead.
library;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bundle_id_migration_service.dart';

/// Bundle ID the old (pre-migration) app identity shipped under.
const kOldBundleId = 'com.whispaste.whispaste';

/// `accountName`/`kSecAttrService` `flutter_secure_storage` defaults to on
/// Apple platforms when no custom `AppleOptions` are supplied — matches
/// `AppleOptions.defaultAccountName` and what `BundleIdMigrationHost.swift`
/// queries for.
const kSecureStorageDefaultService = 'flutter_secure_storage_service';

/// Method channel backing [OldKeychainAdapter] and [OldPreferencesAdapter] —
/// see `macos/Runner/BundleIdMigrationHost.swift`. Windows/Linux have no old
/// bundle-ID identity to migrate from (single, stable app ID), so this
/// channel is macOS-only; both adapters return `null` reads elsewhere.
const _channel = MethodChannel('com.whispaste.bundle_id_migration');

// ---------------------------------------------------------------------------
// Secure-storage adapter
// ---------------------------------------------------------------------------

/// [KeyValueStore] backed by [FlutterSecureStorage], for the *current*
/// (new) bundle identity. `flutter_secure_storage_darwin` only applies
/// `kSecAttrAccessGroup` on iOS — macOS Keychain items are scoped to the
/// running app's code-signing identity with no built-in cross-bundle-ID
/// access, which is why reading *old*-identity Keychain data needs
/// [OldKeychainAdapter] instead of a differently-configured instance of
/// this class.
class SecureStorageAdapter implements KeyValueStore {
  const SecureStorageAdapter(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}

// ---------------------------------------------------------------------------
// SharedPreferences adapter
// ---------------------------------------------------------------------------

/// [KeyValueStore] backed by [SharedPreferences], for the *current* (new)
/// bundle identity.
///
/// All values are stored as strings via [prefs.getString] /
/// [prefs.setString].  Numeric and boolean preference values that were
/// originally stored as int/bool by the app (e.g. timestamps) have been
/// cast to String by the old caller and are read back as String here.
///
/// [SharedPreferences] itself does not expose a scoped (per-bundle-ID)
/// instance — reading the *old* identity's `NSUserDefaults` domain
/// (`~/Library/Preferences/<old-bundle-id>.plist` on macOS) needs
/// [OldPreferencesAdapter] instead of a differently-configured instance of
/// this class.
class SharedPreferencesAdapter implements KeyValueStore {
  SharedPreferencesAdapter(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<Map<String, String>> readAll() async {
    final result = <String, String>{};
    for (final key in _prefs.getKeys()) {
      final raw = _prefs.get(key);
      if (raw != null) {
        result[key] = raw.toString();
      }
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// Old-identity adapters (macOS native bridge)
// ---------------------------------------------------------------------------

/// Read-only [KeyValueStore] over the *old* bundle identity's `NSUserDefaults`
/// domain, via `BundleIdMigrationHost.swift`. Non-sandboxed macOS apps can
/// read any preference domain by suite name — no cross-app entitlement is
/// required. Returns `null` on any other platform (no channel handler
/// registered there) or if the platform channel call fails for any reason —
/// both cases are treated by [runBundleIdMigration] as "no old data".
class OldPreferencesAdapter implements KeyValueStore {
  const OldPreferencesAdapter();

  @override
  Future<String?> read(String key) async {
    try {
      return await _channel.invokeMethod<String>('readOldPreference', {
        'oldBundleId': kOldBundleId,
        'key': key,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      throw UnsupportedError('OldPreferencesAdapter is read-only');

  @override
  Future<Map<String, String>> readAll() =>
      throw UnsupportedError('OldPreferencesAdapter is read-only');
}

/// Read-only [KeyValueStore] over Keychain items created under the *old*
/// app identity, via `BundleIdMigrationHost.swift`. Best-effort: macOS may
/// deny cross-code-signing-identity Keychain access, which surfaces here the
/// same way as "item absent" (`null`) — [runBundleIdMigration] already
/// handles that case as a no-op, so this can only recover data, never
/// regress behaviour.
class OldKeychainAdapter implements KeyValueStore {
  const OldKeychainAdapter();

  @override
  Future<String?> read(String key) async {
    try {
      return await _channel.invokeMethod<String>('readOldKeychainValue', {
        'service': kSecureStorageDefaultService,
        'account': key,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      throw UnsupportedError('OldKeychainAdapter is read-only');

  @override
  Future<Map<String, String>> readAll() =>
      throw UnsupportedError('OldKeychainAdapter is read-only');
}
