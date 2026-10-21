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

import 'dart:ui' show Locale;

import '../core/config/settings_labels.dart';
import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/perf_instrumentation.dart';
import 'hotkey_key_resolver.dart';
import 'profile_hotkey_plan.dart';
import 'prompt_display_arbiter.dart';
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
/// - [waylandUnbound]: Linux Wayland only — the hotkey is registered, but the
///   desktop has not bound it through the GlobalShortcuts portal, so it does
///   not fire in other apps ([waylandHotkeyBindingProvider] says why). Main
///   hotkey only; UI offers a reconnect and the `--toggle` fallback.
enum HotkeyRegistrationStatus { unknown, success, conflict, waylandUnbound }

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

/// Notifier holding the main hotkey's latest [WaylandHotkeyBinding] — the
/// reason behind [HotkeyRegistrationStatus.waylandUnbound]. Written by
/// [HotkeyService].
class WaylandHotkeyBindingController extends Notifier<WaylandHotkeyBinding> {
  @override
  WaylandHotkeyBinding build() => WaylandHotkeyBinding.notApplicable;

  void set(WaylandHotkeyBinding binding) {
    state = binding;
  }
}

/// Provider for the main hotkey's [WaylandHotkeyBinding].
final waylandHotkeyBindingProvider =
    NotifierProvider<WaylandHotkeyBindingController, WaylandHotkeyBinding>(
      WaylandHotkeyBindingController.new,
    );

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

/// Notifier holding the [HotkeyRegistrationStatus] for the "next favorite
/// language" hotkey. Kept separate so a conflict there never shows up on the
/// other actions.
class LanguageCycleHotkeyRegistrationStatusController
    extends Notifier<HotkeyRegistrationStatus> {
  @override
  HotkeyRegistrationStatus build() => HotkeyRegistrationStatus.unknown;

  void set(HotkeyRegistrationStatus status) {
    state = status;
  }
}

/// Provider for the "next favorite language" [HotkeyRegistrationStatus].
final languageCycleHotkeyRegistrationStatusProvider =
    NotifierProvider<
      LanguageCycleHotkeyRegistrationStatusController,
      HotkeyRegistrationStatus
    >(LanguageCycleHotkeyRegistrationStatusController.new);

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

/// Notifier holding the [HotkeyRegistrationStatus] for the edit-selection
/// hotkey (`.scratch/voice-selection-edit/`) — separate from the other
/// status providers for the same reason as the Smart-Mode one.
class SelectionEditHotkeyRegistrationStatusController
    extends Notifier<HotkeyRegistrationStatus> {
  @override
  HotkeyRegistrationStatus build() => HotkeyRegistrationStatus.unknown;

  void set(HotkeyRegistrationStatus status) {
    state = status;
  }
}

/// Provider for the edit-selection [HotkeyRegistrationStatus] state.
final selectionEditHotkeyRegistrationStatusProvider =
    NotifierProvider<
      SelectionEditHotkeyRegistrationStatusController,
      HotkeyRegistrationStatus
    >(SelectionEditHotkeyRegistrationStatusController.new);

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

/// [safeDefaultHotKey] in the settings storage format (see
/// `hotkey_key_resolver.dart`), so settings and dock can display it.
const safeDefaultHotkeyKey = 'Space';
String get safeDefaultHotkeyModifiers =>
    Platform.isMacOS ? 'shift+meta' : 'ctrl+shift';

/// True while the global action listens on [safeDefaultHotKey] because the
/// configured combination could not be registered. Settings and dock then
/// show the fallback instead of the configured hotkey, and the app tells the
/// user once with a toast.
class GlobalHotkeyFallbackController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool active) {
    state = active;
  }
}

final globalHotkeyFallbackActiveProvider =
    NotifierProvider<GlobalHotkeyFallbackController, bool>(
      GlobalHotkeyFallbackController.new,
    );

