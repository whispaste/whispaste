import 'package:flutter/foundation.dart';

/// Display session of a Linux desktop, as far as the environment tells.
enum LinuxSessionType { x11, wayland, unknown }

/// What the desktop session can restrict for the floating button. Shown to the
/// user in Settings, never applied silently.
enum FloatingButtonLimit {
  /// Keep-above: the desktop may not keep the button over other windows.
  alwaysOnTop,

  /// Free positioning: the desktop decides where the button appears.
  freePositioning,
}

/// Whether the floating button can work on this desktop, and what it may not
/// be able to do there.
@immutable
class FloatingButtonSupport {
  const FloatingButtonSupport({
    required this.available,
    this.limits = const {},
  });

  /// Windows and macOS: no limits.
  static const full = FloatingButtonSupport(available: true);

  /// The native host cannot run on this backend. The switch stays disabled.
  static const unavailable = FloatingButtonSupport(available: false);

  /// False when the native host cannot run here at all.
  final bool available;

  /// Limits the session imposes while [available] is true.
  final Set<FloatingButtonLimit> limits;
}

/// Reads the session type from the environment, the same way the Linux
/// keyboard monitor does: XDG_SESSION_TYPE first, WAYLAND_DISPLAY as fallback.
LinuxSessionType linuxSessionTypeFrom(Map<String, String> environment) {
  final type = environment['XDG_SESSION_TYPE']?.toLowerCase();
  if (type == 'wayland') return LinuxSessionType.wayland;
  if (type == 'x11') return LinuxSessionType.x11;
  final waylandDisplay = environment['WAYLAND_DISPLAY'];
  if (waylandDisplay != null && waylandDisplay.isNotEmpty) {
    return LinuxSessionType.wayland;
  }
  return LinuxSessionType.unknown;
}

/// Maps the native probe result and the session type to the support state.
///
/// The host runs on X11 or XWayland (main.cc forces the X11 GDK backend). On
/// a Wayland session the compositor decides position and stacking, so both are
/// listed as limits. Focus-free clicks are not listed: the window never takes
/// input focus on either session.
FloatingButtonSupport linuxFloatingButtonSupport({
  required bool x11Backend,
  required LinuxSessionType session,
}) {
  if (!x11Backend) return FloatingButtonSupport.unavailable;
  if (session != LinuxSessionType.wayland) return FloatingButtonSupport.full;
  return const FloatingButtonSupport(
    available: true,
    limits: {
      FloatingButtonLimit.alwaysOnTop,
      FloatingButtonLimit.freePositioning,
    },
  );
}
