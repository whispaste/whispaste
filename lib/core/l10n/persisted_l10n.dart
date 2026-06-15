import 'package:flutter/widgets.dart';

import '../data/database.dart';
import '../logging/app_logger.dart';
import 'generated/app_localizations.dart';

final _log = AppLogger('PersistedL10n');

/// Resolves [L10n] from the persisted locale without a [Localizations]
/// ancestor.
///
/// The floating render engines run in their own Flutter engines with no
/// `MaterialApp`/`Localizations` above them, so `L10n.of(context)` is
/// unavailable. They read the same `locale` key the main engine persists in
/// the `app_settings` KV table and look the strings up directly.
///
/// Falls back to English when nothing is persisted, the stored code is not a
/// supported locale, or the settings read fails.
Future<L10n> resolvePersistedL10n() async {
  const fallback = 'en';
  const supported = {'de', 'en', 'he'};
  var code = fallback;
  final db = HistoryDatabase();
  try {
    final values = await db.readAppSettings();
    final stored = values['locale'];
    if (stored != null && supported.contains(stored)) code = stored;
  } catch (e) {
    _log.debug('Failed to read persisted locale (falling back to en): $e');
  } finally {
    await db.close();
  }
  return lookupL10n(Locale(code));
}
