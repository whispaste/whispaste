/// One-time clean-up of the removed beta update channel.
///
/// Older versions let users pick a `beta` release feed and stored the choice
/// under [legacyUpdateChannelKey]. The beta channel no longer exists, so every
/// installation follows the stable feed. Dropping the stored value is the whole
/// migration: nothing else is read from it, no other data is touched, and the
/// next stable update the user receives is delivered through the stable feed.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/app_logger.dart';

final _log = AppLogger('LegacyUpdateChannel');

/// SharedPreferences key under which the removed channel choice was stored.
const legacyUpdateChannelKey = 'update_channel';

/// Removes a stored update-channel value (`beta` or `stable`) if present.
/// Never throws: a broken preferences store must not block app startup.
Future<void> migrateLegacyUpdateChannel([SharedPreferences? prefs]) async {
  try {
    final store = prefs ?? await SharedPreferences.getInstance();
    if (!store.containsKey(legacyUpdateChannelKey)) return;
    await store.remove(legacyUpdateChannelKey);
    _log.info('Removed stored update channel (beta channel no longer exists)');
  } catch (e) {
    _log.debug('Legacy update channel clean-up failed: $e');
  }
}
