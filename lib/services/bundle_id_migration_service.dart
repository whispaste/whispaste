/// Bundle-ID data migration service.
///
/// One-time, idempotent migration that carries user data from the old bundle
/// identity (`com.whispaste.whispaste`) to the new one (`de.whispaste.app`).
///
/// ## Why this is needed
///
/// On macOS, `flutter_secure_storage` stores Keychain entries scoped to the
/// app's bundle identifier. `SharedPreferences` uses `NSUserDefaults`, which
/// on macOS resolves to a `.plist` named after the bundle ID in
/// `~/Library/Preferences/`. When the bundle ID changes both stores become
/// unreachable under the new identity — existing users would lose their API
/// keys and preferences silently.
///
/// The history database is **not** affected because its path is hardcoded to
/// `~/Library/Application Support/WhisPaste/history.db` (independent of the
/// bundle ID).
///
/// ## Architecture
///
/// The migration logic is a **pure function** ([runBundleIdMigration]) that
/// operates exclusively on injected [KeyValueStore] abstractions. No real
/// Keychain or `NSUserDefaults` is touched during tests. Platform adapters
/// wired in `main.dart` provide the concrete old/new stores.
///
/// ## Run semantics
///
/// - Runs **once** — a persistent marker in the new store guards re-entry.
/// - **No-Op** when no old data is present.
/// - Does **not overwrite** existing new data (new store wins).
/// - Covers: API keys (secure storage), preferences (SharedPreferences),
///   history (explicit no-op — path is bundle-ID-independent).
library;

import 'dart:developer' as dev;

/// A simple key-value store abstraction used by the migration.
///
/// Concrete implementations wrap [FlutterSecureStorage] for API keys and
/// [SharedPreferences] for preferences. In tests, in-memory fakes are used.
abstract interface class KeyValueStore {
  /// Returns the value for [key], or `null` if absent.
  Future<String?> read(String key);

  /// Writes [value] for [key].
  Future<void> write(String key, String value);

  /// Returns all key-value pairs in the store.
  Future<Map<String, String>> readAll();
}

/// Marker key written to [newPrefs] after a successful migration run.
///
/// The value `'1'` signals "done"; absence means "not yet run".
const kBundleIdMigrationDoneKey = 'bundle_id_migration_done';

/// All API-key names that live in the secure store under the old identity.
///
/// Keys match [apiKeyMapping] in `secure_key_store.dart`.
const kApiKeyNames = ['wp_openai_api_key', 'wp_deepgram_api_key'];

/// All preference key names carried over from the old identity.
const kPreferenceKeyNames = [
  'recent_searches',
  'review_prompt_last_shown',
  'review_prompt_permanently_dismissed',
  'review_prompt_shown_count',
  'feedback_last_submitted_ms',
];

/// Result of a migration run — for logging and testing.
class BundleIdMigrationResult {
  const BundleIdMigrationResult({
    required this.ranMigration,
    required this.copiedApiKeys,
    required this.copiedPreferences,
    this.error,
  });

  /// Whether the migration body actually ran (false when marker was already set).
  final bool ranMigration;

  /// Names of API keys successfully copied (empty when no old data or already present).
  final List<String> copiedApiKeys;

  /// Names of preference keys successfully copied.
  final List<String> copiedPreferences;

  /// Non-null when an unexpected error occurred (migration still marks done).
  final Object? error;

  @override
  String toString() =>
      'BundleIdMigrationResult('
      'ranMigration=$ranMigration, '
      'copiedApiKeys=$copiedApiKeys, '
      'copiedPreferences=$copiedPreferences'
      '${error != null ? ", error=$error" : ""}'
      ')';
}

