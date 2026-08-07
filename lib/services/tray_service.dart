/// System tray integration for desktop platforms.
///
/// Provides a tray icon with context menu for quick access to
/// recording, settings, and quitting the app. Uses `tray_manager`.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/config/settings_provider.dart';
import '../core/data/database.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/platform/macos_lifecycle_channel.dart';
import '../core/recording/recording_state.dart';
import 'audio_service.dart';
import 'microphone_selection_service.dart';
import 'stt/stt_bundle.dart';
import 'tray_mic_menu.dart';

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
    _showContextMenu();
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
      default:
        final key = menuItem.key;
        if (key == null) return;
        final micLabel = micLabelFromMenuKey(key);
        if (micLabel != null) {
          _selectMicrophone(micLabel);
          return;
        }
        // Action-needed item or any custom key: open the window and
        // route the click to the action handler for resolution.
        _showWindow();
        onActionNeededTap?.call(key);
    }
  }

  /// Click handler for the action-needed item in the tray menu — fired
  /// when the user clicks "⚠ Auto-Paste blocked" (or similar).
  ValueChanged<String>? onActionNeededTap;

  @override
  void onTrayIconMouseUp() {}
  @override
  void onTrayIconRightMouseUp() {}

  // ── Public API ────────────────────────────────────────────────────────────

  /// Updates the tray menu to reflect the current recording state.
  void updateRecordingState(RecordingState recording, {L10n? l10n}) {
    if (!_isDesktop || !_initialized) return;
    _l10n = l10n;
    _lastRecording = recording;
    _rebuildMenu();
  }

  /// Marks an action item visible in the tray menu — top-of-list entry
  /// that survives until [clearActionNeeded]. Use for issues the user
  /// must fix manually (Auto-Paste permission missing, etc.) so the
  /// reminder stays visible when the main window is closed.
  void setActionNeeded({
    required String label,
    required String tooltip,
    String? menuItemKey,
  }) {
    if (!_isDesktop || !_initialized) return;
    _actionNeeded = _ActionNeeded(
      label: label,
      tooltip: tooltip,
      menuItemKey: menuItemKey ?? 'action_needed',
    );
    try {
      trayManager.setToolTip(tooltip);
    } on Exception catch (e) {
      _log.warning('Tray tooltip update failed', e);
    }
    _rebuildMenu();
  }

  /// Clears any pending action item from the tray menu. Called when the
  /// user has resolved the issue (e.g. paste succeeded after one failed).
  void clearActionNeeded() {
    if (!_isDesktop || !_initialized) return;
    if (_actionNeeded == null) return;
    _actionNeeded = null;
    try {
      trayManager.setToolTip('WhisPaste');
    } on Exception catch (e) {
      _log.warning('Tray tooltip reset failed', e);
    }
    _rebuildMenu();
  }

  /// Whether the tray icon was successfully initialized.
  bool get isInitialized => _initialized;

  // ── Private ───────────────────────────────────────────────────────────────

  bool _initialized = false;
  L10n? _l10n;
  RecordingState _lastRecording = const RecordingState();
  _ActionNeeded? _actionNeeded;
  List<String> _micDeviceLabels = const [micDefaultLabel];

  Future<void> _init() async {
    try {
      final iconPath = await _resolveIconPath();
      if (iconPath == null) {
        _log.warning('Tray icon not found — skipping tray setup');
        return;
      }

      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('WhisPaste');
      trayManager.addListener(this);

      _initialized = true;
      _rebuildMenu();
      _log.info('System tray initialized');
    } on Exception catch (e) {
      _log.warning('Failed to init system tray: $e');
    }
  }

  /// Refreshes the mic device list just-in-time, then pops up the menu.
  ///
  /// The device set changes while the app runs (docking/undocking) and
  /// right-mouse-down is the only pre-popup hook, so a cached list from
  /// startup would go stale.
  Future<void> _showContextMenu() async {
    await _refreshMicDevices();
    try {
      await trayManager.popUpContextMenu();
    } on Exception catch (e) {
      _log.warning('Tray context menu popup failed: $e');
    }
  }

  Future<void> _refreshMicDevices() async {
    try {
      ref.invalidate(audioInputDevicesProvider);
      // Timeout keeps the menu responsive if enumeration hangs on a flaky
      // HAL — the previous list is shown instead.
      _micDeviceLabels = await ref
          .read(audioInputDevicesProvider.future)
          .timeout(const Duration(milliseconds: 800));
    } on Exception catch (e) {
      _log.warning('Mic enumeration for tray menu failed: $e');
    }
    await _rebuildMenu();
  }

  /// Applies a microphone choice made in the tray menu — delegates to the
  /// shared [MicrophoneSelectionService] so tray and status-bar chip behave
  /// identically.
  Future<void> _selectMicrophone(String label) async {
    await ref.read(microphoneSelectionServiceProvider).select(label);
    await _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    final recording = _lastRecording;
    final isRecording = recording.isRecording;
    final l = _l10n;
    final toggleLabel = isRecording
        ? (l?.trayStopRecording ?? 'Stop Recording')
        : (l?.trayStartRecording ?? 'Start Recording');
    final statusDot = isRecording ? '🔴' : '🟢';
    final statusText = isRecording
        ? (l?.trayStatusRecording ?? 'Recording…')
        : (l?.trayStatusReady ?? 'Ready');

    final selectedMic =
        ref.read(settingsProvider).value?.audioInput.microphone ??
        micDefaultLabel;
    // Mirror the settings dropdown: no submenu when only the default
    // pseudo-device was enumerated — there is nothing to switch to.
    final hasRealMicDevices = _micDeviceLabels.length > 1;

    final action = _actionNeeded;
    final items = <MenuItem>[
      if (action != null) ...[
        MenuItem(key: action.menuItemKey, label: '⚠ ${action.label}'),
        MenuItem.separator(),
      ],
      MenuItem(key: 'status', label: '$statusDot $statusText', disabled: true),
      MenuItem.separator(),
      MenuItem(key: 'toggle_recording', label: toggleLabel),
      if (hasRealMicDevices)
        MenuItem.submenu(
          label: l?.trayMicrophone ?? 'Microphone',
          submenu: Menu(
            items: buildMicrophoneMenuItems(
              deviceLabels: _micDeviceLabels,
              selectedLabel: selectedMic,
              systemDefaultLabel:
                  l?.settingsMicSystemDefault ?? 'System Default',
            ),
          ),
        ),
      MenuItem.separator(),
      MenuItem(key: 'show', label: l?.trayOpenApp ?? 'Open WhisPaste'),
      MenuItem(key: 'settings', label: l?.traySettings ?? 'Settings'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: l?.trayQuit ?? 'Quit'),
    ];

    await trayManager.setContextMenu(Menu(items: items));
  }

  Future<String?> _resolveIconPath() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    // On Windows, prefer a dedicated ICO. PNG tray icons often render as an
    // empty transparent slot with `tray_manager`.
    if (Platform.isWindows) {
      final candidates = [
        '$exeDir\\resources\\tray.ico',
        '$exeDir\\tray.ico',
        '$exeDir\\resources\\app_icon.ico',
        '$exeDir\\app_icon.ico',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) {
          _log.info('Resolved tray icon: $path');
          return path;
        }
      }
      _log.warning('No tray icon file found, falling back to executable icon');
      return Platform.resolvedExecutable;
    }

    // macOS / Linux: try known bundle paths first (fast, no I/O allocation).
    if (Platform.isMacOS || Platform.isLinux) {
      final candidates = [
        // macOS .app bundle: flutter_assets inside App.framework (primary)
        p.normalize(
          '$exeDir/../Frameworks/App.framework/Resources/flutter_assets/assets/icons/logo-dark.png',
        ),
        // macOS .app bundle: flutter_assets directly in Resources (fallback)
        p.normalize(
          '$exeDir/../Resources/flutter_assets/assets/icons/logo-dark.png',
        ),
        // macOS .app bundle: Resources root (set via Xcode bundle-resource copy)
        p.normalize('$exeDir/../Resources/tray.png'),
        // Linux: flutter_assets next to executable
        p.normalize('$exeDir/data/flutter_assets/assets/icons/logo-dark.png'),
      ];
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          _log.info('Resolved tray icon: $candidate');
          return candidate;
        }
      }

      // Last resort: extract from rootBundle to a temp file.
      // This is reliable regardless of bundle layout changes across Flutter versions.
      try {
        final bytes = await rootBundle.load('assets/icons/logo-dark.png');
        final tmp = File(
          p.join(Directory.systemTemp.path, 'whispaste_tray_icon.png'),
        );
        await tmp.writeAsBytes(bytes.buffer.asUint8List());
        _log.info('Extracted tray icon via rootBundle → ${tmp.path}');
        return tmp.path;
      } on Exception catch (e) {
        _log.warning('rootBundle icon extraction failed: $e');
      }
    }

    return null;
  }

  Future<void> _showWindow() async {
    try {
      // On macOS, restore Dock presence before showing the window.
      await MacOSLifecycleChannel.setRegular();
      await windowManager.show();
      await windowManager.focus();
    } on Exception catch (e) {
      _log.warning('Failed to show window: $e');
    }
  }

  Future<void> _quit() async {
    // Stop the STT subprocess before destroying to prevent orphaned processes.
    try {
      ref.read(localSttBundleProvider.notifier).stop();
    } catch (e) {
      _log.debug('STT subprocess stop failed during quit (non-fatal): $e');
    }

    try {
      await trayManager.destroy().timeout(const Duration(seconds: 1));
    } on Exception catch (e) {
      _log.debug('Tray destroy failed during quit (non-fatal): $e');
    }

    // Close Drift DB before engine teardown — prevents SIGABRT from
    // sqlite3LeaveMutexAndCloseZombie when open stream statements survive
    // into Dart isolate shutdown.
    try {
      await ref
          .read(historyDatabaseProvider)
          .close()
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      _log.debug('DB close failed during quit (non-fatal): $e');
    }

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
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
}

class _ActionNeeded {
  const _ActionNeeded({
    required this.label,
    required this.tooltip,
    required this.menuItemKey,
  });
  final String label;
  final String tooltip;
  final String menuItemKey;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// System tray provider — eagerly watched in the app shell.
final trayServiceProvider = NotifierProvider<TrayService, void>(
  TrayService.new,
);
