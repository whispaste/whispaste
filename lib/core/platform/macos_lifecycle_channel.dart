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

  /// Bounces the Dock icon until the user activates WhisPaste — used when
  /// the app has a pending action item (e.g. paste blocked by missing
  /// Accessibility permission) and the main window may be hidden.
  ///
  /// Returns an attention token that can be passed to [cancelUserAttention]
  /// to stop the bounce once the issue is resolved, or `null` if the call
  /// failed or the OS rejected it.
  static Future<int?> requestUserAttention({bool critical = true}) async {
    if (!Platform.isMacOS) return null;
    try {
      final token = await _channel.invokeMethod<int>('requestUserAttention', {
        'level': critical ? 'critical' : 'informational',
      });
      return token;
    } on PlatformException {
      return null;
    }
  }

  /// Cancels an attention request started by [requestUserAttention].
  static Future<void> cancelUserAttention(int token) async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('cancelUserAttentionRequest', {
        'token': token,
      });
    } on PlatformException {
      // Best-effort cancel.
    }
  }
}