/// Pure migration function — carries old-identity data to the new identity.
///
/// Parameters:
/// - [oldSecureStore]: reads from the old bundle-ID Keychain scope.
/// - [newSecureStore]: writes to the new bundle-ID Keychain scope.
/// - [oldPrefs]: reads from the old bundle-ID `NSUserDefaults` scope.
/// - [newPrefs]: reads and writes the new bundle-ID `NSUserDefaults` scope;
///   also stores the migration-done marker.
///
/// Contract:
/// - Idempotent: if [kBundleIdMigrationDoneKey] is already set in [newPrefs],
///   returns immediately without touching any store.
/// - No-overwrite: for each key, a value present in the new store is preserved
///   even if the old store also has a value for that key.
/// - Always sets the marker in [newPrefs] before returning (even on partial
///   failure) so a broken old store does not cause infinite retry loops.
Future<BundleIdMigrationResult> runBundleIdMigration({
  required KeyValueStore oldSecureStore,
  required KeyValueStore newSecureStore,
  required KeyValueStore oldPrefs,
  required KeyValueStore newPrefs,
}) async {
  // --- Guard: already ran ---
  final marker = await newPrefs.read(kBundleIdMigrationDoneKey);
  if (marker == '1') {
    return const BundleIdMigrationResult(
      ranMigration: false,
      copiedApiKeys: [],
      copiedPreferences: [],
    );
  }

  final copiedApiKeys = <String>[];
  final copiedPreferences = <String>[];
  Object? capturedError;

  try {
    // --- Migrate API keys (secure storage) ---
    for (final key in kApiKeyNames) {
      try {
        final oldValue = await oldSecureStore.read(key);
        if (oldValue == null || oldValue.isEmpty) continue;

        final newValue = await newSecureStore.read(key);
        if (newValue != null && newValue.isNotEmpty) {
          // New store already has a value — preserve it, skip copy.
          dev.log(
            'BundleIdMigration: skipping api key "$key" (new store already set)',
            name: 'BundleIdMigration',
          );
          continue;
        }

        await newSecureStore.write(key, oldValue);
        copiedApiKeys.add(key);
        dev.log(
          'BundleIdMigration: copied api key "$key"',
          name: 'BundleIdMigration',
        );
      } catch (e) {
        dev.log(
          'BundleIdMigration: error copying api key "$key": $e',
          name: 'BundleIdMigration',
        );
        capturedError = e;
      }
    }

    // --- Migrate preferences ---
    for (final key in kPreferenceKeyNames) {
      try {
        final oldValue = await oldPrefs.read(key);
        if (oldValue == null || oldValue.isEmpty) continue;

        final newValue = await newPrefs.read(key);
        if (newValue != null && newValue.isNotEmpty) {
          dev.log(
            'BundleIdMigration: skipping pref "$key" (new store already set)',
            name: 'BundleIdMigration',
          );
          continue;
        }

        await newPrefs.write(key, oldValue);
        copiedPreferences.add(key);
        dev.log(
          'BundleIdMigration: copied pref "$key"',
          name: 'BundleIdMigration',
        );
      } catch (e) {
        dev.log(
          'BundleIdMigration: error copying pref "$key": $e',
          name: 'BundleIdMigration',
        );
        capturedError = e;
      }
    }

    // History (Drift/SQLite) is stored at a hardcoded path that does not
    // include the bundle ID, so it requires no migration here.
  } finally {
    // Always set the marker so a broken old store doesn't cause infinite loops.
    try {
      await newPrefs.write(kBundleIdMigrationDoneKey, '1');
    } catch (e) {
      dev.log(
        'BundleIdMigration: could not write marker: $e',
        name: 'BundleIdMigration',
      );
    }
  }

  dev.log(
    'BundleIdMigration complete: '
    'apiKeys=$copiedApiKeys, prefs=$copiedPreferences',
    name: 'BundleIdMigration',
  );

  return BundleIdMigrationResult(
    ranMigration: true,
    copiedApiKeys: List.unmodifiable(copiedApiKeys),
    copiedPreferences: List.unmodifiable(copiedPreferences),
    error: capturedError,
  );
}
