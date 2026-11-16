// XP-6-14 / XP-6-13: whether the main hotkey still needs the desktop's own
// shortcut to work system-wide, and how the forced native-Wayland backend is
// recognised for the log.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/linux_desktop_shortcut.dart';

void main() {
  Future<bool> pending(
    DesktopShortcutFallback fallback, {
    bool installed = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        desktopShortcutFallbackProvider.overrideWith((ref) async => fallback),
        gnomeToggleShortcutInstalledProvider.overrideWith(
          (ref) async => installed,
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(desktopShortcutFallbackProvider.future);
    await container.read(gnomeToggleShortcutInstalledProvider.future);
    return container.read(desktopShortcutPendingProvider);
  }

  test('nothing is pending where the hotkey works on its own', () async {
    expect(await pending(DesktopShortcutFallback.notNeeded), isFalse);
  });

  test('GNOME is pending until WhisPaste added its entry', () async {
    expect(await pending(DesktopShortcutFallback.gnome), isTrue);
    expect(
      await pending(DesktopShortcutFallback.gnome, installed: true),
      isFalse,
    );
  });

  test('a manual binding cannot be seen, so it stays pending', () async {
    expect(await pending(DesktopShortcutFallback.manual), isTrue);
  });

  group('gdkBackendForcedWayland', () {
    test('GDK_BACKEND=wayland (also first in a list) is native Wayland', () {
      expect(gdkBackendForcedWayland({'GDK_BACKEND': 'wayland'}), isTrue);
      expect(gdkBackendForcedWayland({'GDK_BACKEND': 'wayland,x11'}), isTrue);
      expect(gdkBackendForcedWayland({'GDK_BACKEND': ' Wayland '}), isTrue);
    });

    test('the runner default x11, or nothing set, is not', () {
      expect(gdkBackendForcedWayland({'GDK_BACKEND': 'x11'}), isFalse);
      expect(gdkBackendForcedWayland({'GDK_BACKEND': 'x11,wayland'}), isFalse);
      expect(gdkBackendForcedWayland(const {}), isFalse);
    });
  });
}
