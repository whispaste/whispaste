/// Platform adapters that back [KeyValueStore] with real storage.
///
/// These adapters are wired in `main.dart` and are NOT used in tests —
/// tests inject [FakeKeyValueStore] instances instead.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bundle_id_migration_service.dart';

// ---------------------------------------------------------------------------
// Secure-storage adapter
// ---------------------------------------------------------------------------

/// [KeyValueStore] backed by [FlutterSecureStorage].
///
/// Pass a pre-configured [FlutterSecureStorage] instance so that macOS
/// Keychain access group or iOS accessibility options can be set at the
/// call site.
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

/// [KeyValueStore] backed by [SharedPreferences].
///
/// All values are stored as strings via [prefs.getString] /
/// [prefs.setString].  Numeric and boolean preference values that were
/// originally stored as int/bool by the app (e.g. timestamps) have been
/// cast to String by the old caller and are read back as String here.
///
/// Because [SharedPreferences] does not expose a scoped (per-bundle-ID)
/// instance on desktop, this adapter reads the *current* app's preference
/// domain.  The old-identity adapter is therefore only useful before the
/// first `SharedPreferences.getInstance()` call flushes the new domain.
///
/// On macOS, `shared_preferences_macos` reads `NSUserDefaults`, which uses
/// the running app's bundle ID as the suite name.  After the bundle-ID
/// migration, the old plist file remains on disk at
/// `~/Library/Preferences/<old-bundle-id>.plist` but is not read by the
/// new binary.  The old adapter reads it by launching NSUserDefaults with
/// the old suite name — however, `shared_preferences` does not expose this
/// API publicly.
///
/// **Practical consequence**: the preferences migration relies on the
/// platform channel's default behaviour.  If `SharedPreferences` on the
/// target platform isolates stores by bundle ID and does not expose a
/// "read from a different bundle ID" API, the old-identity adapter will
/// simply return empty values (all `null`), making the preferences
/// migration a silent no-op.  API keys (via [SecureStorageAdapter]) are
/// still migrated correctly because `flutter_secure_storage` exposes
/// explicit account-scoped reads.
///
/// The pure [runBundleIdMigration] function is correct regardless — it
/// handles absent old data gracefully.
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
