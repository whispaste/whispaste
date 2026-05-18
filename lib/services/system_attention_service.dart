/// Cross-platform "get the user's attention" service for action items
/// that need surfacing even when the main window is hidden or the user
/// is focused on another app.
///
/// Layered approach — each layer fails gracefully so a denied OS
/// notification doesn't break tray-badge / dock-bounce visibility:
///
///   1. **Native OS notification** (best-effort) — pops up in Notification
///      Center / Action Center. May silently no-op on ad-hoc-signed apps
///      or when the user has denied notification permission.
///   2. **Dock bounce** (macOS) / **Taskbar flash** (Windows) — works
///      regardless of code-signing or permissions, gets the user's eye
///      reliably.
///   3. **Tray menu** — persistent reminder that survives until the user
///      acts on it. Owned by [TrayService], updated via [setActionNeeded].
///
/// Call [requestAttention] when something goes wrong; call [clearAttention]
/// when the issue is resolved (e.g. a paste succeeded after one failed).
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import '../core/logging/app_logger.dart';
import '../core/platform/macos_lifecycle_channel.dart';

/// Identity of an attention request — used to throttle duplicate alerts
/// for the same underlying problem (e.g. don't spam the user with 5
/// "paste blocked" notifications during a single recording session).
enum AttentionKind {
  pasteBlockedPermission,
  pasteBlockedNoTarget,
  pasteFailedUnknown,
}

class SystemAttentionService {
  SystemAttentionService();

  static final _log = AppLogger('SystemAttention');
  static const _windowsChannel = MethodChannel('com.whispaste.attention');

  /// Minimum time between two attention requests of the same [AttentionKind].
  /// Avoids spamming the user if paste fails repeatedly in quick succession.
  static const Duration _throttle = Duration(minutes: 1);

  final Map<AttentionKind, DateTime> _lastFired = {};
  int? _macAttentionToken;
  bool _windowsFlashActive = false;
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await localNotifier.setup(
        appName: 'WhisPaste',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    } on Exception catch (e) {
      _log.warning('local_notifier setup failed (notifications disabled)', e);
    }
  }

  /// Fire all three attention layers (notification + dock/taskbar + tray
  /// hook out via [onTrayActionNeeded]) for the given [kind] of issue.
  ///
  /// Subsequent calls for the same [kind] within [_throttle] are dropped
  /// so paste failures during a single recording session don't pile up.
  Future<void> requestAttention({
    required AttentionKind kind,
    required String title,
    required String body,
  }) async {
    final now = DateTime.now();
    final last = _lastFired[kind];
    if (last != null && now.difference(last) < _throttle) {
      _log.debug('Attention throttled: $kind (last=${now.difference(last)})');
      return;
    }
    _lastFired[kind] = now;

    await _ensureInit();
    await _fireNotification(title: title, body: body);
    await _fireDockOrTaskbar();
  }

  /// Cancel any active dock-bounce / taskbar-flash request. Notifications
  /// already in the user's Notification Center are not retroactively
  /// dismissed — those expire on their own or when the user clears them.
  Future<void> clearAttention() async {
    _lastFired.clear();
    if (Platform.isMacOS && _macAttentionToken != null) {
      await MacOSLifecycleChannel.cancelUserAttention(_macAttentionToken!);
      _macAttentionToken = null;
    }
    if (Platform.isWindows && _windowsFlashActive) {
      try {
        await _windowsChannel.invokeMethod('cancelUserAttentionRequest');
      } on PlatformException {
        // Best-effort cancel.
      }
      _windowsFlashActive = false;
    }
  }

  Future<void> _fireNotification({
    required String title,
    required String body,
  }) async {
    try {
      final notif = LocalNotification(title: title, body: body);
      await notif.show();
    } on Exception catch (e) {
      // Best-effort — ad-hoc-signed apps may silently fail here, which
      // is exactly why we also fire the dock-bounce / taskbar-flash.
      _log.debug('Native notification failed (non-fatal)', e);
    }
  }

  Future<void> _fireDockOrTaskbar() async {
    if (Platform.isMacOS) {
      final token = await MacOSLifecycleChannel.requestUserAttention(
        critical: true,
      );
      if (token != null && token > 0) {
        _macAttentionToken = token;
      }
      return;
    }
    if (Platform.isWindows) {
      try {
        await _windowsChannel.invokeMethod('requestUserAttention', {
          'level': 'critical',
        });
        _windowsFlashActive = true;
      } on PlatformException catch (e) {
        _log.debug('Windows taskbar flash failed (non-fatal)', e);
      } on MissingPluginException {
        // Channel not registered (test env / older build).
      }
    }
  }
}

final systemAttentionServiceProvider = Provider<SystemAttentionService>((ref) {
  return SystemAttentionService();
});
