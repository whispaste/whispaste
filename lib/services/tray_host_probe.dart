/// Whether the desktop offers a tray host (a status-notifier watcher).
///
/// On Linux the tray icon is shown only where a watcher owns its name on the
/// session bus. KDE and most others provide one; GNOME needs the AppIndicator
/// extension. Without a host the tray quick switch is invisible, so the app
/// says so instead of failing silently.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks the session bus whether `org.kde.StatusNotifierWatcher` has an owner.
/// When the probe cannot run or answers unclearly, the host counts as present:
/// a missing `dbus-send` must never produce a false warning.
Future<bool> probeLinuxTrayHost({
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    final result = await Process.run('dbus-send', const [
      '--session',
      '--print-reply',
      '--dest=org.freedesktop.DBus',
      '/org/freedesktop/DBus',
      'org.freedesktop.DBus.NameHasOwner',
      'string:org.kde.StatusNotifierWatcher',
    ]).timeout(timeout);
    if (result.exitCode != 0) return true;
    return !(result.stdout as String).contains('boolean false');
  } on Object {
    return true;
  }
}

/// The probe in use. Tests replace it so they never reach the session bus.
final trayHostProbeProvider = Provider<Future<bool> Function()>(
  (ref) => probeLinuxTrayHost,
);

/// True when Linux runs without a tray host, so the tray is missing. The app
/// shell turns this into a notice, once per start.
final trayHostMissingProvider = NotifierProvider<TrayHostMissingNotifier, bool>(
  TrayHostMissingNotifier.new,
);

class TrayHostMissingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void update({required bool missing}) => state = missing;
}
