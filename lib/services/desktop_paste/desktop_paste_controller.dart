import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'macos_desktop_paste_controller.dart';
import 'windows_desktop_paste_controller.dart';

/// Platform-agnostic interface for desktop clipboard pasting.
///
/// The controller captures the current paste target before recording starts and
/// later restores focus so a simulated paste lands back in the intended app.
abstract class DesktopPasteController {
  /// Creates the platform-specific controller, or `null` if unsupported.
  static DesktopPasteController? create() {
    if (Platform.isWindows) return WindowsDesktopPasteController();
    if (Platform.isMacOS) return MacOSDesktopPasteController();
    return null;
  }

  /// Captures the current desktop window/application as the paste target.
  ///
  /// Returns `true` when a suitable external target window was captured.
  Future<bool> capturePasteTarget();

  /// Restores the captured target and sends the paste shortcut.
  ///
  /// Returns `true` when the native bridge reported success.
  Future<bool> pasteClipboard({required Duration delay});

  /// Releases any native resources held by the controller.
  Future<void> dispose();
}

/// Shared provider for the platform desktop paste controller.
final desktopPasteControllerProvider = Provider<DesktopPasteController?>((ref) {
  final controller = DesktopPasteController.create();
  ref.onDispose(() {
    if (controller == null) return;
    unawaited(controller.dispose());
  });
  return controller;
});
