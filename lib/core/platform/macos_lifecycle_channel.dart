/// macOS activation policy channel for close-to-tray dock behavior.
///
/// Toggles between `.regular` (visible in Dock) and `.accessory`
/// (hidden from Dock, menu-bar-only app) via a MethodChannel.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

final _log = AppLogger('MacOSLifecycleChannel');

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
    } on PlatformException catch (e) {
      // Non-critical UX enhancement.
      _log.debug('setActivationPolicy(regular) failed', e);
    }
  }

  /// Hide from Dock and App Switcher (tray-only mode).
  static Future<void> setAccessory() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('setActivationPolicy', {
        'policy': 'accessory',
      });
    } on PlatformException catch (e) {
      // Non-critical UX enhancement.
      _log.debug('setActivationPolicy(accessory) failed', e);
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
    } on PlatformException catch (e) {
      _log.debug('requestUserAttention failed', e);
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
    } on PlatformException catch (e) {
      // Best-effort cancel.
      _log.debug('cancelUserAttention($token) failed', e);
    }
  }

  /// Programmatic relaunch of the application bundle. Used by the Auto-Paste
  /// onboarding step when the user has hit the ad-hoc-signed TCC-cache
  /// mismatch on macOS — after `tccutil reset` cleared stale entries,
  /// macOS only re-evaluates the app's trust on a fresh process.
  ///
  /// The call returns successfully a few hundred milliseconds before the
  /// app actually quits; callers should treat it as fire-and-forget and
  /// expect the process to terminate shortly after.
  static Future<void> restart() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('restart');
    } on PlatformException catch (e) {
      // Best-effort — if the relaunch helper failed to spawn, the user
      // still has the option to quit WhisPaste manually.
      _log.warning('App restart via platform channel failed', e);
    }
  }
}
