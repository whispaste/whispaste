import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/build_config.dart';
import 'desktop_paste_controller_interface.dart';
import 'macos_desktop_paste_controller.dart';
import 'windows_desktop_paste_controller.dart';

export 'desktop_paste_controller_interface.dart';

/// Shared provider for the platform desktop paste controller.
final desktopPasteControllerProvider = Provider<DesktopPasteController?>((ref) {
  // Mac App Store build: keystroke-injection paste is compiled out, so no
  // native paste controller is wired up at all.
  DesktopPasteController? controller;
  if (kAutoPasteSupported) {
    if (Platform.isWindows) {
      controller = WindowsDesktopPasteController();
    } else if (Platform.isMacOS) {
      controller = MacOSDesktopPasteController();
    }
  }
  ref.onDispose(() {
    if (controller == null) return;
    unawaited(controller.dispose());
  });
  return controller;
});
