/// Type-tolerant SharedPreferences readers for keys that may have passed
/// through [runBundleIdMigration] (`bundle_id_migration_service.dart`).
///
/// That migration's [SharedPreferencesAdapter] persists every value as a
/// String regardless of the original type (see its own doc comment) — so an
/// int/bool preference that existed under the old bundle ID (`com.whispaste.
/// whispaste`) comes back as a String under the new one. `SharedPreferences
/// .getInt`/`.getBool` do an unchecked cast and throw `TypeError` on that
/// mismatch (confirmed in production: Sentry FLUTTER_WHISPASTE-BP/-BQ, a
/// fatal crash loop in `review_prompt_service.dart`/`support_prompt_service
/// .dart` for exactly this reason). Use these instead of the raw getters for
/// any key listed in `bundle_id_migration_service.dart`'s
/// `kPreferenceKeyNames`.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Reads [key] as an int, tolerating a migrated String-typed value.
int? readIntPrefSafe(SharedPreferences prefs, String key) {
  final raw = prefs.get(key);
  if (raw is int) return raw;
  if (raw is String) return int.tryParse(raw);
  return null;
}

/// Reads [key] as a bool, tolerating a migrated String-typed value.
bool? readBoolPrefSafe(SharedPreferences prefs, String key) {
  final raw = prefs.get(key);
  if (raw is bool) return raw;
  if (raw is String) {
    return raw == 'true' ? true : (raw == 'false' ? false : null);
  }
  return null;
}
