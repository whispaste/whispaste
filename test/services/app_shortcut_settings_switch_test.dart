/// The switch behind the hotkey recorder's "Change in system settings"
/// button under Wayland (#171): GNOME with a known desktop ID gets the
/// action, which opens WhisPaste's page in GNOME Settings; every other
/// desktop, Flatpak, a missing desktop ID or a non-Linux host keeps the plain
/// hint (null action). Tested through the providers the recorder reads, with
/// the session and the opener injected.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/linux_desktop_shortcut.dart';

const _gnomeWayland = {
  'XDG_SESSION_TYPE': 'wayland',
  'WAYLAND_DISPLAY': 'wayland-0',
  // What Ubuntu 26.04 reports (lab guest ubu).
  'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME',
};

void main() {
  late List<String> opened;

  ProviderContainer containerFor({
    required Map<String, String> env,
    String? appId = 'de.whispaste.app',
    bool host = true,
  }) {
    final container = ProviderContainer(
      overrides: [
        linuxDesktopShortcutHostProvider.overrideWithValue(host),
        linuxFocusEnvProvider.overrideWithValue(env),
        appShortcutSettingsOpenerProvider.overrideWithValue((id) async {
          opened.add(id);
          return true;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.read(waylandSettingsAppIdProvider.notifier).set(appId);
    return container;
  }

  setUp(() => opened = []);

  test('GNOME Wayland: the action opens the page of the reported ID', () {
    final container = containerFor(env: _gnomeWayland);
    final action = container.read(appShortcutSettingsActionProvider);
    expect(action, isNotNull);
    action!();
    expect(opened, ['de.whispaste.app']);
  });

  test('plain GNOME in XDG_CURRENT_DESKTOP (Fedora) counts as GNOME', () {
    final container = containerFor(
      env: {..._gnomeWayland, 'XDG_CURRENT_DESKTOP': 'GNOME'},
    );
    expect(container.read(appShortcutSettingsActionProvider), isNotNull);
  });

  test('KDE and wlroots desktops keep the hint', () {
    for (final env in [
      {..._gnomeWayland, 'XDG_CURRENT_DESKTOP': 'KDE'},
      {..._gnomeWayland, 'SWAYSOCK': '/run/user/1000/sway.sock'},
      {..._gnomeWayland, 'XDG_CURRENT_DESKTOP': 'Hyprland'},
    ]) {
      final container = containerFor(env: env);
      expect(
        container.read(appShortcutSettingsActionProvider),
        isNull,
        reason: '$env',
      );
    }
  });

  test('inside Flatpak the settings app is out of reach: no button', () {
    final container = containerFor(
      env: {..._gnomeWayland, 'FLATPAK_ID': 'de.whispaste.app'},
    );
    expect(container.read(appShortcutSettingsActionProvider), isNull);
  });

  test('no visible desktop entry (no ID from the runner): no button', () {
    final container = containerFor(env: _gnomeWayland, appId: null);
    expect(container.read(appShortcutSettingsActionProvider), isNull);
  });

  test('not a Linux desktop host: no button', () {
    final container = containerFor(env: _gnomeWayland, host: false);
    expect(container.read(appShortcutSettingsActionProvider), isNull);
  });

  test('GNOME under X11 has no portal binding: no button', () {
    final container = containerFor(
      env: {'XDG_SESSION_TYPE': 'x11', 'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME'},
    );
    expect(container.read(appShortcutSettingsActionProvider), isNull);
  });

  test('the keyboard settings desktop follows the same session', () {
    expect(
      containerFor(
        env: _gnomeWayland,
      ).read(keyboardShortcutSettingsDesktopProvider),
      LinuxFocusDesktop.gnome,
    );
    expect(
      containerFor(
        env: {..._gnomeWayland, 'FLATPAK_ID': 'de.whispaste.app'},
      ).read(keyboardShortcutSettingsDesktopProvider),
      isNull,
    );
  });
}
