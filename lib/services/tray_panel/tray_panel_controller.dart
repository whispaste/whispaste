import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../method_channel_platform_host.dart';
import 'tray_panel_protocol.dart';

final _log = AppLogger('TrayPanelController');

/// Events from the native tray panel shell.
sealed class TrayPanelEvent {
  const TrayPanelEvent();
}

/// The user pressed a panel control; [action] is a [TrayPanelAction] id.
class TrayPanelActionEvent extends TrayPanelEvent {
  const TrayPanelActionEvent(this.action);
  final String action;
}

/// The panel left the screen (Escape, click outside, action).
class TrayPanelDismissed extends TrayPanelEvent {
  const TrayPanelDismissed();
}

/// Contract of the native panel shell, so the tray service and its tests do
/// not depend on a platform channel.
abstract interface class TrayPanelController {
  Stream<TrayPanelEvent> get events;

  /// Opens (or, when it is open, closes) the panel anchored at the tray icon
  /// with [content]. Completes with false when the panel could not be shown,
  /// so the caller falls back to the native menu.
  Future<bool> toggle(TrayPanelContent content);

  /// Pushes a fresh snapshot while the panel is open.
  Future<void> update(TrayPanelContent content);

  Future<void> hide();

  Future<void> dispose();
}

/// Native shell over `com.whispaste.tray_panel`: `TrayPanelHost.swift` on
/// macOS, `tray_panel_host.cpp` on Windows, `tray_panel_host.cc` on Linux.
class NativeTrayPanelController
    extends MethodChannelPlatformHost<TrayPanelEvent>
    implements TrayPanelController {
  NativeTrayPanelController() : super('com.whispaste.tray_panel');

  @override
  TrayPanelEvent? parseNativeEvent(MethodCall call) {
    switch (call.method) {
      case 'onAction':
        final args = call.arguments;
        final action = args is Map ? args['action'] : null;
        return action is String ? TrayPanelActionEvent(action) : null;
      case 'onDismissed':
        return const TrayPanelDismissed();
      default:
        return null;
    }
  }

  @override
  Future<bool> toggle(TrayPanelContent content) async {
    try {
      final shown = await invokeMapMethod<String, Object?>(
        'toggle',
        content.toMap(),
      );
      return shown?['ok'] == true;
    } on PlatformException catch (e) {
      _log.warning('Tray panel toggle failed: $e');
      return false;
    } on MissingPluginException catch (e) {
      _log.debug('Tray panel shell unavailable: $e');
      return false;
    }
  }

  @override
  Future<void> update(TrayPanelContent content) async {
    try {
      await invokeMethod('update', content.toMap());
    } on PlatformException catch (e) {
      // Cosmetic: the next show sends a full snapshot again.
      _log.debug('Tray panel update failed: $e');
    } on MissingPluginException catch (e) {
      _log.debug('Tray panel shell unavailable: $e');
    }
  }

  @override
  Future<void> hide() async {
    try {
      await invokeMethod('hide');
    } on PlatformException catch (e) {
      _log.debug('Tray panel hide failed: $e');
    } on MissingPluginException catch (e) {
      _log.debug('Tray panel shell unavailable: $e');
    }
  }
}

/// The platform's panel shell, or null where none exists (tests, mobile).
TrayPanelController? createTrayPanelController() =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux
    ? NativeTrayPanelController()
    : null;

final trayPanelControllerProvider = Provider<TrayPanelController?>((ref) {
  final controller = createTrayPanelController();
  if (controller != null) ref.onDispose(controller.dispose);
  return controller;
});