/// The global hotkey every surface should name (dock, overlay hint,
/// onboarding, settings): the safe default while it stands in for a taken
/// combination, else the configured one. [display] is the stored display
/// override of the key (empty for the safe default).
({String key, String modifiers, String display}) activeGlobalHotkey(
  AppSettings settings, {
  required bool fallback,
}) => fallback
    ? (
        key: safeDefaultHotkeyKey,
        modifiers: safeDefaultHotkeyModifiers,
        display: '',
      )
    : (
        key: settings.hotkeyKey,
        modifiers: settings.hotkeyModifiers,
        display: settings.hotkey.hotkeyKeyDisplay,
      );

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
/// Maps the stored cancel-dictation key name (see
/// `cancelDictationKeyChoices`) to its key. Unknown names fall back to Escape.
LogicalKeyboardKey logicalKeyForCancelDictation(String name) => switch (name) {
  'f12' => LogicalKeyboardKey.f12,
  _ => LogicalKeyboardKey.escape,
};

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

  /// Action identifier for the toggle-only "next favorite language" hotkey.
  /// Must match the action id in `hotkey_flow.dart`'s binding list.
  static const _languageCycleActionId = 'languageCycle';

  /// Prefix of the per-profile action ids (see [profileHotkeyActionId]).
  static const _profileActionPrefix = 'profile:';

  /// Action identifier for the fourth, push-to-talk-capable Smart-Mode
  /// hotkey (ticket 04 of `.scratch/smart-mode-v2/`). Unlike
  /// [_quickNoteActionId]/[_snippetPickerActionId] it mirrors
  /// [_globalActionId]'s push-to-talk support (ADR 0008: one extra hotkey,
  /// behaving like the main one, not a lesser toggle-only action).
  static const _smartModeActionId = 'smartMode';

  /// Action identifier for the edit-selection hotkey
  /// (`.scratch/voice-selection-edit/`) — push-to-talk-capable exactly like
  /// [_smartModeActionId] (macOS registrar key-up; toggle elsewhere).
  static const _selectionEditActionId = 'selectionEdit';

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

  /// Session-scoped bare **Escape**, active only while a normal (non-
  /// snippet) dictation is recording/transcribing/refining — registered by
  /// [registerCancelDictationKey], unregistered by
  /// [unregisterCancelDictationKey]. Same "system-wide grab only while
  /// truly needed" contract as the snippet keys above; `FloatingOverlayService`
  /// owns the pairing.
  static const _cancelDictationActionId = 'cancelDictation';

  /// Callback fired when a profile hotkey is pressed (key-down), with the
  /// profile's id. The profile is applied persistently by the caller.
  void Function(String profileId)? onProfileHotkeyPressed;

  /// Profile hotkeys currently registered: action id to the combination's
  /// signature (see [ProfileHotkeyEntry.signature]).
  final Map<String, String> _profileRegistrations = {};

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

  /// Fired when the "next favorite language" hotkey is pressed. The bootstrap
  /// wires it to the language switch (cycle + feedback). One-shot.
  VoidCallback? onLanguageCycleHotkeyPressed;

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

  /// Callback fired when the edit-selection hotkey is pressed (key-down).
  VoidCallback? onSelectionEditHotkeyPressed;

  /// Callback fired when the edit-selection hotkey is released (key-up) —
  /// same platform availability as [onSmartModeHotkeyReleased].
  VoidCallback? onSelectionEditHotkeyReleased;

  /// Whether the current platform can deliver key-up events for global hotkeys.
  ///
  /// macOS gets key-up from the registrar; Windows gets it from the RawInput
  /// [_monitor] (issue #39). Either source enabling key-up makes push-to-talk
  /// available — this is the capability flag the settings toggle reads.
  bool get supportsKeyUp => _registrar.supportsKeyUp || _monitor.supportsKeyUp;

  /// Whether push-to-talk rests solely on the experimental Linux key-up
  /// monitor (handy-catchup/09) — the settings UI marks the option then.
  bool get keyUpExperimental =>
      !_registrar.supportsKeyUp &&
      _monitor.supportsKeyUp &&
      _monitor.experimental;

  bool _initialized = false;
  bool _quickNoteInitialized = false;
  bool _snippetPickerInitialized = false;
  bool _languageCycleInitialized = false;
  bool _smartModeInitialized = false;
  bool _selectionEditInitialized = false;

  /// Callbacks for the session-scoped interactive-snippet keys. Set by
  /// [registerInteractiveSnippetKeys], cleared by
  /// [unregisterInteractiveSnippetKeys] — never wired from
  /// [WpServiceBootstrap] like the persistent actions, because they only
  /// exist for the lifetime of one guided sequence.
  VoidCallback? _onInteractiveSnippetAdvance;
  VoidCallback? _onInteractiveSnippetCancel;
  VoidCallback? _onCancelDictation;

  /// Monotonic epoch guarding the register/unregister race on the
  /// session-scoped keys: [unregisterInteractiveSnippetKeys] bumps it, and a
  /// registration that completes only AFTER such a bump immediately
  /// unregisters itself again instead of leaking a system-wide Enter/Escape
  /// grab past the end of the sequence.
  int _snippetKeysEpoch = 0;

  /// Same epoch pattern as [_snippetKeysEpoch], for the independent
  /// cancel-dictation key — kept separate so a snippet sequence starting or
  /// ending never races the normal-dictation registration (and vice versa).
  int _cancelDictationEpoch = 0;

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
  /// RawInput, issue #39; Linux XInput2/GlobalShortcuts portal, experimental,
  /// handy-catchup/09). On macOS this is a no-op monitor and the registrar
  /// provides key-up. Override in tests via [injectMonitor].
  KeyboardUpMonitor _monitor = (Platform.isWindows || Platform.isLinux)
      ? ChannelKeyboardUpMonitor()
      : NoopKeyboardUpMonitor();

  /// How long a key-down stream is treated as OS auto-repeat. Refreshed on
  /// every key-down (including suppressed repeats), so a held key keeps the
  /// window alive; a genuine re-press arrives after a longer gap and is
  /// honoured. Comfortably larger than typical auto-repeat initial delays.
  static const _autoRepeatWindow = Duration(milliseconds: 1200);

  /// Shared nudge window. Read in [build]; null until the notifier is built.
  PromptDisplayArbiter? _promptArbiter;

  @override
  void build() {
    _promptArbiter = ref.read(promptDisplayArbiterProvider);
    if (!_isDesktop) return;

    _wireMonitor();

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
          _setFallbackActive(false);
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
        prevKey: previous.stt.languageCycleHotkeyKey,
        key: current.stt.languageCycleHotkeyKey,
        prevModifiers: previous.stt.languageCycleHotkeyModifiers,
        modifiers: current.stt.languageCycleHotkeyModifiers,
        prevEnabled: previous.stt.languageCycleHotkeyEnabled,
        enabled: current.stt.languageCycleHotkeyEnabled,
        actionId: _languageCycleActionId,
        label: 'Language-cycle',
        register: () => _registerLanguageCycleFromSettings(current),
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

      _handleSecondaryHotkeySettingsChange(
        prevKey: previous.selectionEditHotkey.selectionEditHotkeyKey,
        key: current.selectionEditHotkey.selectionEditHotkeyKey,
        prevModifiers:
            previous.selectionEditHotkey.selectionEditHotkeyModifiers,
        modifiers: current.selectionEditHotkey.selectionEditHotkeyModifiers,
        prevEnabled: previous.selectionEditHotkey.selectionEditHotkeyEnabled,
        enabled: current.selectionEditHotkey.selectionEditHotkeyEnabled,
        actionId: _selectionEditActionId,
        label: 'Edit-selection',
        register: () => _registerSelectionEditFromSettings(current),
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
      if (settings.stt.languageCycleHotkeyEnabled) {
        await _registerLanguageCycleFromSettings(settings);
      }
      if (settings.smartModeHotkey.smartModeHotkeyEnabled) {
        await _registerSmartModeFromSettings(settings);
      }
      if (settings.selectionEditHotkey.selectionEditHotkeyEnabled) {
        await _registerSelectionEditFromSettings(settings);
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
    _wireMonitor();
  }

  /// Routes the monitor's events into the global action. Key-down only
  /// arrives from the Linux portal path; a press the X11 grab reports as well
  /// is deduplicated by [_handleKeyDown]'s held-key guard.
  void _wireMonitor() {
    _monitor.onKeyUp = () => _handleKeyUp(_globalActionId, 'Global');
    _monitor.onKeyDown = () => _handleKeyDown(_globalActionId, 'Global');
    _monitor.onWaylandBindingChanged = _applyWaylandBinding;
  }

  /// Starts the key-up monitor for the global [hotKey]. On Linux Wayland this
  /// also asks the desktop to bind it (GlobalShortcuts portal), under the
  /// localized name the desktop shows in its dialog.
  Future<void> _startMonitor(HotKey hotKey) async {
    await _monitor.start(
      hotKey,
      description: _resolveL10n().waylandHotkeyPortalDescription,
    );
    _applyWaylandBinding();
  }

  /// Asks the desktop again to bind the global hotkey (Linux Wayland, after
  /// the portal dialog was declined or the app ID was missing). No-op without
  /// a registered global hotkey.
  Future<void> reconnectWaylandHotkey() async {
    final hotKey = _stateFor(_globalActionId).registeredHotKey;
    if (hotKey == null) return;
    await _startMonitor(hotKey);
  }

  /// Mirrors the monitor's [WaylandHotkeyBinding] into the main hotkey's
  /// status: an unbound Wayland hotkey is registered but does not fire in
  /// other apps, so it must not read as [HotkeyRegistrationStatus.success].
  /// A conflict (or no attempt yet) is never overwritten.
  void _applyWaylandBinding() {
    final binding = _monitor.waylandBinding;
    try {
      ref.read(waylandHotkeyBindingProvider.notifier).set(binding);
      final current = ref.read(hotkeyRegistrationStatusProvider);
      if (current != HotkeyRegistrationStatus.success &&
          current != HotkeyRegistrationStatus.waylandUnbound) {
        return;
      }
    } on Object catch (e) {
      _log.debug('Wayland binding update skipped (standalone test): $e');
      return;
    }
    _setStatus(
      binding.isUnbound
          ? HotkeyRegistrationStatus.waylandUnbound
          : HotkeyRegistrationStatus.success,
    );
  }

  /// The app's own language setting, falling back to English (same rule as
  /// the recording orchestrator's native texts).
  L10n _resolveL10n() {
    String? localeCode;
    try {
      localeCode = ref.read(settingsProvider).value?.locale;
    } on Object catch (e) {
      _log.debug('No settings for the portal text (standalone test): $e');
    }
    if (localeCode != null) {
      try {
        return lookupL10n(Locale(localeCode));
      } on Object catch (e) {
        _log.debug('Unsupported locale "$localeCode", falling back to en: $e');
      }
    }
    return lookupL10n(const Locale('en'));
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
      _setFallbackActive(false);
      // Start the RawInput key-up monitor for the same combo (Windows; no-op
      // elsewhere) so push-to-talk has a release event (#39).
      await _startMonitor(hotKey);
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
  }) => _registerToggleOnlyAction(
    actionId: _quickNoteActionId,
    handlerLabel: 'QuickNote',
    logName: 'Quick-note',
    key: key,
    modifiers: modifiers,
    setStatus: _setQuickNoteStatus,
  );

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
  }) => _registerToggleOnlyAction(
    actionId: _snippetPickerActionId,
    handlerLabel: 'SnippetPicker',
    logName: 'Snippet-Picker',
    key: key,
    modifiers: modifiers,
    setStatus: _setSnippetPickerStatus,
  );

  /// Shared registration for the toggle-only one-shot actions (quick-note,
  /// Snippet-Picker, language cycle): no key-up is ever wired, no monitor is
  /// started, and a failed registration stays unregistered rather than falling
  /// back to a safe default.
  Future<void> _registerToggleOnlyAction({
    required String actionId,
    required String handlerLabel,
    required String logName,
    required LogicalKeyboardKey key,
    required List<HotKeyModifier> modifiers,
    required void Function(HotkeyRegistrationStatus) setStatus,
  }) async {
    if (!_isDesktop) return;
    await _unregisterAction(actionId, stopMonitor: false);

    final hotKey = HotKey(key: key, modifiers: modifiers);
    _stateFor(actionId).registeredHotKey = hotKey;

    try {
      await _registrar.register(
        hotKey,
        keyDownHandler: (_) => _handleKeyDown(actionId, handlerLabel),
      );
      _log.info('$logName hotkey registered successfully');
      setStatus(HotkeyRegistrationStatus.success);
    } on Object catch (e) {
      setStatus(HotkeyRegistrationStatus.conflict);
      _stateFor(actionId).registeredHotKey = null;
      final keyCode = key.keyId.toRadixString(16);
      _log.warning(
        'Failed to register $logName hotkey (key=0x$keyCode): $e '
        '— staying unregistered, no safe-default fallback',
      );
    }
  }

  /// Re-registers the "next favorite language" hotkey with a new combination.
  /// Toggle-only one-shot like the Snippet-Picker: no key-up is wired, and no
  /// safe-default fallback on failure.
  Future<void> updateLanguageCycleHotkey({
    required LogicalKeyboardKey key,
    List<HotKeyModifier> modifiers = const [],
  }) => _registerToggleOnlyAction(
    actionId: _languageCycleActionId,
    handlerLabel: 'LanguageCycle',
    logName: 'Language-cycle',
    key: key,
    modifiers: modifiers,
    setStatus: _setLanguageCycleStatus,
  );

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
  }) => _registerPushToTalkAction(
    actionId: _smartModeActionId,
    handlerLabel: 'SmartMode',
    logName: 'Smart-Mode',
    key: key,
    modifiers: modifiers,
    setStatus: _setSmartModeStatus,
  );

  /// Re-registers the edit-selection hotkey with a new combination. Same
  /// push-to-talk wiring and no-safe-default-fallback contract as
  /// [updateSmartModeHotkey].
  Future<void> updateSelectionEditHotkey({
    required LogicalKeyboardKey key,
    List<HotKeyModifier> modifiers = const [],
  }) => _registerPushToTalkAction(
    actionId: _selectionEditActionId,
    handlerLabel: 'SelectionEdit',
    logName: 'edit-selection',
    key: key,
    modifiers: modifiers,
    setStatus: _setSelectionEditStatus,
  );

  /// Shared registration for the secondary recording hotkeys (Smart Mode,
  /// edit selection): key-up wired wherever the registrar supports it, no
  /// safe-default fallback on failure.
  Future<void> _registerPushToTalkAction({
    required String actionId,
    required String handlerLabel,
    required String logName,
    required LogicalKeyboardKey key,
    required List<HotKeyModifier> modifiers,
    required void Function(HotkeyRegistrationStatus) setStatus,
  }) async {
    if (!_isDesktop) return;
    await _unregisterAction(actionId, stopMonitor: false);

    final hotKey = HotKey(key: key, modifiers: modifiers);
    _stateFor(actionId).registeredHotKey = hotKey;

    try {
      await _registrar.register(
        hotKey,
        keyDownHandler: (_) => _handleKeyDown(actionId, handlerLabel),
        keyUpHandler: _registrar.supportsKeyUp
            ? (_) => _handleKeyUp(actionId, handlerLabel)
            : null,
      );
      _log.info('$logName hotkey registered successfully');
      setStatus(HotkeyRegistrationStatus.success);
    } on Object catch (e) {
      setStatus(HotkeyRegistrationStatus.conflict);
      _stateFor(actionId).registeredHotKey = null;
      final keyCode = key.keyId.toRadixString(16);
      _log.warning(
        'Failed to register $logName hotkey (key=0x$keyCode): $e '
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

  /// Registers the session-scoped bare **Escape** that cancels/discards a
  /// normal (non-snippet) dictation — issue #145's "Escape only cancels
  /// interactive snippet sequences, not a normal dictation" gap.
  ///
  /// MUST only be called while a normal dictation is recording/transcribing/
  /// refining, and MUST be paired with [unregisterCancelDictationKey] once it
  /// leaves that range (done/error/idle) — same system-wide-grab contract as
  /// [registerInteractiveSnippetKeys]. `FloatingOverlayService` owns the
  /// pairing, driven off `recordingPhaseProvider`, and skips it entirely
  /// while an interactive-snippet sequence is active (that sequence owns
  /// Escape itself via [registerInteractiveSnippetKeys]).
  Future<void> registerCancelDictationKey({
    required VoidCallback onCancel,
    LogicalKeyboardKey key = LogicalKeyboardKey.escape,
  }) async {
    if (!_isDesktop) return;
    final epoch = ++_cancelDictationEpoch;
    await _unregisterAction(_cancelDictationActionId, stopMonitor: false);
    if (epoch != _cancelDictationEpoch) return;
    _onCancelDictation = onCancel;
    await _registerSessionKeyGeneric(
      _cancelDictationActionId,
      key,
      'Cancel dictation',
      epoch,
      () => epoch == _cancelDictationEpoch,
    );
  }

  /// Removes the cancel-dictation Escape registration (see
  /// [registerCancelDictationKey]). Safe to call when nothing is registered.
  Future<void> unregisterCancelDictationKey() async {
    _cancelDictationEpoch++;
    _onCancelDictation = null;
    await _unregisterAction(_cancelDictationActionId, stopMonitor: false);
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
  ) => _registerSessionKeyGeneric(
    actionId,
    key,
    label,
    epoch,
    () => epoch == _snippetKeysEpoch,
  );

  /// Shared implementation behind [_registerSessionKey] (interactive-snippet
  /// keys) and [registerCancelDictationKey] (normal-dictation Escape) — each
  /// caller supplies its own epoch/[stillCurrent] check so the two
  /// independent session-key lifecycles never interfere with each other.
  Future<void> _registerSessionKeyGeneric(
    String actionId,
    LogicalKeyboardKey key,
    String label,
    int epoch,
    bool Function() stillCurrent,
  ) async {
    if (!stillCurrent()) {
      // The session already ended before this key's turn came — skip.
      return;
    }
    final hotKey = HotKey(key: key, modifiers: const []);
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
      if (!stillCurrent()) {
        // The session ended while the registration was in flight — undo it
        // immediately instead of leaking a system-wide key grab.
        _log.info('$label registration outlived its session — undoing');
        try {
          await _registrar.unregister(hotKey);
        } on Object catch (e) {
          _log.debug('$label late unregister failed (non-fatal): $e');
        }
        return;
      }
      _stateFor(actionId).registeredHotKey = hotKey;
      _log.info('$label registered');
    } on Object catch (e) {
      _stateFor(actionId).registeredHotKey = null;
      _log.warning(
        'Failed to register $label: $e — the session continues without it',
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

  /// Sibling of [_registerFromSettings] for the "next favorite language"
  /// action.
  Future<void> _registerLanguageCycleFromSettings(AppSettings settings) {
    final stt = settings.stt;
    return _registerSecondaryHotkeyFromSettings(
      key: stt.languageCycleHotkeyKey,
      modifiers: stt.languageCycleHotkeyModifiers,
      update: updateLanguageCycleHotkey,
      markInitialized: () => _languageCycleInitialized = true,
      setStatus: _setLanguageCycleStatus,
      label: 'Language-cycle',
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

  /// Sibling of [_registerFromSettings] for the edit-selection action.
  Future<void> _registerSelectionEditFromSettings(AppSettings settings) {
    final hotkey = settings.selectionEditHotkey;
    return _registerSecondaryHotkeyFromSettings(
      key: hotkey.selectionEditHotkeyKey,
      modifiers: hotkey.selectionEditHotkeyModifiers,
      update: updateSelectionEditHotkey,
      markInitialized: () => _selectionEditInitialized = true,
      setStatus: _setSelectionEditStatus,
      label: 'Edit-selection',
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

  /// Writes [globalHotkeyFallbackActiveProvider] — same standalone-test guard
  /// as [_setStatus].
  void _setFallbackActive(bool active) {
    try {
      ref.read(globalHotkeyFallbackActiveProvider.notifier).set(active);
    } on Object catch (e) {
      _log.debug(
        'Hotkey fallback update skipped (standalone test instance): $e',
      );
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

  /// Language-cycle sibling of [_setStatus] — same standalone-test guard.
  void _setLanguageCycleStatus(HotkeyRegistrationStatus status) {
    try {
      ref
          .read(languageCycleHotkeyRegistrationStatusProvider.notifier)
          .set(status);
    } on Object catch (e) {
      _log.debug(
        'Language-cycle hotkey status update skipped (standalone test instance): $e',
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

  /// Edit-selection sibling of [_setStatus] — same standalone-test guard.
  void _setSelectionEditStatus(HotkeyRegistrationStatus status) {
    try {
      ref
          .read(selectionEditHotkeyRegistrationStatusProvider.notifier)
          .set(status);
    } on Object catch (e) {
      _log.debug(
        'Edit-selection hotkey status update skipped (standalone test '
        'instance): $e',
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
      await _startMonitor(fallback);
      _setFallbackActive(true);
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
    // A hotkey press closes an open nudge prompt. The close records nothing,
    // so it is neither a dismissal nor a snooze.
    _promptArbiter?.closeOpenPrompt();
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
    } else if (actionId == _languageCycleActionId) {
      // No perf mark: switching the language does not start a recording.
      onLanguageCycleHotkeyPressed?.call();
    } else if (actionId.startsWith(_profileActionPrefix)) {
      // No perf mark: a profile switch changes settings, it starts nothing.
      onProfileHotkeyPressed?.call(
        actionId.substring(_profileActionPrefix.length),
      );
    } else if (actionId == _smartModeActionId) {
      // Same t₀ stamp rationale as the quick-note action — this action also
      // drives the recording overlay.
      PerfMarkers.instance.markHotkeyPressed();
      onSmartModeHotkeyPressed?.call();
    } else if (actionId == _selectionEditActionId) {
      // Drives the recording overlay too — same t₀ stamp rationale.
      PerfMarkers.instance.markHotkeyPressed();
      onSelectionEditHotkeyPressed?.call();
    } else if (actionId == _snippetAdvanceActionId) {
      // No perf mark — the field advance ends a recording rather than
      // starting the hotkey→overlay hot path this marker measures.
      _onInteractiveSnippetAdvance?.call();
    } else if (actionId == _snippetCancelActionId) {
      _onInteractiveSnippetCancel?.call();
    } else if (actionId == _cancelDictationActionId) {
      _onCancelDictation?.call();
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
    } else if (actionId == _selectionEditActionId) {
      onSelectionEditHotkeyReleased?.call();
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

  /// Makes the registered profile hotkeys match [entries]. A profile whose
  /// combination is unchanged stays registered, so calling this again with the
  /// same entries registers nothing; a removed or changed entry is unregistered
  /// first. Returns the profile ids the OS refused.
  Future<Set<String>> syncProfileHotkeys(
    List<ProfileHotkeyEntry> entries,
  ) async {
    if (!_isDesktop) return const {};
    final wanted = {for (final entry in entries) entry.actionId: entry};
    for (final actionId in _profileRegistrations.keys.toList()) {
      final target = wanted[actionId];
      if (target != null &&
          _profileRegistrations[actionId] == target.signature) {
        continue;
      }
      await _unregisterProfileAction(actionId);
    }
    final refused = <String>{};
    for (final entry in entries) {
      if (_profileRegistrations.containsKey(entry.actionId)) continue;
      if (!await _registerProfileHotkey(entry)) refused.add(entry.profileId);
    }
    return refused;
  }

  Future<bool> _registerProfileHotkey(ProfileHotkeyEntry entry) async {
    final hotKey = HotKey(
      key: resolveKey(entry.key),
      modifiers: resolveModifiers(entry.modifiers),
    );
    _stateFor(entry.actionId).registeredHotKey = hotKey;
    try {
      await _registrar.register(
        hotKey,
        keyDownHandler: (_) => _handleKeyDown(entry.actionId, 'Profile'),
      );
      _profileRegistrations[entry.actionId] = entry.signature;
      _log.info('Profile hotkey registered: ${entry.profileId}');
      return true;
    } on Object catch (e) {
      _stateFor(entry.actionId).registeredHotKey = null;
      _log.warning('Profile hotkey refused for ${entry.profileId}: $e');
      return false;
    }
  }

  Future<void> _unregisterProfileAction(String actionId) async {
    await _unregisterAction(actionId, stopMonitor: false);
    _profileRegistrations.remove(actionId);
    _actionStates.remove(actionId);
  }

  Future<void> _destroy() async {
    for (final actionId in _profileRegistrations.keys.toList()) {
      await _unregisterProfileAction(actionId);
    }
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
    if (_languageCycleInitialized) {
      await _unregisterAction(_languageCycleActionId, stopMonitor: false);
      _log.info('Language-cycle hotkey unregistered');
    }
    if (_smartModeInitialized) {
      await _unregisterAction(_smartModeActionId, stopMonitor: false);
      _log.info('Smart-Mode hotkey unregistered');
    }
    if (_selectionEditInitialized) {
      await _unregisterAction(_selectionEditActionId, stopMonitor: false);
      _log.info('Edit-selection hotkey unregistered');
    }
    // Last line of defence for the session-scoped interactive-snippet keys:
    // normally InteractiveSnippetController unregisters them on every
    // sequence exit path, but a teardown mid-sequence must not leak a
    // system-wide Enter/Escape grab. No-op when nothing is registered.
    await unregisterInteractiveSnippetKeys();
    // Same last-line-of-defence for the cancel-dictation Escape key:
    // FloatingOverlayService normally unregisters it on every phase exit,
    // but a teardown mid-recording must not leak the system-wide grab.
    await unregisterCancelDictationKey();
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
