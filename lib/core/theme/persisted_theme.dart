import 'dart:ui' show Brightness, PlatformDispatcher;

import '../data/database.dart';
import '../logging/app_logger.dart';

final _log = AppLogger('PersistedTheme');

/// Resolves whether the persisted theme preference is dark without a
/// [Theme]/Riverpod ancestor — the theme counterpart to
/// `resolvePersistedL10n()` for secondary render engines.
///
/// Reads the same `theme_mode` key the main engine persists in the
/// `app_settings` KV table (`'dark' | 'light' | 'system'`). `'system'`
/// resolves against the current platform brightness. Falls back to dark
/// (the app default, see `GeneralSettings.themeMode`) when nothing is
/// persisted or the read fails.
Future<bool> resolvePersistedIsDark() async {
  var stored = 'dark';
  final db = HistoryDatabase();
  try {
    final values = await db.readAppSettings();
    stored = values['theme_mode'] ?? stored;
  } catch (e) {
    _log.debug(
      'Failed to read persisted theme mode (falling back to dark): $e',
    );
  } finally {
    await db.close();
  }
  return switch (stored) {
    'light' => false,
    'system' =>
      PlatformDispatcher.instance.platformBrightness == Brightness.dark,
    _ => true,
  };
}
