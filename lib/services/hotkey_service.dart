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
import '../core/logging/perf_instrumentation.dart';
import 'hotkey_key_resolver.dart';
import 'keyboard_up_monitor.dart';

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

/// Notifier holding the [HotkeyRegistrationStatus] for the quick-note hotkey
/// (ticket 20) — kept fully separate from [hotkeyRegistrationStatusProvider]
/// so a conflict on one action never surfaces as a conflict on the other.
class QuickNoteHotkeyRegistrationStatusController
    extends Notifier<HotkeyRegistrationStatus> {
  @override
  HotkeyRegistrationStatus build() => HotkeyRegistrationStatus.unknown;

  void set(HotkeyRegistrationStatus status) {
    state = status;
  }
}

/// Provider for the quick-note [HotkeyRegistrationStatus] state.
final quickNoteHotkeyRegistrationStatusProvider =
    NotifierProvider<
      QuickNoteHotkeyRegistrationStatusController,
      HotkeyRegistrationStatus
    >(QuickNoteHotkeyRegistrationStatusController.new);

/// Notifier holding the [HotkeyRegistrationStatus] for the Snippet-Picker
/// hotkey (ticket 26) — kept fully separate from the other two status
/// providers so a conflict on one action never surfaces as a conflict on
/// another.
class SnippetPickerHotkeyRegistrationStatusController
    extends Notifier<HotkeyRegistrationStatus> {
  @override
  HotkeyRegistrationStatus build() => HotkeyRegistrationStatus.unknown;

  void set(HotkeyRegistrationStatus status) {
    state = status;
  }
}

/// Provider for the Snippet-Picker [HotkeyRegistrationStatus] state.
final snippetPickerHotkeyRegistrationStatusProvider =
    NotifierProvider<
      SnippetPickerHotkeyRegistrationStatusController,
      HotkeyRegistrationStatus
    >(SnippetPickerHotkeyRegistrationStatusController.new);

/// Notifier holding the [HotkeyRegistrationStatus] for the Smart-Mode hotkey
/// (ticket 04 of `.scratch/smart-mode-v2/`) — kept fully separate from the
/// other status providers so a conflict on one action never surfaces as a
/// conflict on another.
class SmartModeHotkeyRegistrationStatusController
    extends Notifier<HotkeyRegistrationStatus> {
  @override
  HotkeyRegistrationStatus build() => HotkeyRegistrationStatus.unknown;

  void set(HotkeyRegistrationStatus status) {
    state = status;
  }
}

/// Provider for the Smart-Mode [HotkeyRegistrationStatus] state.
final smartModeHotkeyRegistrationStatusProvider =
    NotifierProvider<
      SmartModeHotkeyRegistrationStatusController,
      HotkeyRegistrationStatus
    >(SmartModeHotkeyRegistrationStatusController.new);

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
// Per-action state
// ---------------------------------------------------------------------------

/// Registration + held-key state for a single hotkey action. See
/// [HotkeyService._stateFor].
class _ActionHotkeyState {
  HotKey? registeredHotKey;

  /// Whether the action's key is currently considered held down. Set on an
  /// accepted key-down, cleared on key-up (macOS) or once the auto-repeat
  /// window lapses (Windows/Linux, which have no key-up). Used to swallow OS
  /// key-repeat so a held key triggers exactly once.
  bool keyHeld = false;

