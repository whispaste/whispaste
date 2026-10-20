/// Picks the focus source for the running Linux session (V1 Wayland) and
/// says how well the target app can be told apart there (status row).
library;

import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'compositor_ipc_sources.dart';
import 'dbus_focus_sources.dart';
import 'focused_target.dart';
import 'wlr_toplevel_source.dart';

/// The session's desktop as far as focus lookup is concerned.
enum LinuxFocusDesktop { x11, sway, hyprland, niri, kde, gnome, otherWayland }

/// Reads the session from the environment. Order matters: compositor
/// sockets beat `XDG_CURRENT_DESKTOP`, which nested or themed sessions often
/// misreport.
LinuxFocusDesktop detectLinuxFocusDesktop(Map<String, String> env) {
  final wayland =
      (env['WAYLAND_DISPLAY']?.isNotEmpty ?? false) ||
      env['XDG_SESSION_TYPE'] == 'wayland';
  if (!wayland) return LinuxFocusDesktop.x11;
  if (env['SWAYSOCK']?.isNotEmpty ?? false) return LinuxFocusDesktop.sway;
  if (env['HYPRLAND_INSTANCE_SIGNATURE']?.isNotEmpty ?? false) {
    return LinuxFocusDesktop.hyprland;
  }
  if (env['NIRI_SOCKET']?.isNotEmpty ?? false) return LinuxFocusDesktop.niri;
  final desktops = (env['XDG_CURRENT_DESKTOP'] ?? '').toLowerCase().split(':');
  if (desktops.contains('kde')) return LinuxFocusDesktop.kde;
  // Ubuntu reports `ubuntu:GNOME`, Fedora `GNOME`.
  if (desktops.contains('gnome')) return LinuxFocusDesktop.gnome;
  return LinuxFocusDesktop.otherWayland;
}

/// The Wayland focus source for [desktop], or null where the native X11
/// lookup is the only one (X11 sessions) or none exists.
///
/// Inside Flatpak the Sway, niri and Hyprland sockets are usually out of
/// reach; the Wayland socket is not, so the wlr toplevel protocol stands in.
FocusedTargetSource? waylandFocusSourceFor(
  LinuxFocusDesktop desktop,
  Map<String, String> env, {
  DBusClient Function()? sessionBus,
}) {
  DBusClient bus() => (sessionBus ?? DBusClient.session)();
  FocusedTargetSource? wlr() => switch (WlrToplevelFocusSource.socketFor(env)) {
    final path? => WlrToplevelFocusSource(path),
    null => null,
  };
  FocusedTargetSource? ipc(
    String? path,
    FocusedTargetSource Function(String) make,
  ) {
    if (path == null) return wlr();
    final sandboxed = env['FLATPAK_ID']?.isNotEmpty ?? false;
    return sandboxed && !_isSocket(path) ? wlr() : make(path);
  }

  return switch (desktop) {
    LinuxFocusDesktop.sway => ipc(env['SWAYSOCK'], SwayFocusSource.new),
    LinuxFocusDesktop.hyprland => ipc(
      HyprlandFocusSource.socketFor(env),
      HyprlandFocusSource.new,
    ),
    LinuxFocusDesktop.niri => ipc(env['NIRI_SOCKET'], NiriFocusSource.new),
    LinuxFocusDesktop.kde => KWinFocusSource(
      bus(),
      scriptDirectory: kwinScriptDirectory(env),
    ),
    LinuxFocusDesktop.gnome => GnomeShellFocusSource(bus()),
    LinuxFocusDesktop.otherWayland => wlr(),
    LinuxFocusDesktop.x11 => null,
  };
}

bool _isSocket(String? path) =>
    path != null &&
    FileSystemEntity.typeSync(path) == FileSystemEntityType.unixDomainSock;

/// Where the KWin script goes: KWin reads it from the host, and a Flatpak's
/// /tmp is private, so inside Flatpak it goes to the app's runtime folder,
/// which the host sees at the same path. Null means the system temp folder.
Directory? kwinScriptDirectory(Map<String, String> env) {
  final app = env['FLATPAK_ID'];
  final runtime = env['XDG_RUNTIME_DIR'];
  if (app == null || app.isEmpty || runtime == null) return null;
  return Directory('$runtime/app/$app');
}

/// What the settings say about target detection on Linux (V1 Wayland).
enum LinuxFocusStatus {
  /// The target app is known: X11, or a Wayland compositor that answers.
  available,

  /// GNOME under Wayland without the WhisPaste extension: only XWayland
  /// windows are known.
  gnomeExtensionMissing,

  /// A Wayland session without a reachable focus source (a compositor
  /// WhisPaste cannot ask yet, or a Flatpak that cannot see its socket).
  unsupported,
}

/// Checks once whether this session can name the focused window. Reaching
/// the source is enough; nothing is asked about any window.
Future<LinuxFocusStatus> probeLinuxFocusStatus(
  Map<String, String> env, {
  DBusClient Function()? sessionBus,
}) async {
  final desktop = detectLinuxFocusDesktop(env);
  final reachable = switch (desktop) {
    LinuxFocusDesktop.x11 => true,
    LinuxFocusDesktop.kde || LinuxFocusDesktop.gnome => await _hasOwner(
      (sessionBus ?? DBusClient.session)(),
      desktop == LinuxFocusDesktop.kde
          ? 'org.kde.KWin'
          : GnomeShellFocusSource.busName,
    ),
    // Socket sources open no bus, so asking the chooser is cheap here.
    _ => switch (waylandFocusSourceFor(desktop, env)) {
      final WlrToplevelFocusSource wlr => await wlr.isAvailable(),
      final SwayFocusSource s => _isSocket(s.socketPath),
      final NiriFocusSource s => _isSocket(s.socketPath),
      final HyprlandFocusSource s => _isSocket(s.socketPath),
      _ => false,
    },
  };
  if (reachable) return LinuxFocusStatus.available;
  return desktop == LinuxFocusDesktop.gnome
      ? LinuxFocusStatus.gnomeExtensionMissing
      : LinuxFocusStatus.unsupported;
}

Future<bool> _hasOwner(DBusClient bus, String name) async {
  try {
    return await bus.nameHasOwner(name).timeout(focusedTargetDbusTimeout);
  } on Object {
    // No session bus or no answer: the source counts as unreachable.
    return false;
  } finally {
    await bus.close();
  }
}

/// The Linux target-detection status for the settings. Re-read on demand
/// (`ref.invalidate`), e.g. after the GNOME extension was switched on.
final linuxFocusStatusProvider = FutureProvider<LinuxFocusStatus>(
  (ref) => probeLinuxFocusStatus(Platform.environment),
);
