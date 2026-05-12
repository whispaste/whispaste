/// macOS activation policy channel for close-to-tray dock behavior.
///
/// Toggles between `.regular` (visible in Dock) and `.accessory`
/// (hidden from Dock, menu-bar-only app) via a MethodChannel.
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// Controls macOS NSApplication activation policy from Dart.
///
/// Call [setRegular] when restoring the main window (dock icon visible).
/// Call [setAccessory] when hiding to tray (dock icon hidden).
class MacOSLifecycleChannel {
  MacOSLifecycleChannel._();

  static const _channel = MethodChannel('com.whispaste.app_lifecycle');

  /// Show the app in Dock and App Switcher (normal app mode).
  static Future<void> setRegular() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('setActivationPolicy', {'policy': 'regular'});
    } on PlatformException {
      // Silently ignore — non-critical UX enhancement.
    }
  }

  /// Hide from Dock and App Switcher (tray-only mode).
  static Future<void> setAccessory() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('setActivationPolicy', {
        'policy': 'accessory',
      });
    } on PlatformException {
      // Silently ignore — non-critical UX enhancement.
    }
  }
}
