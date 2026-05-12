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
import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/config/settings_labels.dart';
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';

// ---------------------------------------------------------------------------
// Registrar abstraction (enables unit testing without platform channels)
// ---------------------------------------------------------------------------

/// Thin abstraction over the two [hotKeyManager] operations used by
/// [HotkeyService]. Swap with a [FakeHotKeyRegistrar] in tests.
abstract class HotKeyRegistrar {
  Future<void> register(HotKey hotKey, {HotKeyHandler? keyDownHandler});

  Future<void> unregister(HotKey hotKey);
}

/// Production registrar — delegates to the package singleton.
class _PackageHotKeyRegistrar implements HotKeyRegistrar {
  const _PackageHotKeyRegistrar();

  @override
  Future<void> register(HotKey hotKey, {HotKeyHandler? keyDownHandler}) =>
      hotKeyManager.register(hotKey, keyDownHandler: keyDownHandler);

  @override
  Future<void> unregister(HotKey hotKey) => hotKeyManager.unregister(hotKey);
}

// ---------------------------------------------------------------------------
// Safe-default hotkey
// ---------------------------------------------------------------------------

/// Safe-default hotkey used when the user's configured shortcut fails to
/// register (e.g. due to a `TypeError` from `hotkey_manager`).
///
/// Platform-aware: macOS uses Meta (Cmd) instead of Control.
HotKey get safeDefaultHotKey => HotKey(
  key: LogicalKeyboardKey.space,
  modifiers: Platform.isMacOS
      ? [HotKeyModifier.meta, HotKeyModifier.shift]
      : [HotKeyModifier.control, HotKeyModifier.shift],
);

/// Human-readable label for the safe-default hotkey shown in toasts.
String get safeDefaultHotKeyLabel =>
    Platform.isMacOS ? 'Cmd+Shift+Space' : 'Ctrl+Shift+Space';

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Manages global hotkey registration for push-to-record.
///
/// The default shortcut is **Ctrl+Shift+D** (toggle mode: press to
/// start, press again to stop). Hotkey changes take effect immediately.
///
/// When registration fails with any [Object] (including [TypeError] from
/// `hotkey_manager`), the service falls back to a safe-default hotkey
/// (Ctrl/Cmd+Shift+Space) and invokes [onRegistrationFailed] so the caller
/// can display a localised toast prompting the user to re-bind.
class HotkeyService extends Notifier<void> {
  static final _log = AppLogger('HotkeyService');

  /// Callback fired when the global hotkey is pressed.
  VoidCallback? onHotkeyPressed;

  /// Callback fired when hotkey registration fails and the safe default is
  /// used instead.
  ///
  /// The caller (e.g. [ServiceBootstrapWidget]) should show a localised toast
  /// that prompts the user to re-bind their shortcut in Settings.
  VoidCallback? onRegistrationFailed;

  HotKey? _registeredHotKey;
  bool _initialized = false;
  DateTime? _lastHotkeyPress;

  /// Pluggable registrar — defaults to the package singleton; override in
  /// tests by calling [injectRegistrar].
  HotKeyRegistrar _registrar = const _PackageHotKeyRegistrar();

  static const _debounceMs = 600;

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

  /// Injects a custom [HotKeyRegistrar] for unit testing.
  ///
  /// Call this before [updateHotkey] to avoid real platform-channel calls.
  @visibleForTesting
  void injectRegistrar(HotKeyRegistrar registrar) {
    _registrar = registrar;
  }

  /// Re-registers the hotkey with a new combination.
  ///
  /// If registration throws any [Object] (including [TypeError] from
  /// `hotkey_manager`), the service registers the safe-default hotkey instead
  /// and fires [onRegistrationFailed].
  Future<void> updateHotkey({
    required LogicalKeyboardKey key,
    List<HotKeyModifier> modifiers = const [],
  }) async {
    if (!_isDesktop) return;
    await _unregister();

    _registeredHotKey = HotKey(key: key, modifiers: modifiers);

    try {
      await _registrar.register(
        _registeredHotKey!,
        keyDownHandler: (_) {
          final now = DateTime.now();
          if (_lastHotkeyPress != null &&
              now.difference(_lastHotkeyPress!).inMilliseconds < _debounceMs) {
            _log.debug('Hotkey debounced (within ${_debounceMs}ms window)');
            return;
          }
          _lastHotkeyPress = now;
          _log.info('Global hotkey pressed');
          onHotkeyPressed?.call();
        },
      );
      _log.info('Hotkey registered successfully');
    } on Object catch (e, st) {
      // Catch Object (not just Exception) so TypeError from hotkey_manager
      // is handled gracefully.
      final keyCode = key.keyId.toRadixString(16);
      _log.warning('Failed to register hotkey (key=0x$keyCode): $e');

      // Sentry breadcrumb — key code only, no recording content or PII.
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: 'hotkey_registration_failed',
          level: SentryLevel.info,
          data: {'failed_key_code': '0x$keyCode'},
        ),
      );

      _log.warning(
        'Falling back to safe-default hotkey ($safeDefaultHotKeyLabel): $e\n$st',
      );
      await _registerSafeDefault();
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
    } on Object catch (e) {
      _log.warning('Failed to register global hotkey: $e');
    }
  }

  /// Registers the safe-default hotkey and fires [onRegistrationFailed].
  Future<void> _registerSafeDefault() async {
    final fallback = safeDefaultHotKey;
    _registeredHotKey = fallback;
    try {
      await _registrar.register(
        fallback,
        keyDownHandler: (_) {
          final now = DateTime.now();
          if (_lastHotkeyPress != null &&
              now.difference(_lastHotkeyPress!).inMilliseconds < _debounceMs) {
            return;
          }
          _lastHotkeyPress = now;
          _log.info('Safe-default hotkey pressed');
          onHotkeyPressed?.call();
        },
      );
      _log.info(
        'Safe-default hotkey registered successfully ($safeDefaultHotKeyLabel)',
      );
      _initialized = true;
      onRegistrationFailed?.call();
    } on Object catch (e) {
      // Even the fallback failed — log and leave the service in a non-crashing
      // degraded state.
      _log.error('Safe-default hotkey also failed to register: $e');
      _registeredHotKey = null;
    }
  }

  Future<void> _unregister() async {
    if (_registeredHotKey != null) {
      try {
        await _registrar.unregister(_registeredHotKey!);
      } on Object catch (_) {
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
