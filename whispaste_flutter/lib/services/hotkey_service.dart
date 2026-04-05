/// Global hotkey service for desktop platforms.
///
/// Registers a system-wide keyboard shortcut (default: Ctrl+Shift+D)
/// that toggles recording regardless of which window has focus.
/// Uses the `hotkey_manager` package.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/services.dart';

import '../core/logging/app_logger.dart';

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Manages global hotkey registration for push-to-record.
///
/// The default shortcut is **Ctrl+Shift+D** (toggle mode: press to
/// start, press again to stop). Hotkey changes take effect immediately.
class HotkeyService extends Notifier<void> {
  static final _log = AppLogger('HotkeyService');

  /// Callback fired when the global hotkey is pressed.
  VoidCallback? onHotkeyPressed;

  HotKey? _registeredHotKey;
  bool _initialized = false;

  @override
  void build() {
    if (!_isDesktop) return;

    Future.microtask(_init);
    ref.onDispose(_destroy);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Re-registers the hotkey with a new combination.
  Future<void> updateHotkey({
    required LogicalKeyboardKey key,
    List<HotKeyModifier> modifiers = const [],
  }) async {
    if (!_isDesktop) return;
    await _unregister();

    _registeredHotKey = HotKey(
      key: key,
      modifiers: modifiers,
    );

    try {
      await hotKeyManager.register(_registeredHotKey!, keyDownHandler: (_) {
        _log.info('Global hotkey pressed');
        onHotkeyPressed?.call();
      });
      _log.info('Hotkey registered: $modifiers + $key');
    } on Exception catch (e) {
      _log.warning('Failed to register hotkey: $e');
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _init() async {
    try {
      // Default: Ctrl+Shift+D
      _registeredHotKey = HotKey(
        key: LogicalKeyboardKey.keyD,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      );

      await hotKeyManager.register(_registeredHotKey!, keyDownHandler: (_) {
        _log.info('Global hotkey pressed');
        onHotkeyPressed?.call();
      });

      _initialized = true;
      _log.info('Global hotkey registered: Ctrl+Shift+D');
    } on Exception catch (e) {
      _log.warning('Failed to register global hotkey: $e');
    }
  }

  Future<void> _unregister() async {
    if (_registeredHotKey != null) {
      try {
        await hotKeyManager.unregister(_registeredHotKey!);
      } on Exception catch (_) {
        // Best-effort cleanup.
      }
      _registeredHotKey = null;
    }
  }

  Future<void> _destroy() async {
    if (!_initialized) return;
    await _unregister();
    _log.info('Global hotkey unregistered');
  }

  static bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global hotkey provider — eagerly watched in the app shell.
final hotkeyServiceProvider =
    NotifierProvider<HotkeyService, void>(HotkeyService.new);
