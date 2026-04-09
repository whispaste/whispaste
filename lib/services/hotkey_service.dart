/// Global hotkey service for desktop platforms.
///
/// Registers a system-wide keyboard shortcut (default: Ctrl+Shift+D)
/// that toggles recording regardless of which window has focus.
/// Uses the `hotkey_manager` package.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_labels.dart';
import '../core/config/settings_provider.dart';
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

    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (prev, next) {
      final previous = prev?.value;
      final current = next.value;
      if (current == null || previous == null) return;
      final changed =
          previous.hotkeyKey != current.hotkeyKey ||
          previous.hotkeyModifiers != current.hotkeyModifiers ||
          previous.hotkeyEnabled != current.hotkeyEnabled;
      if (changed) {
        if (current.hotkeyEnabled) {
          unawaited(_registerFromSettings(current));
        } else {
          unawaited(_unregister());
          _log.info('Global hotkey disabled by user');
        }
      }
    });

    Future.microtask(() async {
      final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
      if (settings.hotkeyEnabled) {
        await _registerFromSettings(settings);
      }
    });
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

    _registeredHotKey = HotKey(key: key, modifiers: modifiers);

    try {
      await hotKeyManager.register(
        _registeredHotKey!,
        keyDownHandler: (_) {
          _log.info('Global hotkey pressed');
          onHotkeyPressed?.call();
        },
      );
      _log.info('Hotkey registered successfully');
    } on Exception catch (e) {
      _log.warning('Failed to register hotkey: $e');
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _registerFromSettings(AppSettings settings) async {
    try {
      await updateHotkey(
        key: _resolveKey(settings.hotkeyKey),
        modifiers: _resolveModifiers(settings.hotkeyModifiers),
      );
      _initialized = true;
      _log.info(
        'Global hotkey synced from settings: '
        '${formatHotkeyShortcut(settings.hotkeyModifiers, settings.hotkeyKey)}',
      );
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
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global hotkey provider — eagerly watched in the app shell.
final hotkeyServiceProvider = NotifierProvider<HotkeyService, void>(
  HotkeyService.new,
);

// ---------------------------------------------------------------------------
// Key resolution helpers
// ---------------------------------------------------------------------------

/// Maps a stored key label (e.g. 'D', 'F1') to a [LogicalKeyboardKey].
LogicalKeyboardKey _resolveKey(String label) {
  final upper = label.toUpperCase();
  // Single letter
  if (upper.length == 1 &&
      upper.codeUnitAt(0) >= 65 &&
      upper.codeUnitAt(0) <= 90) {
    final offset = upper.codeUnitAt(0) - 65;
    return LogicalKeyboardKey(0x00000000061 + offset); // keyA = 0x61
  }
  // Function keys
  final fnMatch = RegExp(r'^F(\d+)$').firstMatch(upper);
  if (fnMatch != null) {
    final n = int.parse(fnMatch.group(1)!);
    if (n >= 1 && n <= 12) {
      return LogicalKeyboardKey(0x00100000070 + n - 1); // f1..f12
    }
  }
  // Named keys
  return switch (upper) {
    'SPACE' => LogicalKeyboardKey.space,
    'ENTER' => LogicalKeyboardKey.enter,
    'TAB' => LogicalKeyboardKey.tab,
    'ESCAPE' => LogicalKeyboardKey.escape,
    'BACKSPACE' => LogicalKeyboardKey.backspace,
    'DELETE' => LogicalKeyboardKey.delete,
    'INSERT' => LogicalKeyboardKey.insert,
    'HOME' => LogicalKeyboardKey.home,
    'END' => LogicalKeyboardKey.end,
    'PAGEUP' => LogicalKeyboardKey.pageUp,
    'PAGEDOWN' => LogicalKeyboardKey.pageDown,
    _ => LogicalKeyboardKey.keyD, // fallback
  };
}

/// Maps a stored modifier string (e.g. 'ctrl+shift') to [HotKeyModifier] list.
List<HotKeyModifier> _resolveModifiers(String modifiers) {
  final parts = modifiers.toLowerCase().split('+');
  final result = <HotKeyModifier>[];
  for (final part in parts) {
    switch (part.trim()) {
      case 'ctrl' || 'control':
        result.add(HotKeyModifier.control);
      case 'shift':
        result.add(HotKeyModifier.shift);
      case 'alt':
        result.add(HotKeyModifier.alt);
      case 'meta' || 'win' || 'super' || 'cmd':
        result.add(HotKeyModifier.meta);
    }
  }
  return result;
}