  /// Timestamp of the most recent key-down event (accepted OR suppressed),
  /// used to bridge the auto-repeat stream on platforms without key-up.
  DateTime? lastKeyDownAt;
}

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

  /// Action identifier for the original, push-to-talk-capable hotkey.
  static const _globalActionId = 'global';

  /// Action identifier for the second, toggle-only quick-note hotkey
  /// (ticket 20). Kept as a plain string identifier — not a hardcoded second
  /// field per piece of state — so a third action (ticket 26) reuses
  /// [_stateFor] without another round of this refactor.
  static const _quickNoteActionId = 'quickNote';

  /// Action identifier for the third, toggle-only Snippet-Picker hotkey
  /// (ticket 26) — reuses [_stateFor] exactly as [_quickNoteActionId] does,
  /// per its own doc comment above.
  static const _snippetPickerActionId = 'snippetPicker';

  /// Action identifier for the fourth, push-to-talk-capable Smart-Mode
  /// hotkey (ticket 04 of `.scratch/smart-mode-v2/`). Unlike
  /// [_quickNoteActionId]/[_snippetPickerActionId] it mirrors
  /// [_globalActionId]'s push-to-talk support (ADR 0008: one extra hotkey,
  /// behaving like the main one, not a lesser toggle-only action).
  static const _smartModeActionId = 'smartMode';

  /// Action identifiers for the two SESSION-SCOPED interactive-snippet keys
  /// (Enter → advance field, Escape → cancel sequence). Unlike every other
  /// action these are never registered from settings: capturing bare Enter
  /// or Escape system-wide while the app merely runs would swallow those
  /// keys in every other application. They exist only between
  /// [registerInteractiveSnippetKeys] and
  /// [unregisterInteractiveSnippetKeys], i.e. exactly while an
  /// interactive-snippet guided sequence is active.
  static const _snippetAdvanceActionId = 'snippetAdvance';
  static const _snippetCancelActionId = 'snippetCancel';

  /// Callback fired when the global hotkey is pressed (key-down).
  VoidCallback? onHotkeyPressed;

  /// Callback fired when the global hotkey is released (key-up).
  ///
  /// Only fires on platforms where [supportsKeyUp] is true (currently macOS).
  VoidCallback? onHotkeyReleased;

  /// Callback fired when hotkey registration fails and the safe default is
  /// used instead.
  ///
  /// The caller (e.g. [WpServiceBootstrap]) should show a localised toast
  /// that prompts the user to re-bind their shortcut in Settings.
  VoidCallback? onRegistrationFailed;

  /// Callback fired when the quick-note hotkey is pressed (key-down).
  ///
  /// Toggle-only — there is no matching "released" callback because this
  /// action never offers push-to-talk (ticket 20).
  VoidCallback? onQuickNoteHotkeyPressed;

  /// Callback fired when the Snippet-Picker hotkey is pressed (key-down).
  ///
  /// One-shot — opens the panel directly, no recording involved, so there is
  /// no "released" callback either (ticket 26).
  VoidCallback? onSnippetPickerHotkeyPressed;

  /// Callback fired when the Smart-Mode hotkey is pressed (key-down).
  VoidCallback? onSmartModeHotkeyPressed;

  /// Callback fired when the Smart-Mode hotkey is released (key-up).
  ///
  /// Only fires where key-up delivery is available for this action — on
  /// macOS via the registrar (same as [onHotkeyReleased]). On Windows/Linux
  /// the shared [_monitor] channel is reserved for the global hotkey (see its
  /// class doc), so the Smart-Mode hotkey is toggle-only there for now — a
  /// documented, accepted platform gap (ticket 04), not a bug.
  VoidCallback? onSmartModeHotkeyReleased;

  /// Whether the current platform can deliver key-up events for global hotkeys.
  ///
  /// macOS gets key-up from the registrar; Windows gets it from the RawInput
  /// [_monitor] (issue #39). Either source enabling key-up makes push-to-talk
  /// available — this is the capability flag the settings toggle reads.
  bool get supportsKeyUp => _registrar.supportsKeyUp || _monitor.supportsKeyUp;

  bool _initialized = false;
  bool _quickNoteInitialized = false;
  bool _snippetPickerInitialized = false;
  bool _smartModeInitialized = false;

  /// Callbacks for the session-scoped interactive-snippet keys. Set by
  /// [registerInteractiveSnippetKeys], cleared by
  /// [unregisterInteractiveSnippetKeys] — never wired from
  /// [WpServiceBootstrap] like the persistent actions, because they only
  /// exist for the lifetime of one guided sequence.
  VoidCallback? _onInteractiveSnippetAdvance;
  VoidCallback? _onInteractiveSnippetCancel;

  /// Monotonic epoch guarding the register/unregister race on the
  /// session-scoped keys: [unregisterInteractiveSnippetKeys] bumps it, and a
  /// registration that completes only AFTER such a bump immediately
  /// unregisters itself again instead of leaking a system-wide Enter/Escape
  /// grab past the end of the sequence.
  int _snippetKeysEpoch = 0;

  /// Per-action registration + held-key state, keyed by action id (see
  /// [_globalActionId], [_quickNoteActionId]). A held key on one action must
  /// never suppress auto-repeat on another, so each action gets its own
  /// bucket rather than sharing the old single set of instance fields.
  final Map<String, _ActionHotkeyState> _actionStates = {};

  _ActionHotkeyState _stateFor(String actionId) =>
      _actionStates.putIfAbsent(actionId, _ActionHotkeyState.new);

  /// Pluggable registrar — defaults to the package singleton; override in
  /// tests by calling [injectRegistrar].
  HotKeyRegistrar _registrar = const _PackageHotKeyRegistrar();

  /// Key-up source for platforms whose registrar is key-down only (Windows
  /// RawInput; issue #39). On macOS/Linux this is a no-op monitor and the
  /// registrar (or nothing) provides key-up. Override in tests via
  /// [injectMonitor].
  KeyboardUpMonitor _monitor = Platform.isWindows
      ? ChannelKeyboardUpMonitor()
      : NoopKeyboardUpMonitor();

  /// How long a key-down stream is treated as OS auto-repeat. Refreshed on
  /// every key-down (including suppressed repeats), so a held key keeps the
  /// window alive; a genuine re-press arrives after a longer gap and is
  /// honoured. Comfortably larger than typical auto-repeat initial delays.
  static const _autoRepeatWindow = Duration(milliseconds: 1200);

  @override
  void build() {
    if (!_isDesktop) return;

    _monitor.onKeyUp = () => _handleKeyUp(_globalActionId, 'Global');

    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (prev, next) {
      final previous = prev?.value;
      final current = next.value;
      if (current == null || previous == null) return;

      final globalChanged =
          previous.hotkeyKey != current.hotkeyKey ||
          previous.hotkeyModifiers != current.hotkeyModifiers ||
          previous.hotkeyEnabled != current.hotkeyEnabled;
      if (globalChanged) {
        if (current.hotkeyEnabled) {
          unawaited(_registerFromSettings(current));
        } else {
          unawaited(_unregisterAction(_globalActionId, stopMonitor: true));
          _log.info('Global hotkey disabled by user');
        }
      }

      _handleSecondaryHotkeySettingsChange(
        prevKey: previous.quickNoteHotkey.quickNoteHotkeyKey,
        key: current.quickNoteHotkey.quickNoteHotkeyKey,
        prevModifiers: previous.quickNoteHotkey.quickNoteHotkeyModifiers,
        modifiers: current.quickNoteHotkey.quickNoteHotkeyModifiers,
        prevEnabled: previous.quickNoteHotkey.quickNoteHotkeyEnabled,
        enabled: current.quickNoteHotkey.quickNoteHotkeyEnabled,
        actionId: _quickNoteActionId,
        label: 'Quick-note',
        register: () => _registerQuickNoteFromSettings(current),
      );

      _handleSecondaryHotkeySettingsChange(
        prevKey: previous.snippetPickerHotkey.snippetPickerHotkeyKey,
        key: current.snippetPickerHotkey.snippetPickerHotkeyKey,
        prevModifiers:
            previous.snippetPickerHotkey.snippetPickerHotkeyModifiers,
        modifiers: current.snippetPickerHotkey.snippetPickerHotkeyModifiers,
        prevEnabled: previous.snippetPickerHotkey.snippetPickerHotkeyEnabled,
        enabled: current.snippetPickerHotkey.snippetPickerHotkeyEnabled,
        actionId: _snippetPickerActionId,
        label: 'Snippet-Picker',
        register: () => _registerSnippetPickerFromSettings(current),
      );

      _handleSecondaryHotkeySettingsChange(
        prevKey: previous.smartModeHotkey.smartModeHotkeyKey,
        key: current.smartModeHotkey.smartModeHotkeyKey,
        prevModifiers: previous.smartModeHotkey.smartModeHotkeyModifiers,
        modifiers: current.smartModeHotkey.smartModeHotkeyModifiers,
        prevEnabled: previous.smartModeHotkey.smartModeHotkeyEnabled,
        enabled: current.smartModeHotkey.smartModeHotkeyEnabled,
        actionId: _smartModeActionId,
        label: 'Smart-Mode',
        register: () => _registerSmartModeFromSettings(current),
      );
    });

    Future.microtask(() async {
      final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
      if (settings.hotkeyEnabled) {
        await _registerFromSettings(settings);
      }
      if (settings.quickNoteHotkey.quickNoteHotkeyEnabled) {
        await _registerQuickNoteFromSettings(settings);
      }
      if (settings.snippetPickerHotkey.snippetPickerHotkeyEnabled) {
        await _registerSnippetPickerFromSettings(settings);
      }
      if (settings.smartModeHotkey.smartModeHotkeyEnabled) {
        await _registerSmartModeFromSettings(settings);
      }
    });
    ref.onDispose(_destroy);
  }

  /// Shared change-detection + register/unregister handling for the three
  /// secondary hotkeys (quick-note, Snippet-Picker, Smart-Mode) inside the
  /// [settingsProvider] listener in [build]. Split out purely to keep
  /// [build]'s cyclomatic complexity under the project's static-analysis
  /// threshold.
  void _handleSecondaryHotkeySettingsChange({
    required String prevKey,
    required String key,
    required String prevModifiers,
    required String modifiers,
    required bool prevEnabled,
    required bool enabled,
    required String actionId,
    required String label,
    required Future<void> Function() register,
  }) {
    final changed =
        prevKey != key || prevModifiers != modifiers || prevEnabled != enabled;
    if (!changed) return;

    if (enabled) {
      unawaited(register());
    } else {
      unawaited(_unregisterAction(actionId, stopMonitor: false));
      _log.info('$label hotkey disabled by user');
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Injects a custom [KeyboardUpMonitor] for unit testing and wires its
  /// key-up callback. Call before [updateHotkey].
  @visibleForTesting
  void injectMonitor(KeyboardUpMonitor monitor) {
    _monitor = monitor;
    _monitor.onKeyUp = () => _handleKeyUp(_globalActionId, 'Global');
  }

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
    await _unregisterAction(_globalActionId, stopMonitor: true);

    final hotKey = HotKey(key: key, modifiers: modifiers);
    _stateFor(_globalActionId).registeredHotKey = hotKey;

    try {
      await _registrar.register(
        hotKey,
        keyDownHandler: (_) => _handleKeyDown(_globalActionId, 'Global'),
        keyUpHandler: _registrar.supportsKeyUp
            ? (_) => _handleKeyUp(_globalActionId, 'Global')
            : null,
      );
      _log.info('Hotkey registered successfully');
      _setStatus(HotkeyRegistrationStatus.success);
      // Start the RawInput key-up monitor for the same combo (Windows; no-op
      // elsewhere) so push-to-talk has a release event (#39).
      await _monitor.start(hotKey);
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

  /// Re-registers the quick-note hotkey (ticket 20) with a new combination.
  ///
  /// Unlike [updateHotkey], a failed registration does **not** fall back to
  /// a safe-default combination — the action simply stays unregistered and
  /// reports [HotkeyRegistrationStatus.conflict]. An unexpectedly-claimed
  /// fallback key that types into a note is worse than a hotkey that does
  /// nothing, and the feature has a full-fledged alternative path (the
  /// Notes area itself).
  Future<void> updateQuickNoteHotkey({
    required LogicalKeyboardKey key,
    List<HotKeyModifier> modifiers = const [],
  }) async {
    if (!_isDesktop) return;
    await _unregisterAction(_quickNoteActionId, stopMonitor: false);

    final hotKey = HotKey(key: key, modifiers: modifiers);
    _stateFor(_quickNoteActionId).registeredHotKey = hotKey;

    try {
      await _registrar.register(
        hotKey,
        keyDownHandler: (_) => _handleKeyDown(_quickNoteActionId, 'QuickNote'),
        // Toggle-only — no push-to-talk for this action, so no keyUpHandler
        // is ever wired, regardless of registrar capability.
      );
      _log.info('Quick-note hotkey registered successfully');
      _setQuickNoteStatus(HotkeyRegistrationStatus.success);
      // No monitor.start() — the monitor is a single shared native channel
      // (Windows RawInput) and this toggle-only action never needs key-up.
      // Starting it here would steal the global hotkey's release watch.
    } on Object catch (e) {
      _setQuickNoteStatus(HotkeyRegistrationStatus.conflict);
      _stateFor(_quickNoteActionId).registeredHotKey = null;
      final keyCode = key.keyId.toRadixString(16);
      _log.warning(
        'Failed to register quick-note hotkey (key=0x$keyCode): $e '
        '— staying unregistered, no safe-default fallback',
      );
    }
  }

  /// Re-registers the Snippet-Picker hotkey (ticket 26) with a new
  /// combination.
  ///
  /// Same no-safe-default-fallback contract as [updateQuickNoteHotkey] and
  /// for the same reason: an unexpectedly-claimed fallback key opening the
  /// picker (or worse, typing into whatever has focus) is worse than a key
  /// that does nothing, and the picker has a full-fledged alternative path
  /// (the spoken trigger word).
  Future<void> updateSnippetPickerHotkey({
    required LogicalKeyboardKey key,
    List<HotKeyModifier> modifiers = const [],
  }) async {
    if (!_isDesktop) return;
    await _unregisterAction(_snippetPickerActionId, stopMonitor: false);

    final hotKey = HotKey(key: key, modifiers: modifiers);
    _stateFor(_snippetPickerActionId).registeredHotKey = hotKey;

    try {
      await _registrar.register(
        hotKey,
        keyDownHandler: (_) =>
            _handleKeyDown(_snippetPickerActionId, 'SnippetPicker'),
        // Toggle-only/one-shot — no push-to-talk for this action, so no
        // keyUpHandler is ever wired, regardless of registrar capability.
      );
      _log.info('Snippet-Picker hotkey registered successfully');
      _setSnippetPickerStatus(HotkeyRegistrationStatus.success);
      // No monitor.start() — same reasoning as updateQuickNoteHotkey: the
      // shared monitor is a single native channel and this action never
      // needs key-up.
    } on Object catch (e) {
      _setSnippetPickerStatus(HotkeyRegistrationStatus.conflict);
      _stateFor(_snippetPickerActionId).registeredHotKey = null;
      final keyCode = key.keyId.toRadixString(16);
      _log.warning(
        'Failed to register Snippet-Picker hotkey (key=0x$keyCode): $e '
        '— staying unregistered, no safe-default fallback',
      );
    }
  }

  /// Re-registers the Smart-Mode hotkey (ticket 04) with a new combination.
  ///
  /// Unlike [updateQuickNoteHotkey]/[updateSnippetPickerHotkey] this wires a
  /// key-up handler wherever the registrar supports it (macOS today — see
  /// [HotKeyRegistrar.supportsKeyUp]), giving push-to-talk parity with
  /// [updateHotkey]. On platforms without registrar key-up (Windows/Linux)
  /// this stays toggle-only, since the shared [_monitor] RawInput channel is
  /// reserved for the global action — a documented, accepted gap for this
  /// ticket, not a silent omission.
  ///
  /// Same no-safe-default-fallback contract as the other two secondary
  /// hotkeys and for the same reason: an unexpectedly-claimed fallback key
  /// triggering an unwanted Smart-Mode recording is worse than a hotkey that
  /// does nothing.
  Future<void> updateSmartModeHotkey({
    required LogicalKeyboardKey key,
    List<HotKeyModifier> modifiers = const [],
  }) async {
    if (!_isDesktop) return;
    await _unregisterAction(_smartModeActionId, stopMonitor: false);

    final hotKey = HotKey(key: key, modifiers: modifiers);
    _stateFor(_smartModeActionId).registeredHotKey = hotKey;

    try {
      await _registrar.register(
        hotKey,
        keyDownHandler: (_) => _handleKeyDown(_smartModeActionId, 'SmartMode'),
        keyUpHandler: _registrar.supportsKeyUp
            ? (_) => _handleKeyUp(_smartModeActionId, 'SmartMode')
            : null,
      );
      _log.info('Smart-Mode hotkey registered successfully');
      _setSmartModeStatus(HotkeyRegistrationStatus.success);
    } on Object catch (e) {
      _setSmartModeStatus(HotkeyRegistrationStatus.conflict);
      _stateFor(_smartModeActionId).registeredHotKey = null;
      final keyCode = key.keyId.toRadixString(16);
      _log.warning(
        'Failed to register Smart-Mode hotkey (key=0x$keyCode): $e '
        '— staying unregistered, no safe-default fallback',
      );
    }
  }

  /// Registers the session-scoped interactive-snippet keys: bare **Enter**
  /// (advance to the next field) and bare **Escape** (cancel the sequence).
  ///
  /// MUST only be called while an interactive-snippet guided sequence is
  /// starting, and MUST be paired with [unregisterInteractiveSnippetKeys] on
  /// every exit path of that sequence (finish, cancel, abort) — a bare
  /// system-wide Enter grab left behind would swallow Enter in every other
  /// application. `InteractiveSnippetController` owns that pairing; this
  /// service additionally unregisters both keys in [_destroy] as a last
  /// line of defence.
  ///
  /// Failure contract mirrors the secondary hotkeys: a key that cannot be
  /// registered (already claimed elsewhere) is logged and simply stays
  /// unavailable — the sequence continues, the main hotkey path still
  /// advances fields. Each key registers independently, so an Enter
  /// conflict does not take Escape down with it (or vice versa).
  Future<void> registerInteractiveSnippetKeys({
    required VoidCallback onAdvance,
    required VoidCallback onCancel,
  }) async {
    if (!_isDesktop) return;
    // Claim this sequence's epoch SYNCHRONOUSLY, before the cleanup await
    // below. Capturing after an await would open a race:
    // [unregisterInteractiveSnippetKeys] could land during that await, and
    // the epoch captured afterwards would match the post-bump value — making
    // this already-ended sequence look current and letting its key grabs
    // survive. ONE epoch for both keys: if the sequence ends while either
    // registration is still in flight, both key registrations see the stale
    // epoch — the pending one undoes itself, the not-yet-started one is
    // skipped.
    final epoch = ++_snippetKeysEpoch;
    // Idempotent: drop any previous session's registration first.
    await _unregisterInteractiveSnippetActions();
    if (epoch != _snippetKeysEpoch) {
      // The sequence was ended (or replaced) while the cleanup above was in
      // flight — don't resurrect the callbacks or register any key.
      return;
    }
    _onInteractiveSnippetAdvance = onAdvance;
    _onInteractiveSnippetCancel = onCancel;
    await _registerSessionKey(
      _snippetAdvanceActionId,
      LogicalKeyboardKey.enter,
      'Snippet-advance (Enter)',
      epoch,
    );
    await _registerSessionKey(
      _snippetCancelActionId,
      LogicalKeyboardKey.escape,
      'Snippet-cancel (Escape)',
      epoch,
    );
  }

  /// Removes the session-scoped interactive-snippet keys (see
  /// [registerInteractiveSnippetKeys]). Safe to call when nothing is
  /// registered.
  Future<void> unregisterInteractiveSnippetKeys() async {
    _snippetKeysEpoch++;
    _onInteractiveSnippetAdvance = null;
    _onInteractiveSnippetCancel = null;
    await _unregisterInteractiveSnippetActions();
  }

  /// Drops both session-scoped key registrations WITHOUT bumping the epoch —
  /// the shared cleanup between [unregisterInteractiveSnippetKeys] (which
  /// bumps) and [registerInteractiveSnippetKeys] (which has already claimed
  /// its own fresh epoch before calling this).
  Future<void> _unregisterInteractiveSnippetActions() async {
    await _unregisterAction(_snippetAdvanceActionId, stopMonitor: false);
    await _unregisterAction(_snippetCancelActionId, stopMonitor: false);
  }

  /// Registers one session-scoped key for [actionId]. Stores the [HotKey]
  /// only after the registrar call succeeded (unlike the settings-driven
  /// `update*` methods, which store first): if an unregister raced past the
  /// pending call, nothing must be left behind that [_unregisterAction]
  /// already missed — the epoch check below closes exactly that window.
  Future<void> _registerSessionKey(
    String actionId,
    LogicalKeyboardKey key,
    String label,
    int epoch,
  ) async {
    if (epoch != _snippetKeysEpoch) {
      // The sequence already ended before this key's turn came — skip.
      return;
    }
    final hotKey = HotKey(key: key);
    try {
      await _registrar.register(
        hotKey,
        keyDownHandler: (_) => _handleKeyDown(actionId, label),
        // Where key-up is available (macOS registrar), clear the held state
        // so a quick successive press within the auto-repeat window is not
        // swallowed as OS key-repeat.
        keyUpHandler: _registrar.supportsKeyUp
            ? (_) => _handleKeyUp(actionId, label)
            : null,
      );
      if (epoch != _snippetKeysEpoch) {
        // The sequence ended while the registration was in flight — undo it
        // immediately instead of leaking a system-wide key grab.
        _log.info('$label registration outlived its sequence — undoing');
        try {
          await _registrar.unregister(hotKey);
        } on Object catch (e) {
          _log.debug('$label late unregister failed (non-fatal): $e');
        }
        return;
      }
      _stateFor(actionId).registeredHotKey = hotKey;
      _log.info('$label registered for interactive-snippet sequence');
    } on Object catch (e) {
      _stateFor(actionId).registeredHotKey = null;
      _log.warning(
        'Failed to register $label: $e — the sequence continues without it',
      );
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

  /// Shared implementation behind [_registerQuickNoteFromSettings],
  /// [_registerSnippetPickerFromSettings] and [_registerSmartModeFromSettings]
  /// — all three secondary hotkeys share the same brand-new-settings-key
  /// contract: no legacy DB with a pre-fix corrupted value to self-heal, and
  /// no safe-default fallback (an unexpectedly-claimed fallback key doing the
  /// wrong thing is worse than a hotkey that does nothing).
  Future<void> _registerSecondaryHotkeyFromSettings({
    required String key,
    required String modifiers,
    required Future<void> Function({
      required LogicalKeyboardKey key,
      List<HotKeyModifier> modifiers,
    })
    update,
    required void Function() markInitialized,
    required void Function(HotkeyRegistrationStatus) setStatus,
    required String label,
  }) async {
    try {
      await update(
        key: resolveKey(key),
        modifiers: resolveModifiers(modifiers),
      );
      markInitialized();
      _log.info(
        '$label hotkey synced from settings: '
        '${formatHotkeyShortcut(modifiers, key)}',
      );
    } on Object catch (e) {
      setStatus(HotkeyRegistrationStatus.conflict);
      _log.warning('Failed to register $label hotkey: $e');
    }
  }

  /// Sibling of [_registerFromSettings] for the quick-note action (ticket 20).
  Future<void> _registerQuickNoteFromSettings(AppSettings settings) {
    final quickNote = settings.quickNoteHotkey;
    return _registerSecondaryHotkeyFromSettings(
      key: quickNote.quickNoteHotkeyKey,
      modifiers: quickNote.quickNoteHotkeyModifiers,
      update: updateQuickNoteHotkey,
      markInitialized: () => _quickNoteInitialized = true,
      setStatus: _setQuickNoteStatus,
      label: 'Quick-note',
    );
  }

  /// Sibling of [_registerFromSettings] for the Snippet-Picker action
  /// (ticket 26).
  Future<void> _registerSnippetPickerFromSettings(AppSettings settings) {
    final snippetPicker = settings.snippetPickerHotkey;
    return _registerSecondaryHotkeyFromSettings(
      key: snippetPicker.snippetPickerHotkeyKey,
      modifiers: snippetPicker.snippetPickerHotkeyModifiers,
      update: updateSnippetPickerHotkey,
      markInitialized: () => _snippetPickerInitialized = true,
      setStatus: _setSnippetPickerStatus,
      label: 'Snippet-Picker',
    );
  }

  /// Sibling of [_registerFromSettings] for the Smart-Mode action
  /// (ticket 04).
  Future<void> _registerSmartModeFromSettings(AppSettings settings) {
    final smartMode = settings.smartModeHotkey;
    return _registerSecondaryHotkeyFromSettings(
      key: smartMode.smartModeHotkeyKey,
      modifiers: smartMode.smartModeHotkeyModifiers,
      update: updateSmartModeHotkey,
      markInitialized: () => _smartModeInitialized = true,
      setStatus: _setSmartModeStatus,
      label: 'Smart-Mode',
    );
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
    } on Object catch (e) {
      _log.debug('Hotkey status update skipped (standalone test instance): $e');
    }
  }

  /// Quick-note sibling of [_setStatus] — same standalone-test guard.
  void _setQuickNoteStatus(HotkeyRegistrationStatus status) {
    try {
      ref.read(quickNoteHotkeyRegistrationStatusProvider.notifier).set(status);
    } on Object catch (e) {
      _log.debug(
        'Quick-note hotkey status update skipped (standalone test instance): $e',
      );
    }
  }

  /// Snippet-Picker sibling of [_setStatus] — same standalone-test guard.
  void _setSnippetPickerStatus(HotkeyRegistrationStatus status) {
    try {
      ref
          .read(snippetPickerHotkeyRegistrationStatusProvider.notifier)
          .set(status);
    } on Object catch (e) {
      _log.debug(
        'Snippet-Picker hotkey status update skipped (standalone test instance): $e',
      );
    }
  }

  /// Smart-Mode sibling of [_setStatus] — same standalone-test guard.
  void _setSmartModeStatus(HotkeyRegistrationStatus status) {
    try {
      ref.read(smartModeHotkeyRegistrationStatusProvider.notifier).set(status);
    } on Object catch (e) {
      _log.debug(
        'Smart-Mode hotkey status update skipped (standalone test instance): $e',
      );
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
  ///
  /// Only ever used for the global action — the quick-note action never
  /// falls back (see [updateQuickNoteHotkey]).
  Future<void> _registerSafeDefault() async {
    final fallback = safeDefaultHotKey;
    _stateFor(_globalActionId).registeredHotKey = fallback;
    try {
      await _registrar.register(
        fallback,
        keyDownHandler: (_) => _handleKeyDown(_globalActionId, 'Safe-default'),
        keyUpHandler: _registrar.supportsKeyUp
            ? (_) => _handleKeyUp(_globalActionId, 'Safe-default')
            : null,
      );
      _log.info(
        'Safe-default hotkey registered successfully ($safeDefaultHotKeyLabel)',
      );
      _initialized = true;
      await _monitor.start(fallback);
      onRegistrationFailed?.call();
    } on Object catch (e) {
      // Even the fallback failed — log and leave the service in a non-crashing
      // degraded state.
      _log.error('Safe-default hotkey also failed to register: $e');
      _stateFor(_globalActionId).registeredHotKey = null;
    }
  }

  /// Handles a hotkey key-down, swallowing OS auto-repeat so a held key fires
  /// exactly once. State is tracked per [actionId] (see [_stateFor]) so a
  /// held key on one action never suppresses auto-repeat on another.
  ///
  /// On macOS (key-up available) a held key is detected directly via
  /// `keyHeld`, cleared on key-up. On Windows/Linux (no key-up) the
  /// [_autoRepeatWindow] sliding window — refreshed on every key-down
  /// including suppressed repeats — bridges the repeat stream; a genuine
  /// re-press lands after a longer gap and is honoured. Without this, holding
  /// the key in toggle mode rapidly flips start/stop and wedges the
  /// recording state.
  void _handleKeyDown(String actionId, String label) {
    final state = _stateFor(actionId);
    final now = DateTime.now();
    final last = state.lastKeyDownAt;
    state.lastKeyDownAt = now;
    final isAutoRepeat =
        state.keyHeld &&
        last != null &&
        now.difference(last) < _autoRepeatWindow;
    if (isAutoRepeat) {
      _log.debug('$label hotkey auto-repeat ignored (key held)');
      return;
    }
    state.keyHeld = true;
    _log.info('$label hotkey pressed');
    if (actionId == _globalActionId) {
      // Stamp t₀ for hotkey→overlay latency BEFORE dispatching so the mark
      // captures the earliest possible Dart-layer moment of this event.
      // Counterpart: PerfMarkers.markOverlayShown() in FloatingOverlayService.
      PerfMarkers.instance.markHotkeyPressed();
      onHotkeyPressed?.call();
      // Arm the RawInput release-watch (Windows): RegisterHotKey hides the
      // hotkey key's DOWN from RawInput, so the native monitor snapshots the
      // held key now and reports its release. No-op on other platforms (#39).
      // Only the global action uses the shared monitor.
      unawaited(_monitor.armRelease());
    } else if (actionId == _quickNoteActionId) {
      // Same t₀ stamp as the global action — the quick-note action also
      // drives the recording overlay (FloatingOverlayService is not
      // target-aware), so it needs a fresh mark for the same
      // markOverlayShown() counterpart to report a meaningful latency
      // instead of a stale/null value from an earlier global press.
      PerfMarkers.instance.markHotkeyPressed();
      onQuickNoteHotkeyPressed?.call();
    } else if (actionId == _snippetPickerActionId) {
      // No perf mark here — this action never drives the recording overlay
      // (it doesn't start a recording at all, ticket 26), so the
      // hotkey→overlay latency marker doesn't apply.
      onSnippetPickerHotkeyPressed?.call();
    } else if (actionId == _smartModeActionId) {
      // Same t₀ stamp rationale as the quick-note action — this action also
      // drives the recording overlay.
      PerfMarkers.instance.markHotkeyPressed();
      onSmartModeHotkeyPressed?.call();
    } else if (actionId == _snippetAdvanceActionId) {
      // No perf mark — the field advance ends a recording rather than
      // starting the hotkey→overlay hot path this marker measures.
      _onInteractiveSnippetAdvance?.call();
    } else if (actionId == _snippetCancelActionId) {
      _onInteractiveSnippetCancel?.call();
    }
  }

  /// Handles a hotkey key-up (macOS only; global and Smart-Mode actions only
  /// — the quick-note and Snippet-Picker actions never wire a keyUpHandler).
  /// Clears the held state so the next press is honoured immediately, and
  /// forwards to [onHotkeyReleased]/[onSmartModeHotkeyReleased]. The
  /// session-scoped interactive-snippet keys also land here purely for the
  /// held-state clearing — they have no released callback.
  void _handleKeyUp(String actionId, String label) {
    final state = _stateFor(actionId);
    // Ignore a key-up with no matching key-down. The Windows RawInput monitor
    // (#39) observes the bare watched key globally, so it can see the key
    // released without modifiers — a case where RegisterHotKey never fired a
    // down. Without this guard a stray up would drive onHotkeyReleased (and the
    // push-to-talk trigger handler, which assumes a preceding press) spuriously.
    if (!state.keyHeld) return;
    state.keyHeld = false;
    _log.info('$label hotkey released');
    if (actionId == _globalActionId) {
      onHotkeyReleased?.call();
    } else if (actionId == _smartModeActionId) {
      onSmartModeHotkeyReleased?.call();
    }
  }

  /// Unregisters [actionId]'s hotkey and resets its held-key state. The
  /// shared [_monitor] is only ever touched for the global action
  /// ([stopMonitor]) — the quick-note action never starts it, so stopping it
  /// on that action's behalf would wrongly cut off the global hotkey's
  /// release watch.
  Future<void> _unregisterAction(
    String actionId, {
    required bool stopMonitor,
  }) async {
    final state = _stateFor(actionId);
    if (state.registeredHotKey != null) {
      try {
        await _registrar.unregister(state.registeredHotKey!);
      } on Object catch (e) {
        _log.debug('Hotkey unregister failed during cleanup (non-fatal): $e');
      }
      state.registeredHotKey = null;
    }
    if (stopMonitor) {
      await _monitor.stop();
    }
    // Reset auto-repeat state so a fresh registration starts clean.
    state.keyHeld = false;
    state.lastKeyDownAt = null;
  }

  Future<void> _destroy() async {
    if (_initialized) {
      await _unregisterAction(_globalActionId, stopMonitor: true);
      _log.info('Global hotkey unregistered');
    }
    if (_quickNoteInitialized) {
      await _unregisterAction(_quickNoteActionId, stopMonitor: false);
      _log.info('Quick-note hotkey unregistered');
    }
    if (_snippetPickerInitialized) {
      await _unregisterAction(_snippetPickerActionId, stopMonitor: false);
      _log.info('Snippet-Picker hotkey unregistered');
    }
    if (_smartModeInitialized) {
      await _unregisterAction(_smartModeActionId, stopMonitor: false);
      _log.info('Smart-Mode hotkey unregistered');
    }
    // Last line of defence for the session-scoped interactive-snippet keys:
    // normally InteractiveSnippetController unregisters them on every
    // sequence exit path, but a teardown mid-sequence must not leak a
    // system-wide Enter/Escape grab. No-op when nothing is registered.
    await unregisterInteractiveSnippetKeys();
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
