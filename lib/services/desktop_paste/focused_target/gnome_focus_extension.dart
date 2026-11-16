/// The optional WhisPaste GNOME Shell extension (V1 Wayland): whether its
/// files are on this system and turning it on or off for the user. The app
/// does this only from a button the user presses (consent).
library;

import 'dart:io';

import '../../../core/logging/app_logger.dart';

final _log = AppLogger('GnomeFocusExtension');

/// UUID of packaging/linux/gnome-shell-extension/whispaste-focus@whispaste.de.
const gnomeFocusExtensionUuid = 'whispaste-focus@whispaste.de';

/// The terminal command that turns the extension on.
const gnomeFocusExtensionEnableCommand =
    'gnome-extensions enable $gnomeFocusExtensionUuid';

/// Whether the extension is installed where GNOME Shell looks: per user, or
/// system-wide by the .deb. A Flatpak sees neither host directory, so it
/// reports false and the UI points to the manual instead.
bool gnomeFocusExtensionInstalled(
  Map<String, String> env, {
  bool Function(String path)? exists,
}) {
  final has = exists ?? (path) => File('$path/metadata.json').existsSync();
  if (env.containsKey('FLATPAK_ID')) return false;
  final home = env['HOME'];
  final dataHome =
      env['XDG_DATA_HOME'] ?? (home == null ? null : '$home/.local/share');
  final dirs = [
    if (dataHome != null) '$dataHome/gnome-shell/extensions',
    for (final d
        in (env['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share').split(':'))
      if (d.isNotEmpty) '$d/gnome-shell/extensions',
  ];
  return dirs.any((d) => has('$d/$gnomeFocusExtensionUuid'));
}

/// Runs a command; replaceable in tests.
typedef GnomeExtensionsRunner =
    Future<ProcessResult> Function(String executable, List<String> args);

/// Turns the extension on or off with `gnome-extensions`. False when the
/// tool is missing or refuses (the UI then shows the command to run).
Future<bool> setGnomeFocusExtensionEnabled(
  bool enabled, {
  GnomeExtensionsRunner? run,
}) async {
  final runner = run ?? Process.run;
  try {
    final result = await runner('gnome-extensions', [
      enabled ? 'enable' : 'disable',
      gnomeFocusExtensionUuid,
    ]);
    return result.exitCode == 0;
  } on Object catch (e) {
    // No gnome-extensions on PATH (not GNOME, or inside a sandbox).
    _log.debug('gnome-extensions not run', e);
    return false;
  }
}
