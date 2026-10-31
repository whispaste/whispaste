import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/build_config.dart';
import 'desktop_paste_controller_interface.dart';
import 'linux_desktop_paste_controller.dart';
import 'macos_desktop_paste_controller.dart';
import 'windows_desktop_paste_controller.dart';

export 'desktop_paste_controller_interface.dart';

/// Shared provider for the platform desktop paste controller.
///
/// Deliberately does NOT call [DesktopPasteController.dispose] from
/// `ref.onDispose`: the native peer behind this channel (`DesktopPasteHost`
/// on every platform) is created once per app process in the platform
/// runner (`my_application.cc` / `AppDelegate.swift` / `flutter_window.cpp`)
/// and torn down there at real app shutdown — it is a process-lifetime
/// singleton, not scoped to whichever [ProviderContainer] happens to read
/// this provider. Sending the native `destroy` call here would permanently
/// disable paste for the rest of the process the moment *any* container
/// holding this provider is disposed (e.g. between tests, or any future
/// scoped/rebuilt container), even though other containers/readers may
/// still expect a working native peer. On Linux this manifested as later
/// `captureTarget` calls hanging forever, since the GTK embedder drops
/// platform messages silently once the channel's method-call handler has
/// been unregistered, instead of replying with "not implemented".
final desktopPasteControllerProvider = Provider<DesktopPasteController?>((ref) {
  // Mac App Store build: keystroke-injection paste is compiled out, so no
  // native paste controller is wired up at all.
  if (!kAutoPasteSupported) return null;
  if (Platform.isWindows) return WindowsDesktopPasteController();
  if (Platform.isMacOS) return MacOSDesktopPasteController();
  if (Platform.isLinux) return LinuxDesktopPasteController();
  return null;
});
