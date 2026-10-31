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
///   2. **Dock bounce** (macOS) / **Taskbar flash** (Windows) / **Urgency
///      hint** (Linux on X11) — works regardless of code-signing or
///      permissions, gets the user's eye reliably. Wayland has no such
///      protocol for normal clients, so there only layers 1 and 3 remain.
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

import '../core/config/settings_provider.dart';
import '../core/config/settings_sections.dart';
import '../core/logging/app_logger.dart';
import '../core/platform/linux_session_bus.dart';
import '../core/platform/macos_lifecycle_channel.dart';

/// Identity of an attention request — used to throttle duplicate alerts
/// for the same underlying problem (e.g. don't spam the user with 5
/// "paste blocked" notifications during a single recording session).
enum AttentionKind {
  pasteBlockedPermission,
  pasteBlockedNoTarget,
  pasteFailedUnknown,

  /// Windows-only: the target window runs elevated (UIPI blocked the
  /// simulated paste) — restarting WhisPaste elevated is the fix, distinct
  /// from the generic [pasteFailedUnknown] bucket.
  pasteBlockedElevation,

  /// The paste shortcut went out, but the target's read receipt could not be
  /// armed (macOS/Windows). Informational: the text is on the clipboard and
  /// nothing was restored. No error sound, no tray entry.
  pasteReceiptRefused,

  /// Smart Mode v2 (ticket 02): the local Cleanup pass failed (model load,
  /// decode error, or timeout) and the raw transcript was pasted instead —
  /// the paste itself succeeded, so this is purely informational, unlike
  /// every other [AttentionKind] here (see ADR 0009 — Smart Mode never
  /// blocks the paste).
  smartModeFallback,

  /// ticket (9.3): no microphone signal shortly after the start. Recording
  /// continues; the dead-mic timeout still stops it if nothing arrives.
  silentMicrophone,

  /// XP-5-09: another app holds the configured hotkey and the safe default
  /// starts dictation instead. Only the master switch gates it: without a
  /// working hotkey nothing else in the app is reachable from outside.
  hotkeyFallback,

  /// Linux without a tray host (GNOME without AppIndicator): the tray quick
  /// switch is not visible, so the app says so once per start.
  trayHostMissing,
}

/// Whether the native OS notification for [kind] may be shown.
///
/// The master switch [InterfaceSettings.showNotifications] gates everything;
/// below it, each category has its own switch. Dock bounce and taskbar flash
/// are deliberately outside this gate (see [SystemAttentionService]).
bool attentionNotificationAllowed(
  AttentionKind kind,
  InterfaceSettings settings,
) {
  if (!settings.showNotifications) return false;
  return switch (kind) {
    AttentionKind.smartModeFallback => settings.notifySmartModeFallback,
    AttentionKind.silentMicrophone => settings.notifyMicrophoneProblems,
    AttentionKind.hotkeyFallback => true,
    AttentionKind.trayHostMissing => true,
    AttentionKind.pasteBlockedPermission ||
    AttentionKind.pasteBlockedNoTarget ||
    AttentionKind.pasteFailedUnknown ||
    AttentionKind.pasteBlockedElevation ||
    AttentionKind.pasteReceiptRefused => settings.notifyPasteProblems,
  };
}

/// Whether a notification server owns `org.freedesktop.Notifications`.
/// Always true off Linux.
Future<bool> notificationServerRunning() =>
    linuxSessionBusNameHasOwner('org.freedesktop.Notifications');

/// Keeps track of which native notices were handed to the OS in this app
/// session (GR-028). Only [AttentionKind.pasteReceiptRefused] is limited to one
/// per session. It is informational, and the in-app notice still shows every
/// time.
///
/// The slot is claimed before the delivery awaits anything, so two overlapping
/// deliveries cannot both pass. A claim that was not delivered (no notification
/// server, or the OS call failed) is released again by the caller.
class SessionNoticeGate {
  static const _oncePerSession = {AttentionKind.pasteReceiptRefused};

  final Set<AttentionKind> _claimed = {};

  /// True when the OS notice for [kind] may be delivered now. Claims the slot
  /// in the same synchronous step, so a second caller gets false until the
  /// first one releases it.
  bool claimOsNotice(AttentionKind kind) {
    if (!_oncePerSession.contains(kind)) return true;
    return _claimed.add(kind);
  }

  /// Gives the slot back after a delivery that was skipped or failed.
  void releaseOsNotice(AttentionKind kind) => _claimed.remove(kind);
}

class SystemAttentionService {
  SystemAttentionService(
    this._ref, {
    Future<bool> Function()? isNotificationServerRunning,
    DateTime Function()? clock,
  }) : _notificationServerRunning =
           isNotificationServerRunning ?? notificationServerRunning,
       _clock = clock ?? DateTime.now;

  final Ref _ref;
  final Future<bool> Function() _notificationServerRunning;
  final DateTime Function() _clock;

