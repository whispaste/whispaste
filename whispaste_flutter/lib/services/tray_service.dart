/// System tray integration for desktop platforms.
///
/// Provides a tray icon with context menu for quick access to
/// recording, settings, and quitting the app. Uses `tray_manager`.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/recording/recording_state.dart';

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Manages the system tray icon and its context menu.
///
/// Listens to [recordingProvider] to update the tray tooltip and menu
/// label between "Start Recording" and "Stop Recording".
class TrayService extends Notifier<void> implements TrayListener {
  static final _log = AppLogger('TrayService');

  /// Callback invoked when the user clicks "Start/Stop Recording" in the tray.
  VoidCallback? onToggleRecording;

  /// Callback invoked when the user clicks a navigation item (e.g. 'settings').
  ValueChanged<String>? onNavigate;

  @override
  void build() {
    // Only run on desktop platforms.
    if (!_isDesktop) return;

    Future.microtask(_init);
    ref.onDispose(_destroy);
  }

  // ── TrayListener callbacks ────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    // Left-click on tray icon → show/restore window.
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showWindow();
      case 'toggle_recording':
        onToggleRecording?.call();
      case 'settings':
        _showWindow();
        onNavigate?.call('settings');
      case 'quit':
        _quit();
    }
  }

  @override
  void onTrayIconMouseUp() {}
  @override
  void onTrayIconRightMouseUp() {}

  // ── Public API ────────────────────────────────────────────────────────────

  /// Updates the tray menu to reflect the current recording state.
  void updateRecordingState(RecordingState recording, {L10n? l10n}) {
    if (!_isDesktop || !_initialized) return;
    _l10n = l10n;
    _rebuildMenu(recording);
  }

  // ── Private ───────────────────────────────────────────────────────────────

  bool _initialized = false;
  L10n? _l10n;

  Future<void> _init() async {
    try {
      final iconPath = _resolveIconPath();
      if (iconPath == null) {
        _log.warning('Tray icon not found — skipping tray setup');
        return;
      }

      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('WhisPaste');
      trayManager.addListener(this);

      _initialized = true;
      _rebuildMenu(const RecordingState());
      _log.info('System tray initialized');
    } on Exception catch (e) {
      _log.warning('Failed to init system tray: $e');
    }
  }

  void _rebuildMenu(RecordingState recording) {
    final isRecording = recording.isRecording;
    final l = _l10n;
    final toggleLabel = isRecording
        ? (l?.trayStopRecording ?? 'Stop Recording')
        : (l?.trayStartRecording ?? 'Start Recording');
    final statusDot = isRecording ? '🔴' : '🟢';
    final statusText = isRecording
        ? (l?.trayStatusRecording ?? 'Recording…')
        : (l?.trayStatusReady ?? 'Ready');

    final menu = Menu(items: [
      MenuItem(key: 'status', label: '$statusDot $statusText', disabled: true),
      MenuItem.separator(),
      MenuItem(key: 'toggle_recording', label: toggleLabel),
      MenuItem.separator(),
      MenuItem(key: 'show', label: l?.trayOpenApp ?? 'Open WhisPaste'),
      MenuItem(key: 'settings', label: l?.traySettings ?? 'Settings'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: l?.trayQuit ?? 'Quit'),
    ]);

    trayManager.setContextMenu(menu);
  }

  String? _resolveIconPath() {
    // On Windows, use the ICO from the runner resources directory.
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      // Check runner resources path (development + installed).
      final candidates = [
        '$exeDir\\data\\flutter_assets\\assets\\icons\\logo-dark.png',
        '$exeDir\\resources\\app_icon.ico',
        '$exeDir\\app_icon.ico',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) return path;
      }
      // Fallback: use resolvedExecutable itself (shows exe icon).
      _log.warning('No tray icon file found, trying exe icon');
      return Platform.resolvedExecutable;
    }

    // macOS / Linux: use PNG from Flutter assets.
    if (Platform.isMacOS || Platform.isLinux) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$exeDir/../Resources/app_icon.png', // macOS bundle
        '$exeDir/data/flutter_assets/assets/icons/logo-dark.png',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) return path;
      }
    }

    return null;
  }

  Future<void> _showWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } on Exception catch (e) {
      _log.warning('Failed to show window: $e');
    }
  }

  Future<void> _quit() async {
    try {
      await trayManager.destroy();
    } on Exception catch (_) {
      // Best-effort cleanup.
    }
    // Use windowManager.destroy() for clean exit.
    await windowManager.destroy();
  }

  Future<void> _destroy() async {
    if (!_initialized) return;
    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
      _log.info('System tray destroyed');
    } on Exception catch (e) {
      _log.warning('Tray destroy error: $e');
    }
  }

  static bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// System tray provider — eagerly watched in the app shell.
final trayServiceProvider = NotifierProvider<TrayService, void>(TrayService.new);
