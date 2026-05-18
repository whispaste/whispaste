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
import 'hotkey_key_resolver.dart';

// ---------------------------------------------------------------------------
// Registrar abstraction (enables unit testing without platform channels)
// ---------------------------------------------------------------------------

/// Thin abstraction over the two [hotKeyManager] operations used by
/// [HotkeyService]. Swap with a [FakeHotKeyRegistrar] in tests.
abstract class HotKeyRegistrar {
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  });

  Future<void> unregister(HotKey hotKey);

  /// Whether this registrar supports key-up events.
  ///
  /// macOS: true (hotkey_manager native layer fires onKeyUp).
  /// Windows/Linux: false (RegisterHotKey is key-down only; WH_KEYBOARD_LL
  /// not yet implemented).
  bool get supportsKeyUp;
}

/// Production registrar — delegates to the package singleton.
class _PackageHotKeyRegistrar implements HotKeyRegistrar {
  const _PackageHotKeyRegistrar();

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) => hotKeyManager.register(
    hotKey,
    keyDownHandler: keyDownHandler,
    keyUpHandler: keyUpHandler,
  );

  @override
  Future<void> unregister(HotKey hotKey) => hotKeyManager.unregister(hotKey);

  @override
  bool get supportsKeyUp => Platform.isMacOS;
}

// ---------------------------------------------------------------------------
// Registration status — observable by UI (ReadyStep) so we can surface a
// blocking conflict warning before the user clicks "Start".
// ---------------------------------------------------------------------------

/// Lifecycle status of the global hotkey registration.
///
/// - [unknown]: no registration attempt has completed yet (transitional).
/// - [success]: the user-configured hotkey is currently registered.
/// - [conflict]: the user-configured hotkey could not be registered (typically
///   because another app or the OS owns the same shortcut). The service falls
///   back to the safe-default in this case, but UI surfaces should still prompt
///   the user to re-bind before continuing.
enum HotkeyRegistrationStatus { unknown, success, conflict }

/// Notifier holding the latest [HotkeyRegistrationStatus]. Written by
/// [HotkeyService]; watched by [ReadyStep] and any other surface that needs
/// to react to a conflict.
class HotkeyRegistrationStatusController
    extends Notifier<HotkeyRegistrationStatus> {
  @override
  HotkeyRegistrationStatus build() => HotkeyRegistrationStatus.unknown;

  /// Update the current registration status. Called from [HotkeyService] —
  /// kept as a method (rather than direct state assignment) so the test
  /// surface stays explicit.
  void set(HotkeyRegistrationStatus status) {
    state = status;
  }
}

/// Provider for the global [HotkeyRegistrationStatus] state.
final hotkeyRegistrationStatusProvider =
    NotifierProvider<
      HotkeyRegistrationStatusController,
      HotkeyRegistrationStatus
    >(HotkeyRegistrationStatusController.new);

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

  /// Callback fired when the global hotkey is pressed (key-down).
  VoidCallback? onHotkeyPressed;

  /// Callback fired when the global hotkey is released (key-up).
  ///
  /// Only fires on platforms where [supportsKeyUp] is true (currently macOS).
  VoidCallback? onHotkeyReleased;

  /// Callback fired when hotkey registration fails and the safe default is
  /// used instead.
  ///
  /// The caller (e.g. [ServiceBootstrapWidget]) should show a localised toast
  /// that prompts the user to re-bind their shortcut in Settings.
  VoidCallback? onRegistrationFailed;

  /// Whether the current platform supports key-up events for global hotkeys.
  bool get supportsKeyUp => _registrar.supportsKeyUp;

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
        keyUpHandler: _registrar.supportsKeyUp
            ? (_) {
                _log.info('Global hotkey released');
                onHotkeyReleased?.call();
              }
            : null,
      );
      _log.info('Hotkey registered successfully');
      _setStatus(HotkeyRegistrationStatus.success);
    } on Object catch (e, st) {
      // Catch Object (not just Exception) so TypeError from hotkey_manager
      // is handled gracefully.
      _setStatus(HotkeyRegistrationStatus.conflict);
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
        key: resolveKey(settings.hotkeyKey),
        modifiers: resolveModifiers(settings.hotkeyModifiers),
      );
      _initialized = true;
      _log.info(
        'Global hotkey synced from settings: '
        '${formatHotkeyShortcut(settings.hotkeyModifiers, settings.hotkeyKey)}',
      );
    } on ArgumentError catch (e) {
      // resolveKey rejected the stored key label. Happens with pre-fix DBs
      // that contain a non-resolvable label (e.g. 'Ö', '+', ';') the recorder
      // used to accept but the registrar cannot handle. Fall back to
      // safe-default and prompt for re-bind. Sibling of the TypeError path
      // in updateHotkey — same observable behaviour for the user.
      _setStatus(HotkeyRegistrationStatus.conflict);
      final label = settings.hotkeyKey;
      final firstCodepointHex = label.isEmpty
          ? '0x0'
          : '0x${label.runes.first.toRadixString(16)}';
      _log.warning(
        'Stored hotkey key "$label" is not resolvable — falling back to '
        'safe-default ($safeDefaultHotKeyLabel). Reason: $e',
      );
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: 'key_label_not_resolvable',
          level: SentryLevel.info,
          // PII-safe diagnostic: length + first codepoint only, never the
          // raw label.
          data: {
            'label_length': label.length,
            'first_codepoint': firstCodepointHex,
          },
        ),
      );
      await _registerSafeDefault();
    } on Object catch (e) {
      _setStatus(HotkeyRegistrationStatus.conflict);
      _log.warning('Failed to register global hotkey: $e');
    }
  }

  /// Writes [status] to [hotkeyRegistrationStatusProvider] if a Riverpod ref
  /// is available (i.e. the service was created via the provider, not via a
  /// bare `HotkeyService()` constructor in a unit test).
  ///
  /// Guarded so the existing standalone-service tests in
  /// `test/services/hotkey_service_test.dart` keep working — they construct
  /// the service directly without a [ProviderContainer].
  void _setStatus(HotkeyRegistrationStatus status) {
    try {
      ref.read(hotkeyRegistrationStatusProvider.notifier).set(status);
    } on Object catch (_) {
      // No ref available (standalone test instance) — skip silently.
    }
  }

  /// Test-only entry point that exercises [_registerFromSettings] directly
  /// without going through the Riverpod [build] lifecycle.
  ///
  /// Lets unit tests verify the ArgumentError fallback path for corrupted
  /// `hotkey_key` values without standing up a full settings provider.
  @visibleForTesting
  Future<void> debugRegisterFromSettings({
    required String hotkeyKey,
    required String hotkeyModifiers,
  }) {
    return _registerFromSettings(
      AppSettings.defaults.copyWith(
        hotkeyKey: hotkeyKey,
        hotkeyModifiers: hotkeyModifiers,
        hotkeyEnabled: true,
      ),
    );
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
        keyUpHandler: _registrar.supportsKeyUp
            ? (_) {
                _log.info('Safe-default hotkey released');
                onHotkeyReleased?.call();
              }
            : null,
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
