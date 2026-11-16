/// Moves the WhisPaste window beside System Settings after the Accessibility
/// deep-link (Onboarding v6, S2), so the user sees the list and the app side
/// by side and does not have to hunt for the window.
///
/// macOS only. The native side (`AppDelegate.swift`, channel
/// `whispaste/settings_window`) waits briefly for the Settings window and
/// reads its bounds; it needs no Screen Recording permission for that. Every
/// other platform, and every failure, returns `false` without a sound: the
/// window simply stays where it is.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

const _channel = MethodChannel('whispaste/settings_window');

/// Asks the native side to place the main window beside System Settings.
/// Returns `true` only when the window was moved.
Future<bool> placeBesideSystemSettings() async {
  if (!Platform.isMacOS) return false;
  try {
    return await _channel.invokeMethod<bool>('placeBesideSystemSettings') ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
