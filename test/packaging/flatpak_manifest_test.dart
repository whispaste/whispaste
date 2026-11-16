@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Flatpak sandbox surface (F-18 / R-03).
///
/// `--socket=session-bus` hands the app the whole session bus, which is
/// effectively a sandbox escape. The app only needs named access: the
/// StatusNotifier watcher (tray), Notifications (libnotify) and the Secret
/// Service (flutter_secure_storage). Portals (GlobalShortcuts, OpenURI,
/// FileChooser, Secret portal) are reachable without any permission.
void main() {
  final manifest = File('packaging/flatpak/de.whispaste.app.yml');
  final finishArgs = _finishArgs(manifest.readAsLinesSync());

  test('manifest does not grant the whole session bus', () {
    expect(
      finishArgs,
      isNot(contains('--socket=session-bus')),
      reason:
          'Use named --talk-name= grants instead of the full session bus '
          '(F-18 / R-03).',
    );
  });

  test('manifest grants the named session-bus services the app uses', () {
    for (final name in const [
      'org.kde.StatusNotifierWatcher', // tray (libayatana-appindicator)
      'org.freedesktop.Notifications', // libnotify (local_notifier)
      'org.freedesktop.secrets', // libsecret (flutter_secure_storage)
    ]) {
      expect(
        finishArgs,
        contains('--talk-name=$name'),
        reason: 'missing --talk-name=$name in finish-args',
      );
    }
  });
}

/// Returns the active (non-comment) `- --arg` entries of `finish-args`.
List<String> _finishArgs(List<String> lines) {
  final args = <String>[];
  var inFinishArgs = false;
  for (final raw in lines) {
    if (raw.startsWith('finish-args:')) {
      inFinishArgs = true;
      continue;
    }
    if (inFinishArgs && raw.isNotEmpty && !raw.startsWith(' ')) {
      break; // next top-level key
    }
    if (!inFinishArgs) continue;
    final line = raw.trim();
    if (line.startsWith('- --')) {
      args.add(line.substring(2).trim());
    }
  }
  return args;
}
