import 'dart:io';

import 'floating_overlay_controller_interface.dart';
import 'linux_floating_overlay_controller.dart';
import 'macos_floating_overlay_controller.dart';
import 'windows_floating_overlay_controller.dart';

export 'floating_overlay_controller_interface.dart';

/// Creates the platform-specific [FloatingOverlayController], or `null` if
/// the current platform is unsupported.
FloatingOverlayController? createFloatingOverlayController() {
  if (Platform.isWindows) return WindowsFloatingOverlayController();
  if (Platform.isMacOS) return MacOSFloatingOverlayController();
  if (Platform.isLinux) return LinuxFloatingOverlayController();
  return null;
}
