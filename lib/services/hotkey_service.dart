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
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'dart:ui' show Locale;

import '../core/config/settings_labels.dart';
import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/perf_instrumentation.dart';
import '../core/recording/recording_state.dart'
    show isDictationBusy, recordingProvider;
import 'floating_button/floating_button_support.dart';
import 'hotkey_key_resolver.dart';
import 'hotkey_trigger.dart';
import 'profile_hotkey_plan.dart';
import 'short_press_hint.dart';
import 'hotkey_registrar.dart';
import 'prompt_display_arbiter.dart';
import 'hotkey_heal_notice.dart';
import 'hotkey_self_heal.dart';
import 'keyboard_up_monitor.dart';
import 'modifier_key_monitor.dart';

export 'hotkey_registrar.dart' show HotKeyRegistrar;

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

/// Notifier holding the shortcut the desktop bound for the main hotkey
/// (null until it reports one). Written by [HotkeyService].
class WaylandBoundTriggerController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? trigger) {
    state = trigger;
  }
}

/// Provider for the desktop-bound shortcut shown in the Wayland notice.
final waylandBoundTriggerProvider =
    NotifierProvider<WaylandBoundTriggerController, String?>(
      WaylandBoundTriggerController.new,
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

/// Notifier holding the [HotkeyRegistrationStatus] for the "paste the last
/// dictation again" hotkey, separate like the other extra actions.
class RepasteHotkeyRegistrationStatusController
    extends Notifier<HotkeyRegistrationStatus> {
  @override
  HotkeyRegistrationStatus build() => HotkeyRegistrationStatus.unknown;

  void set(HotkeyRegistrationStatus status) {
    state = status;
  }
}

/// Provider for the "paste the last dictation again" [HotkeyRegistrationStatus].
final repasteHotkeyRegistrationStatusProvider =
    NotifierProvider<
      RepasteHotkeyRegistrationStatusController,
      HotkeyRegistrationStatus
    >(RepasteHotkeyRegistrationStatusController.new);

/// Notifier holding the [HotkeyRegistrationStatus] for the Smart-Mode hotkey
/// (ticket 04 of `internal-notes`) — kept fully separate from the
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
/// hotkey (`internal-notes`) — separate from the other
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

/// True while the saved double-tap trigger is not observable on this device
/// (Fn off macOS, Wayland, a key the native observer refuses), so the stored
/// key combination listens in its place. The double-tap choice stays saved and
/// takes over again as soon as the device can observe it.
class DoubleTapFallbackController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool active) {
    state = active;
  }
}

