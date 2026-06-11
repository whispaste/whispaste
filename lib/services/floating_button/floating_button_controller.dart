import 'dart:io';

import 'floating_button_controller_interface.dart';
import 'macos_floating_button_controller.dart';
import 'windows_floating_button_controller.dart';

export 'floating_button_controller_interface.dart';

/// Creates the platform-specific [FloatingButtonController], or `null` if
/// the current platform is unsupported.
FloatingButtonController? createFloatingButtonController() {
  if (Platform.isWindows) return WindowsFloatingButtonController();
  if (Platform.isMacOS) return MacOSFloatingButtonController();
  return null;
}