  /// How long one answer of [_notificationServerRunning] holds. A server
  /// started later (mako, dunst) is picked up after this.
  static const Duration _serverCheckTtl = Duration(seconds: 30);
  bool? _serverRunning;
  DateTime? _serverCheckedAt;

  static final _log = AppLogger('SystemAttention');
  static const _attentionChannel = MethodChannel('com.whispaste.attention');

  /// Minimum time between two attention requests of the same [AttentionKind].
  /// Avoids spamming the user if paste fails repeatedly in quick succession.
  static const Duration _throttle = Duration(minutes: 1);

  final Map<AttentionKind, DateTime> _lastFired = {};
  int? _macAttentionToken;
  bool _taskbarFlashActive = false;
  bool _initialized = false;
  final _sessionNotices = SessionNoticeGate();

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
    void Function()? onClick,
  }) async {
    final now = DateTime.now();
    final last = _lastFired[kind];
    if (last != null && now.difference(last) < _throttle) {
      _log.debug('Attention throttled: $kind (last=${now.difference(last)})');
      return;
    }
    _lastFired[kind] = now;

    await _ensureInit();
    await _fireNotification(
      kind: kind,
      title: title,
      body: body,
      onClick: onClick,
    );
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
    if ((Platform.isWindows || Platform.isLinux) && _taskbarFlashActive) {
      try {
        await _attentionChannel.invokeMethod('cancelUserAttentionRequest');
      } on PlatformException catch (e) {
        _log.debug('Taskbar flash cancel failed (non-fatal): $e');
      }
      _taskbarFlashActive = false;
    }
  }

  Future<void> _fireNotification({
    required AttentionKind kind,
    required String title,
    required String body,
    void Function()? onClick,
  }) async {
    // Respect the user's notification switches (master and per category).
    // Dock-bounce / taskbar-flash stay active in either case — those are the
    // fallback attention path that survives even when notifications are
    // suppressed.
    final settings = _ref.read(settingsProvider).value ?? AppSettings.defaults;
    if (!attentionNotificationAllowed(kind, settings.interface_)) {
      _log.debug('Notification suppressed for $kind by user settings');
      return;
    }
    if (!_sessionNotices.claimOsNotice(kind)) {
      _log.debug('OS notice for $kind already shown this session');
      return;
    }
    var delivered = false;
    try {
      if (!await _notificationServerAvailable()) {
        // libnotify would start the server synchronously on the GTK main
        // thread and freeze the app for the 25 s D-Bus timeout (XP-7-19). The
        // in-app toast and the overlay still carry the message.
        _log.info('No notification server on the session bus; skipped $kind');
        return;
      }
      final notif = LocalNotification(title: title, body: body)
        ..onClick = onClick;
      await notif.show();
      delivered = true;
    } on Exception catch (e) {
      // Best-effort — ad-hoc-signed apps may silently fail here, which
      // is exactly why we also fire the dock-bounce / taskbar-flash.
      _log.debug('Native notification failed (non-fatal)', e);
    } finally {
      // Only a delivered notice uses up the session slot.
      if (!delivered) _sessionNotices.releaseOsNotice(kind);
    }
  }

  Future<bool> _notificationServerAvailable() async {
    final checkedAt = _serverCheckedAt;
    final now = _clock();
    if (_serverRunning != null &&
        checkedAt != null &&
        now.difference(checkedAt) < _serverCheckTtl) {
      return _serverRunning!;
    }
    final running = await _notificationServerRunning();
    _serverRunning = running;
    _serverCheckedAt = now;
    return running;
  }

  Future<void> _fireDockOrTaskbar() async {
    // Wayland is deliberately left out: it has no attention protocol for
    // normal clients (no urgency hint, no taskbar flash for a hidden window).
    // The runner answers `false` there, so nothing is faked. The toast and
    // the tray entry carry the message instead.
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
        await _attentionChannel.invokeMethod('requestUserAttention', {
          'level': 'critical',
        });
        _taskbarFlashActive = true;
      } on PlatformException catch (e) {
        _log.debug('Windows taskbar flash failed (non-fatal)', e);
      } on MissingPluginException catch (e) {
        _log.debug(
          'Windows taskbar flash channel not registered (non-fatal): $e',
        );
      }
      return;
    }
    if (Platform.isLinux) {
      try {
        // Sets the X11 urgency hint. The runner answers false under Wayland.
        final delivered = await _attentionChannel.invokeMethod<bool>(
          'requestUserAttention',
          {'level': 'critical'},
        );
        _taskbarFlashActive = delivered ?? false;
      } on PlatformException catch (e) {
        _log.debug('Linux urgency hint failed (non-fatal)', e);
      } on MissingPluginException catch (e) {
        _log.debug('Linux urgency hint channel not registered (non-fatal): $e');
      }
    }
  }
}

final systemAttentionServiceProvider = Provider<SystemAttentionService>((ref) {
  return SystemAttentionService(ref);
});
