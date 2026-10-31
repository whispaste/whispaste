/// Preferences cleanup for the factory reset (XP-6-12).
///
/// The reset brings the app back to a first start, so the counters and
/// remembered choices in SharedPreferences (review and support prompts,
/// recent searches, hints already seen, the last page) go with it. A few
/// keys describe the machine, not the user, and must survive: clearing them
/// would re-run one-time migrations on the next start (the bundle-ID
/// migration would copy the old install's data back in), send a second alive
/// ping on the same day, or treat a verified supporter as unpaid.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Keys the factory reset leaves in place. Everything else is removed.
const Set<String> kPreferencesKeptOnReset = {
  // One-time migrations and sweeps that must not run again.
  'bundle_id_migration_done',
  'legacy_residue_cleanup_version',
  'legacy_temp_wav_sweep_done',
  'history.vacuum_after_v27_done',
  'history.vacuum_after_v27_failed_attempts',
  // Telemetry dedupe: at most one alive ping per day and device.
  'telemetry_alive_ping_last_date',
  // A purchase the store confirmed stays a purchase.
  'support_store_verified_purchase',
  'support_verified_supporter',
};

/// Removes every app preference except [kPreferencesKeptOnReset].
Future<void> clearPreferencesForReset(SharedPreferences prefs) async {
  for (final key in prefs.getKeys().toList()) {
    if (kPreferencesKeptOnReset.contains(key)) continue;
    await prefs.remove(key);
  }
}
