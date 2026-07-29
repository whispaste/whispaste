/// macOS activation policy channel for close-to-tray dock behavior.
///
/// Toggles between `.regular` (visible in Dock) and `.accessory`
/// (hidden from Dock, menu-bar-only app) via a MethodChannel.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../services/graceful_shutdown.dart';
import '../../services/single_instance_service.dart';
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

  /// Programmatic relaunch of the application bundle. Used when the paste/
  /// type capability is stuck reporting "missing" after the user has
  /// actually granted it — macOS only re-evaluates certain trust state on a
  /// fresh process, never mid-run:
  ///   - Developer-ID: after `tccutil reset` cleared stale ad-hoc-signature
  ///     TCC entries.
  ///   - Mac App Store: `CGPreflightPostEventAccess()` doesn't refresh
  ///     within an already-running process after a fresh grant via System
  ///     Settings, even though the OS's actual event delivery already
  ///     respects it — matches macOS's own "quit and relaunch?" UX for this
  ///     exact permission toggle.
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

  /// Presents the native, always-on-top "you must restart WhisPaste" modal
  /// (`NSAlert`) — visible even when WhisPaste is a hidden tray-only app, and
  /// confirming it relaunches immediately and directly on the native side.
  ///
  /// All copy is passed in (from the ARB files) so the Swift layer holds no
  /// localized strings. Fire-and-forget: the native side owns the modal loop
  /// and the relaunch; this future completes as soon as the call is dispatched,
  /// not when the user acts. Idempotent — a re-trigger while the modal is up is
  /// coalesced natively into the single visible alert.
  static Future<void> showRestartRequiredAlert({
    required String title,
    required String body,
    required String confirmLabel,
  }) => _invokeAlert(
    'showRestartRequiredAlert',
    title: title,
    body: body,
    confirmLabel: confirmLabel,
  );

  /// Presents the native "the restart didn't apply the permission — check
  /// System Settings" modal, shown when a grant-driven restart already ran and
  /// the permission is still missing. Confirming opens System Settings →
  /// Privacy & Security → Accessibility natively. This is the loop exit for the
  /// backgrounded, tray-only user: unlike [showRestartRequiredAlert] it does
  /// NOT relaunch, so a permission that genuinely won't persist can't force an
  /// endless restart cycle. Same idempotency/always-on-top behavior.
  static Future<void> showManualGrantAlert({
    required String title,
    required String body,
    required String confirmLabel,
  }) => _invokeAlert(
    'showManualGrantAlert',
    title: title,
    body: body,
    confirmLabel: confirmLabel,
  );

  /// Callbacks keyed by alert id, invoked (with the user's confirm/decline
  /// choice) when the native side reports a [showPermissionGrantAlert]
  /// dialog was dismissed — via the inbound `permissionAlertConfirmed`
  /// channel call, see [registerTerminationHandler]'s dispatch.
  static final Map<String, void Function(bool confirmed)>
  _permissionAlertCallbacks = {};

  /// Presents a native, always-on-top permission dialog (same
  /// tray-app-proof `NSAlert` treatment as [showRestartRequiredAlert]) with
  /// a confirm button and a decline button ([cancelLabel]) — per Apple's
  /// HIG a permission surface must always be declinable. Runs [onDismiss]
  /// on the Dart side with the user's choice.
  ///
  /// Unlike the fixed-behavior restart/manual-grant alerts, dismissing this
  /// one performs no native action — the native side calls back with [id]
  /// and the registered [onDismiss] decides what happens (open a settings
  /// pane, start a grant flow, or nothing on decline). Requires
  /// [registerTerminationHandler] to have been called (it owns the single
  /// inbound method-call handler).
  ///
  /// Returns `true` when the alert was dispatched (so [onDismiss] can be
  /// expected to fire eventually) and `false` when the channel call failed —
  /// callers waiting on [onDismiss] must not block forever in that case.
  static Future<bool> showPermissionGrantAlert({
    required String id,
    required String title,
    required String body,
    required String confirmLabel,
    required String cancelLabel,
    required void Function(bool confirmed) onDismiss,
  }) async {
    if (!Platform.isMacOS) return false;
    _permissionAlertCallbacks[id] = onDismiss;
    try {
      await _channel.invokeMethod('showPermissionGrantAlert', {
        'id': id,
        'title': title,
        'body': body,
        'confirmLabel': confirmLabel,
        'cancelLabel': cancelLabel,
      });
      return true;
    } on PlatformException catch (e) {
      _permissionAlertCallbacks.remove(id);
      _log.warning('showPermissionGrantAlert failed', e);
      return false;
    }
  }

  /// Shared invoker for the two native always-on-top alert channel methods —
  /// identical marshalling, only the method name differs.
  static Future<void> _invokeAlert(
    String method, {
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod(method, {
        'title': title,
        'body': body,
        'confirmLabel': confirmLabel,
      });
    } on PlatformException catch (e) {
      _log.warning('$method failed', e);
    }
  }

  /// Handles `prepareForTermination`, invoked by `AppDelegate.swift`'s
  /// `applicationShouldTerminate` override (macOS Cmd+Q / Dock "Quit")
  /// before it lets the native `NSApplication` actually terminate. Without
  /// this, native quit bypasses the Dart-level `onWindowClose` handler
  /// entirely and can abort the process mid-teardown (see
  /// `graceful_shutdown.dart`).
  static void registerTerminationHandler(ProviderContainer container) {
    if (!Platform.isMacOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'prepareForTermination') {
        await runGracefulEngineShutdown(container);
      } else if (call.method == 'relaunchFailed') {
        // Native relaunch could not start (e.g. the sandbox refused the
        // self-launch) and deliberately did NOT terminate, so the app is
        // still usable. Surface it as a breadcrumb so the failure is visible
        // in the next Sentry trace instead of vanishing silently.
        final error = (call.arguments as Map?)?['error']?.toString();
        _log.warning('Native relaunch failed (app kept running): $error');
        Sentry.addBreadcrumb(
          Breadcrumb(
            message: 'lifecycle.relaunch_failed',
            category: 'app.lifecycle',
            level: SentryLevel.warning,
            data: {'error': error ?? 'unknown'},
          ),
        );
        // markRestartAttempted() already released the single-instance lock
        // in anticipation of a fresh process taking over. Since that never
        // happened, this process is staying alive — reclaim it, or a later
        // genuine second launch attempt would wrongly succeed as primary.
        await SingleInstanceService.ensureSingleInstance();
      } else if (call.method == 'permissionAlertConfirmed') {
        final args = call.arguments as Map?;
        final id = args?['id']?.toString();
        final confirmed = args?['confirmed'] == true;
        final callback = _permissionAlertCallbacks.remove(id);
        callback?.call(confirmed);
      }
      return null;
    });
  }
}