final doubleTapFallbackActiveProvider =
    NotifierProvider<DoubleTapFallbackController, bool>(
      DoubleTapFallbackController.new,
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

ModifierHotkey? _modifierHotkeyNamed(String name) {
  for (final key in ModifierHotkey.values) {
    if (key.name == name) return key;
  }
  return null;
}

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

  /// Action identifier for the toggle-only "paste the last dictation again"
  /// hotkey. Must match the action id in `hotkey_flow.dart`'s binding list.
  static const _repasteActionId = 'repaste';

  /// Prefix of the per-profile action ids (see [profileHotkeyActionId]).
  static const _profileActionPrefix = 'profile:';

  /// Action identifier for the fourth, push-to-talk-capable Smart-Mode
  /// hotkey (ticket 04 of `internal-notes`). Unlike
  /// [_quickNoteActionId]/[_snippetPickerActionId] it mirrors
  /// [_globalActionId]'s push-to-talk support (ADR 0008: one extra hotkey,
  /// behaving like the main one, not a lesser toggle-only action).
  static const _smartModeActionId = 'smartMode';

  /// Action identifier for the edit-selection hotkey
  /// (`internal-notes`) — push-to-talk-capable exactly like
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

  /// Fired when the "paste the last dictation again" hotkey is pressed. The
  /// bootstrap wires it to the repaste service. One-shot, starts nothing.
  VoidCallback? onRepasteHotkeyPressed;

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

  /// Whether the optional actions (Smart Mode, selection edit) get key-up.
  /// Only the registrar delivers it to them; the RawInput monitor serves the
  /// global action alone. A hold on them must therefore use this flag, not
  /// [supportsKeyUp], or its release never arrives on Windows/Linux.
  bool get optionalActionsSupportKeyUp => _registrar.supportsKeyUp;

  /// Whether push-to-talk rests solely on the experimental Linux key-up
  /// monitor (catchup/09) — the settings UI marks the option then.
  bool get keyUpExperimental =>
      !_registrar.supportsKeyUp &&
      _monitor.supportsKeyUp &&
      _monitor.experimental;

  bool _initialized = false;
  bool _quickNoteInitialized = false;
  bool _snippetPickerInitialized = false;
  bool _languageCycleInitialized = false;
  bool _repasteInitialized = false;
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
  /// tests by calling [injectRegistrar]. Wrapped so a hotkey recorder can
  /// take every registration off the system while it listens
  /// ([_syncCaptureSuspension]).
  SuspendableHotKeyRegistrar _registrar = SuspendableHotKeyRegistrar(
    const _PackageHotKeyRegistrar(),
  );

  /// Key-up source for platforms whose registrar is key-down only (Windows
  /// RawInput, issue #39; Linux XInput2/GlobalShortcuts portal, experimental,
  /// catchup/09). On macOS this is a no-op monitor and the registrar
  /// provides key-up. Override in tests via [injectMonitor].
  KeyboardUpMonitor _monitor = (Platform.isWindows || Platform.isLinux)
      ? ChannelKeyboardUpMonitor()
      : NoopKeyboardUpMonitor();

  /// Native observer for a modifier-only global hotkey on macOS. Windows and
  /// Linux route the same events through [_monitor] instead.
  ModifierKeyMonitor _modifierMonitor = ModifierKeyMonitor();

  /// Process environment the Linux session type is read from.
  Map<String, String> _environment = Platform.environment;

  /// Linux Wayland, first run: starting the monitor asks the desktop to bind
  /// the hotkey (GlobalShortcuts portal), and GNOME answers with a modal
  /// shortcut dialog. Until the onboarding reaches its hotkey page or is
  /// done, that start waits, so the dialog never lands on a page that has not
  /// explained it. Installs with a completed onboarding bind at startup.
  bool _desktopBindingAllowed = false;

  /// A monitor start was held back by [_desktopBindingDeferred].
  bool _desktopBindingPending = false;

  /// True while the global hotkey is a modifier-only key instead of a combo.
  bool _modifierOnlyActive = false;

  /// Tail of the modifier-only start/stop chain, see [_serializeModifierOnly].
  Future<void> _modifierOnlyTail = Future<void>.value();

  /// Tail of the global-hotkey chain, see [_serializeGlobal].
  Future<void> _globalTail = Future<void>.value();

  /// Longest a single native step of a hotkey chain may take before the chain
  /// gives it up and continues.
  static const _chainStepTimeout = Duration(seconds: 5);

  /// Pending [_chainStepTimeout] timers. Cancelled in [_destroy]: a native
  /// step that never answers (no host in tests, a host torn down at quit)
  /// must not leave a timer running after the service is gone.
  final Set<Timer> _chainTimers = {};

  /// Longest one heal may spend on the native calls before it counts as a
  /// failed heal. Shorter than [_chainStepTimeout], so a hung native call is
  /// reported by the heal itself instead of by the chain's generic timeout.
  static const _healStepTimeout = Duration(seconds: 4);

  /// Throttle and failure streak of the self-heal (see [requestHotkeyHeal]).
  final HotkeyHealGate _healGate = HotkeyHealGate();

  /// Safety-net timer for the periodic heal ([kHotkeyHealInterval]).
  Timer? _healTimer;

  /// Test seams for the heal's environment; null reads the real providers.
  bool Function()? _healHotkeyEnabled;
  bool Function()? _healDictationBusy;
  DateTime Function() _healNow = DateTime.now;

  /// Called once per streak of [kHotkeyHealFailureToastThreshold] failed heals,
  /// so the user is told that the hotkey cannot be restored automatically.
  void Function()? onHotkeyHealFailedRepeatedly;

  /// Completes with [step]'s result, or with [onTimeout] once
  /// [_chainStepTimeout] passes without an answer.
  Future<T> _boundedStep<T>(
    Future<T> step,
    T Function() onTimeout, {
    Duration timeout = _chainStepTimeout,
  }) {
    final result = Completer<T>();
    late final Timer timer;
    timer = Timer(timeout, () {
      _chainTimers.remove(timer);
      if (!result.isCompleted) result.complete(onTimeout());
    });
    _chainTimers.add(timer);
    void settle() {
      timer.cancel();
      _chainTimers.remove(timer);
    }

    step.then(
      (value) {
        settle();
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object e, StackTrace st) {
        settle();
        if (!result.isCompleted) result.completeError(e, st);
      },
    );
    return result.future;
  }

  /// The keyboard-monitor channel that runs the active modifier-only watch on
  /// Windows and Linux, or null when the macOS observer runs it. Remembered at
  /// start so the stop ends the observer that was started, not the one the
  /// host would pick now.
  ChannelKeyboardUpMonitor? _modifierOnlyChannel;

  /// Called when another key is pressed while the modifier-only hotkey is
  /// held (⌘+C stays ⌘+C). The recording trigger cancels its recording here.
  VoidCallback? onModifierOtherKey;

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
    HotkeyCaptureGuard.setListeningListener(
      (_) => unawaited(_captureSync = _syncCaptureSuspension()),
    );
    ref.onDispose(() => HotkeyCaptureGuard.setListeningListener(null));
    _healTimer = Timer.periodic(
      kHotkeyHealInterval,
      (_) => unawaited(requestHotkeyHeal(HotkeyHealTrigger.timer)),
    );
    onHotkeyHealFailedRepeatedly = () =>
        ref.read(hotkeyHealNoticeProvider.notifier).raise();

    // A double tap the device refused is retried when the app comes back to
    // the foreground, so a permission granted meanwhile takes over without a
    // restart. On desktop, window focus arrives as the resumed state.
    final lifecycle = AppLifecycleListener(onResume: _retryDoubleTapFallback);
    ref.onDispose(lifecycle.dispose);

    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (prev, next) {
      final previous = prev?.value;
      final current = next.value;
      if (current == null || previous == null) return;

      final globalChanged =
          previous.hotkeyKey != current.hotkeyKey ||
          previous.hotkeyModifiers != current.hotkeyModifiers ||
          previous.hotkey.hotkeyDoubleTapKey !=
              current.hotkey.hotkeyDoubleTapKey ||
          previous.hotkeyEnabled != current.hotkeyEnabled;
      if (globalChanged) {
        if (current.hotkeyEnabled) {
          unawaited(_registerFromSettings(current));
        } else {
          unawaited(
            _serializeGlobal(() async {
              await _stopModifierOnly();
              await _unregisterAction(_globalActionId, stopMonitor: true);
              _setFallbackActive(false);
              _setDoubleTapFallback(false);
            }),
          );
          _log.info('Global hotkey disabled by user');
        }
      }

      if (!previous.onboarding.onboardingCompleted &&
          current.onboarding.onboardingCompleted) {
        unawaited(allowDesktopHotkeyBinding());
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
        prevKey: previous.behavior.repasteHotkeyKey,
        key: current.behavior.repasteHotkeyKey,
        prevModifiers: previous.behavior.repasteHotkeyModifiers,
        modifiers: current.behavior.repasteHotkeyModifiers,
        prevEnabled: previous.behavior.repasteHotkeyEnabled,
        enabled: current.behavior.repasteHotkeyEnabled,
        actionId: _repasteActionId,
        label: 'Repaste',
        register: () => _registerRepasteFromSettings(current),
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
      if (settings.behavior.repasteHotkeyEnabled) {
        await _registerRepasteFromSettings(settings);
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

  /// Injects the macOS modifier observer for unit testing.
  @visibleForTesting
  void injectModifierMonitor(ModifierKeyMonitor monitor) {
    _modifierMonitor = monitor;
  }

  /// Injects the environment for unit testing, so the Linux session type does
  /// not follow the machine the tests run on.
  @visibleForTesting
  void injectEnvironment(Map<String, String> environment) {
    _environment = environment;
  }

  /// Makes [key] the global hotkey without a key combination: hold starts,
  /// release stops, another key cancels. Returns false when the platform
  /// cannot observe the key; the caller then keeps the combination.
  Future<bool> registerModifierOnly(ModifierHotkey key) {
    if (!_isDesktop) return Future.value(false);
    return _serializeModifierOnly(
      () => _startModifierOnly(key),
      onTimeout: false,
    );
  }

  /// Runs one modifier-only start or stop after the previous one has
  /// finished. A stop that arrives while a start still awaits its native reply
  /// must run after it, or the observer would stay on for a disabled hotkey.
  ///
  /// Bounded like [_serializeGlobal]: an unanswered native start or stop
  /// yields [onTimeout] after [_chainStepTimeout] instead of blocking the chain.
  Future<T> _serializeModifierOnly<T>(
    Future<T> Function() action, {
    required T onTimeout,
  }) {
    final run = _modifierOnlyTail.then(
      (_) => _boundedStep(action(), () {
        _log.warning(
          'Modifier-only step did not answer within '
          '${_chainStepTimeout.inSeconds} s; the next change runs',
        );
        return onTimeout;
      }),
    );
    _modifierOnlyTail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<bool> _startModifierOnly(ModifierHotkey key) async {
    await _unregisterAction(_globalActionId, stopMonitor: true);
    final bool started;
    ChannelKeyboardUpMonitor? channel;
    if (Platform.isMacOS) {
      _modifierMonitor.onInput = _routeModifierInput;
      started = await _modifierMonitor.start(key);
    } else if (_monitor case final ChannelKeyboardUpMonitor channelMonitor) {
      channel = channelMonitor;
      channelMonitor.onModifierInput = _routeModifierInput;
      started = await channelMonitor.watchModifier(key);
    } else {
      started = false;
    }
    _modifierOnlyActive = started;
    _modifierOnlyChannel = started ? channel : null;
    if (started) {
      _log.info('Modifier-only global hotkey active: ${key.name}');
    }
    return started;
  }

  void _routeModifierInput(ModifierInput input) {
    switch (input) {
      case ModifierInput.down:
        _handleKeyDown(_globalActionId, 'Global');
      case ModifierInput.up:
        _handleKeyUp(_globalActionId, 'Global');
      case ModifierInput.other:
        _signalDictationActivity((c) => c.otherKey());
        onModifierOtherKey?.call();
    }
  }

  /// Ends the modifier-only observer before a combination takes its place.
  Future<void> _stopModifierOnly() => _serializeModifierOnly(() async {
    if (!_modifierOnlyActive) return;
    _modifierOnlyActive = false;
    final channel = _modifierOnlyChannel;
    _modifierOnlyChannel = null;
    if (channel != null) {
      channel.onModifierInput = null;
      await channel.stop();
    } else {
      _modifierMonitor.onInput = null;
      await _modifierMonitor.stop();
    }
  }, onTimeout: null);

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
    _monitor.onKeyUp = _onMonitorKeyUp;
    _monitor.onKeyDown = () => _handleKeyDown(_globalActionId, 'Global');
    _monitor.onWaylandBindingChanged = _applyWaylandBinding;
  }

  /// Key-up of the global hotkey from the native monitor. [pressed] is the
  /// press length the native side timed, so the one-time hint is decided on
  /// the real press, not on when this event reached Dart. A press that short
  /// cannot have been a deliberate hold: it is an on-screen keyboard click, so
  /// the hint explains the "Tap or hold" option. The release itself is handled
  /// as before.
  void _onMonitorKeyUp(Duration? pressed) {
    final wasHeld = _stateFor(_globalActionId).keyHeld;
    _handleKeyUp(_globalActionId, 'Global');
    if (wasHeld && pressed != null && pressed <= shortPressMaxDuration) {
      _requestShortPressHint();
    }
  }

  /// Starts the key-up monitor for the global [hotKey]. On Linux Wayland this
  /// also asks the desktop to bind it (GlobalShortcuts portal), under the
  /// localized name the desktop shows in its dialog.
  Future<void> _startMonitor(HotKey hotKey) async {
    if (_desktopBindingDeferred) {
      _desktopBindingPending = true;
      _log.info('Desktop hotkey binding waits for the onboarding hotkey page');
      return;
    }
    await _monitor.start(
      hotKey,
      description: _resolveL10n().waylandHotkeyPortalDescription,
    );
    _applyWaylandBinding();
  }

  bool get _desktopBindingDeferred =>
      !_desktopBindingAllowed &&
      linuxSessionTypeFrom(_environment) == LinuxSessionType.wayland &&
      !(_settingsOrNull()?.onboarding.onboardingCompleted ?? true);

  /// Lets the global hotkey be bound by the desktop from now on and starts a
  /// monitor that waited for it (see [_desktopBindingAllowed]). Called by the
  /// onboarding hotkey page and once the onboarding is completed or closed.
  Future<void> allowDesktopHotkeyBinding() async {
    if (_desktopBindingAllowed) return;
    _desktopBindingAllowed = true;
    if (!_desktopBindingPending) return;
    _desktopBindingPending = false;
    await _serializeGlobal(reconnectWaylandHotkey);
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
      ref
          .read(waylandBoundTriggerProvider.notifier)
          .set(_monitor.waylandTrigger);
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
    _registrar.dispose();
    _registrar = SuspendableHotKeyRegistrar(registrar);
  }

  /// Re-registers the hotkey with a new combination.
  ///
  /// If registration throws any [Object] (including [TypeError] from
  /// `hotkey_manager`), the service registers the safe-default hotkey instead
  /// and fires [onRegistrationFailed].
  ///
  /// Calls run one after another ([_serializeGlobal]), so the last one wins and
  /// no earlier registration is left behind.
  Future<void> updateHotkey({
    required LogicalKeyboardKey key,
    List<HotKeyModifier> modifiers = const [],
  }) => _serializeGlobal(() => _applyCombo(key: key, modifiers: modifiers));

  /// Runs one global-hotkey operation after the previous one has finished.
  /// Settings changes arrive as unawaited futures, so without this chain two
  /// quick changes could interleave their unregister and register calls and
  /// leave a duplicate or an orphaned registration. Must not be nested: an
  /// action running inside the chain calls [_applyCombo] directly.
  ///
  /// A step that never answers is given up after [_chainStepTimeout] and the
  /// chain moves on, so one hung native call cannot block every later change.
  Future<void> _serializeGlobal(Future<void> Function() action) {
    final run = _globalTail.then(
      (_) => _boundedStep<void>(action(), () {
        _log.warning(
          'Global hotkey step did not answer within '
          '${_chainStepTimeout.inSeconds} s; the next change runs',
        );
        _setStatus(HotkeyRegistrationStatus.conflict);
      }),
    );
    _globalTail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _applyCombo({
    required LogicalKeyboardKey key,
    List<HotKeyModifier> modifiers = const [],
  }) async {
    if (!_isDesktop) return;
    await _stopModifierOnly();
    await _unregisterAction(_globalActionId, stopMonitor: true);

    final hotKey = HotKey(key: key, modifiers: modifiers);
    _stateFor(_globalActionId).registeredHotKey = hotKey;

    try {
      await _registrar.register(
        hotKey,
        keyDownHandler: (_) =>
            _handleKeyDown(_globalActionId, 'Global', checkReleasedAtArm: true),
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
  /// Snippet-Picker, language cycle): no monitor is started, and a failed
  /// registration stays unregistered rather than falling back to a safe
  /// default. Where key-up exists (macOS) the release clears `keyHeld`, so a
  /// later press is not taken for auto-repeat.
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

  /// Re-registers the "paste the last dictation again" hotkey with a new
  /// combination. Toggle-only one-shot, no safe-default fallback on failure.
  Future<void> updateRepasteHotkey({
    required LogicalKeyboardKey key,
    List<HotKeyModifier> modifiers = const [],
  }) => _registerToggleOnlyAction(
    actionId: _repasteActionId,
    handlerLabel: 'Repaste',
    logName: 'Repaste',
    key: key,
    modifiers: modifiers,
    setStatus: _setRepasteStatus,
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

  /// Test seam: replaces the reads of "hotkey enabled" and "dictation busy".
  @visibleForTesting
  void injectHealEnvironment({
    required bool Function() hotkeyEnabled,
    required bool Function() dictationBusy,
  }) {
    _healHotkeyEnabled = hotkeyEnabled;
    _healDictationBusy = dictationBusy;
  }

  /// Test seam: replaces the clock that drives the heal throttle.
  @visibleForTesting
  void injectHealClock(DateTime Function() now) => _healNow = now;

  /// Re-registers the global hotkey (and the enabled extra hotkeys) after a
  /// trigger that may mean the OS has stopped delivering presses: a wake, a
  /// memory-pressure unload, a UI stall, or the periodic safety net.
  ///
  /// Idempotent and cheap to call often: runs are throttled to one per
  /// [kHotkeyHealMinInterval], queued behind other hotkey changes, and skipped
  /// while a dictation, a held key or a hotkey capture makes a re-registration
  /// unsafe. Each run that actually happens writes one log line.
  Future<void> requestHotkeyHeal(HotkeyHealTrigger trigger) {
    if (!_isDesktop) return Future<void>.value();
    if (_healGate.isThrottled(_healNow())) return Future<void>.value();
    if (hotkeyHealBlocker(_readHealState()) != null) {
      return Future<void>.value();
    }
    return _serializeGlobal(() => _healGlobal(trigger));
  }

  Future<void> _captureSync = Future<void>.value();

  /// Test seam: completes once the registrations follow the last change of
  /// [HotkeyCaptureGuard.listening].
  @visibleForTesting
  Future<void> get captureSuspensionSettled => _captureSync;

  /// Brings the system registrations in line with [HotkeyCaptureGuard]:
  /// off while a recorder listens, back on afterwards. Reads the guard when it
  /// runs, so quick open/close sequences settle on the current state. A
  /// global hotkey the system refuses on the way back is reported like any
  /// failed registration; the periodic self-heal registers it again.
  Future<void> _syncCaptureSuspension() async {
    if (HotkeyCaptureGuard.listening) {
      await _registrar.suspend();
      return;
    }
    final refused = await _registrar.resume();
    if (refused.isEmpty) return;
    final global = _stateFor(_globalActionId).registeredHotKey;
    if (global != null &&
        refused.any((h) => h.identifier == global.identifier)) {
      _log.warning('Global hotkey refused after recording; self-heal retries');
      _setStatus(HotkeyRegistrationStatus.conflict);
    }
  }

  Future<void> _healGlobal(HotkeyHealTrigger trigger) async {
    final now = _healNow();
    if (_healGate.isThrottled(now)) return;
    final blocker = hotkeyHealBlocker(_readHealState());
    if (blocker != null) {
      _log.debug('Hotkey self-heal (${trigger.name}) skipped: $blocker');
      return;
    }
    _healGate.markRun(now);

    final watch = Stopwatch()..start();
    final ok = await _boundedStep<bool>(
      _reregisterGlobal(),
      () => false,
      timeout: _healStepTimeout,
    );
    watch.stop();
    final ms = watch.elapsedMilliseconds;

    if (ok) {
      _healGate.recordSuccess();
      _log.info('Hotkey self-heal (${trigger.name}): re-registered in $ms ms');
      return;
    }
    final showToast = _healGate.recordFailure();
    _log.warning(
      'Hotkey self-heal (${trigger.name}): failed after $ms ms, '
      '${_healGate.consecutiveFailures} in a row; retried on the next trigger',
    );
    if (showToast) onHotkeyHealFailedRepeatedly?.call();
  }

  /// Snapshot of what a heal depends on. A key held on any action counts
  /// until its key-up, or for at most [kHotkeyHeldStaleAfter] on platforms
  /// without key-up, so a lost release cannot block heals forever.
  HotkeyHealState _readHealState() {
    final now = DateTime.now();
    final held = _actionStates.values.any(
      (s) =>
          s.keyHeld &&
          (s.lastKeyDownAt == null ||
              now.difference(s.lastKeyDownAt!) < kHotkeyHeldStaleAfter),
    );
    final busyOverride = _healDictationBusy;
    final enabledOverride = _healHotkeyEnabled;
    return HotkeyHealState(
      hotkeyEnabled:
          enabledOverride?.call() ?? (_settingsOrNull()?.hotkeyEnabled ?? true),
      dictationBusy:
          busyOverride?.call() ??
          isDictationBusy(ref.read(recordingProvider).phase),
      keyHeld: held,
      captureActive: HotkeyCaptureGuard.active,
      modifierOnlyActive: _modifierOnlyActive,
    );
  }

  /// Current settings, or null where the service runs without the app's
  /// providers (standalone unit tests read a notifier that was never built).
  AppSettings? _settingsOrNull() {
    try {
      return ref.read(settingsProvider).value;
    } on Object {
      return null;
    }
  }

  /// Unregisters and registers the same combination again. The combination is
  /// the one currently registered; only when none is known is it taken from
  /// the settings. Never falls back to the safe-default combination: a heal
  /// that fails leaves the user's key as it was and is retried later.
  Future<bool> _reregisterGlobal() async {
    final global = _stateFor(_globalActionId);
    var hotKey = global.registeredHotKey;
    if (hotKey == null) {
      final settings = _settingsOrNull() ?? AppSettings.defaults;
      try {
        hotKey = HotKey(
          key: resolveKey(settings.hotkeyKey),
          modifiers: resolveModifiers(settings.hotkeyModifiers),
        );
      } on ArgumentError {
        return false;
      }
    }
    await _unregisterAction(_globalActionId, stopMonitor: false);
    global.registeredHotKey = hotKey;
    try {
      await _registrar.register(
        hotKey,
        keyDownHandler: (_) => _handleKeyDown(_globalActionId, 'Global'),
        keyUpHandler: _registrar.supportsKeyUp
            ? (_) => _handleKeyUp(_globalActionId, 'Global')
            : null,
      );
    } on Object {
      return false;
    }
    // A Wayland portal binding is held by the compositor and is not lost like
    // a grab. Restarting the monitor would open a new portal session, and
    // GNOME would ask the user to confirm the shortcut again on every heal.
    final portalOwned =
        _monitor.waylandBinding != WaylandHotkeyBinding.notApplicable;
    if (!portalOwned) await _startMonitor(hotKey);
    _setStatus(HotkeyRegistrationStatus.success);
    if (portalOwned) _applyWaylandBinding();

    final settings = _settingsOrNull();
    if (settings != null) {
      // Extra hotkeys re-register themselves without a fallback; their own
      // failures are logged and shown in their status, not counted here.
      if (settings.quickNoteHotkey.quickNoteHotkeyEnabled) {
        await _registerQuickNoteFromSettings(settings);
      }
      if (settings.snippetPickerHotkey.snippetPickerHotkeyEnabled) {
        await _registerSnippetPickerFromSettings(settings);
      }
      if (settings.stt.languageCycleHotkeyEnabled) {
        await _registerLanguageCycleFromSettings(settings);
      }
      if (settings.behavior.repasteHotkeyEnabled) {
        await _registerRepasteFromSettings(settings);
      }
      if (settings.smartModeHotkey.smartModeHotkeyEnabled) {
        await _registerSmartModeFromSettings(settings);
      }
      if (settings.selectionEditHotkey.selectionEditHotkeyEnabled) {
        await _registerSelectionEditFromSettings(settings);
      }
    }
    return true;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _registerFromSettings(AppSettings settings) =>
      _serializeGlobal(() => _applyFromSettings(settings));

  Future<void> _applyFromSettings(AppSettings settings) async {
    final doubleTapKey = _modifierHotkeyNamed(
      settings.hotkey.hotkeyDoubleTapKey,
    );
    if (doubleTapKey != null) {
      if (await _registerDoubleTapTrigger(doubleTapKey)) {
        _setDoubleTapFallback(false);
        return;
      }
      // Not observable on this device: the stored combination listens instead,
      // and the double-tap choice stays saved for later.
      _setDoubleTapFallback(true);
    } else {
      _setDoubleTapFallback(false);
    }
    try {
      await _applyCombo(
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

  /// Starts a double-tap key as the dictation trigger and returns true. Its
  /// observer is the modifier-only path. Returns false when the device cannot
  /// observe the key (Fn off macOS, Wayland, a refusing native observer); the
  /// caller then listens on the stored combination instead, see
  /// [_applyFromSettings].
  Future<bool> _registerDoubleTapTrigger(ModifierHotkey key) async {
    if (_doubleTapObservable(key) && await registerModifierOnly(key)) {
      _setStatus(HotkeyRegistrationStatus.success);
      _initialized = true;
      _log.info('Double-tap dictation trigger active: ${key.name}');
      return true;
    }
    _log.warning(
      'Double-tap trigger ${key.name} cannot be observed on this platform; '
      'the stored key combination listens in its place',
    );
    return false;
  }

  /// Whether this platform can observe a double tap of [key] at all. Fixed for
  /// the session: Fn off macOS and Wayland never change.
  bool _doubleTapObservable(ModifierHotkey key) {
    final isWayland =
        Platform.isLinux &&
        linuxSessionTypeFrom(_environment) == LinuxSessionType.wayland;
    return doubleTapSupported(
      key,
      isMacOS: Platform.isMacOS,
      isWayland: isWayland,
    );
  }

  /// Retries a refused double tap when the app comes back to the foreground.
  /// Idle unless a fallback is active, and only for keys the platform can
  /// observe in principle, so a Fn key off macOS never causes a native call.
  /// Re-runs [_applyFromSettings]: on success the double tap takes over, on
  /// another refusal the stored combination listens again.
  void _retryDoubleTapFallback() {
    if (!ref.read(doubleTapFallbackActiveProvider)) return;
    unawaited(
      _serializeGlobal(() async {
        // Checked again inside the chain: an earlier retry may have lifted it.
        if (!ref.read(doubleTapFallbackActiveProvider)) return;
        final settings = ref.read(settingsProvider).value;
        if (settings == null || !settings.hotkeyEnabled) return;
        final key = _modifierHotkeyNamed(settings.hotkey.hotkeyDoubleTapKey);
        if (key == null || !_doubleTapObservable(key)) return;
        _log.info('Retrying double-tap trigger ${key.name} after app resume');
        await _applyFromSettings(settings);
      }),
    );
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

  /// Sibling of [_registerFromSettings] for the repaste action.
  Future<void> _registerRepasteFromSettings(AppSettings settings) {
    final behavior = settings.behavior;
    return _registerSecondaryHotkeyFromSettings(
      key: behavior.repasteHotkeyKey,
      modifiers: behavior.repasteHotkeyModifiers,
      update: updateRepasteHotkey,
      markInitialized: () => _repasteInitialized = true,
      setStatus: _setRepasteStatus,
      label: 'Repaste',
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

  /// Writes [doubleTapFallbackActiveProvider] — same standalone-test guard as
  /// [_setStatus].
  void _setDoubleTapFallback(bool active) {
    try {
      ref.read(doubleTapFallbackActiveProvider.notifier).set(active);
    } on Object catch (e) {
      _log.debug(
        'Double-tap fallback update skipped (standalone test instance): $e',
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

  /// Repaste sibling of [_setStatus] — same standalone-test guard.
  void _setRepasteStatus(HotkeyRegistrationStatus status) {
    try {
      ref.read(repasteHotkeyRegistrationStatusProvider.notifier).set(status);
    } on Object catch (e) {
      _log.debug(
        'Repaste hotkey status update skipped (standalone test instance): $e',
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
        keyDownHandler: (_) => _handleKeyDown(
          _globalActionId,
          'Safe-default',
          checkReleasedAtArm: true,
        ),
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

  /// Feeds the onboarding demo key cap (V05). The demo must never stop the
  /// hotkey itself, so a failing signal is logged and dropped.
  void _signalDictationActivity(
    void Function(DictationHotkeyActivityController controller) signal,
  ) {
    try {
      signal(ref.read(dictationHotkeyActivityProvider.notifier));
    } on Object catch (e) {
      _log.debug('dictation activity signal dropped: $e');
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
  void _handleKeyDown(
    String actionId,
    String label, {
    bool checkReleasedAtArm = false,
  }) {
    // While a recorder listens, a press is the user recording a key, never a
    // trigger: this covers the modifier-only and monitor paths, which are not
    // taken off the system.
    if (HotkeyCaptureGuard.listening) {
      _log.debug('$label hotkey press ignored while a hotkey is recorded');
      return;
    }
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
      // Lights the onboarding demo key cap (V05); the press itself is
      // unchanged.
      _signalDictationActivity((c) => c.pressed(keyUpSupported: supportsKeyUp));
      // Stamp t₀ for hotkey→overlay latency BEFORE dispatching so the mark
      // captures the earliest possible Dart-layer moment of this event.
      // Counterpart: PerfMarkers.markOverlayShown() in FloatingOverlayService.
      PerfMarkers.instance.markHotkeyPressed();
      onHotkeyPressed?.call();
      // Arm the native release-watch: on Windows RegisterHotKey hides the
      // hotkey key's DOWN from RawInput, so the monitor snapshots the held key
      // now and reports its release; Linux arms its watch the same way. Both
      // answer whether the key is still held. macOS needs no watch because
      // the hotkey registrar delivers the release itself (#39).
      // Only the global action uses the shared monitor.
      final armed = _monitor.armRelease(
        modifiers: state.registeredHotKey?.modifiers ?? const [],
      );
      if (checkReleasedAtArm) {
        unawaited(_endPressReleasedBeforeArm(armed, now));
      } else {
        unawaited(armed);
      }
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
    } else if (actionId == _repasteActionId) {
      // No perf mark: pasting the last text again starts no recording.
      onRepasteHotkeyPressed?.call();
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

  /// A registered combination whose main key was already up when the native
  /// release-watch armed. No release event will come for that press, so it is
  /// ended now, like a release at once. Otherwise the recording it started
  /// would run on with no way to stop it by holding (for example a click on an
  /// on-screen keyboard). Only the press that is still current is ended.
  Future<void> _endPressReleasedBeforeArm(
    Future<bool> armed,
    DateTime now,
  ) async {
    final held = await armed;
    if (held) return;
    final state = _stateFor(_globalActionId);
    if (state.lastKeyDownAt != now) return;
    _log.info('Global hotkey already released at arm time; ending the press');
    // Linux may already have ended the press with its own key-up, which
    // arrives first. Ending it again is then a no-op.
    if (state.keyHeld) _handleKeyUp(_globalActionId, 'Global');
    _requestShortPressHint();
  }

  /// Asks for the one-time "Tap or hold" hint. Only pure hold-to-talk
  /// misfires this way. With "Tap or hold" on, the short press latches the
  /// recording instead, so there is nothing to explain.
  void _requestShortPressHint() {
    final audio = ref.read(settingsProvider).value?.audioInput;
    final holdModeOn =
        (audio?.pushToTalk ?? false) && !(audio?.holdOrTap ?? false);
    // Build the provider first: writing its state needs build to have run.
    ref.read(shortPressHintProvider);
    ref.read(shortPressHintProvider.notifier).request(holdModeOn: holdModeOn);
  }

  /// Handles a hotkey key-up (macOS only; global and Smart-Mode actions, and
  /// the toggle-only actions where [HotKeyRegistrar.supportsKeyUp] holds).
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
      _signalDictationActivity((c) => c.released());
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
    _healTimer?.cancel();
    _healTimer = null;
    for (final timer in _chainTimers) {
      timer.cancel();
    }
    _chainTimers.clear();
    _registrar.dispose();
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
    if (_repasteInitialized) {
      await _unregisterAction(_repasteActionId, stopMonitor: false);
      _log.info('Repaste hotkey unregistered');
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

/// What the dictation hotkey is doing right now, for the onboarding demo
/// (Onboarding v6, V05): [held] while the key is down, [presses] counts the
/// genuine presses (auto-repeat excluded), [otherKeys] counts the other keys
/// that joined a held single key (a shortcut, no gesture). Only the global
/// action feeds it.
@immutable
class DictationHotkeyActivity {
  const DictationHotkeyActivity({
    this.presses = 0,
    this.held = false,
    this.otherKeys = 0,
  });

  final int presses;
  final bool held;
  final int otherKeys;
}

/// Time after which a press without a key-up (Windows, Linux) stops lighting
/// the demo key cap again.
const Duration _demoHoldWindow = Duration(milliseconds: 700);

class DictationHotkeyActivityController
    extends Notifier<DictationHotkeyActivity> {
  Timer? _release;

  @override
  DictationHotkeyActivity build() {
    ref.onDispose(() => _release?.cancel());
    return const DictationHotkeyActivity();
  }

  /// A genuine press. Without key-up support the held flag clears itself.
  void pressed({required bool keyUpSupported}) {
    _release?.cancel();
    state = DictationHotkeyActivity(
      presses: state.presses + 1,
      held: true,
      otherKeys: state.otherKeys,
    );
    if (!keyUpSupported) {
      _release = Timer(_demoHoldWindow, released);
    }
  }

  void released() {
    _release?.cancel();
    if (!state.held) return;
    state = DictationHotkeyActivity(
      presses: state.presses,
      otherKeys: state.otherKeys,
    );
  }

  /// Another key joined the held single key.
  void otherKey() {
    state = DictationHotkeyActivity(
      presses: state.presses,
      held: state.held,
      otherKeys: state.otherKeys + 1,
    );
  }
}

final dictationHotkeyActivityProvider =
    NotifierProvider<
      DictationHotkeyActivityController,
      DictationHotkeyActivity
    >(DictationHotkeyActivityController.new);
