/// XP-6-12: the factory reset also empties the app's own preferences, except
/// one-time machine markers and a verified support purchase.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/factory_reset/reset_preferences.dart';

void main() {
  test(
    'user state goes, machine markers and a verified purchase stay',
    () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_unpasted_dictations': 3,
        'review_prompt_shown_count': 1,
        'support_prompt_impression_count': 2,
        'recent_searches': <String>['kaffee'],
        'last_page': 'settings',
        'update_channel': 'beta',
        'discoverability_hint_seen_smart_mode': true,
        'bundle_id_migration_done': true,
        'legacy_residue_cleanup_version': '1.4.2',
        'support_store_verified_purchase': true,
        'support_verified_supporter': true,
        'telemetry_alive_ping_last_date': '2026-10-19',
      });
      final prefs = await SharedPreferences.getInstance();

      await clearPreferencesForReset(prefs);

      expect(prefs.getKeys(), {
        'bundle_id_migration_done',
        'legacy_residue_cleanup_version',
        'support_store_verified_purchase',
        'support_verified_supporter',
        'telemetry_alive_ping_last_date',
      });
    },
  );

  test('an empty store stays empty', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await clearPreferencesForReset(prefs);

    expect(prefs.getKeys(), isEmpty);
  });
}
