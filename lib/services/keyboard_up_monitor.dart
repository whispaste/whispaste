/// Key-up source for global hotkeys on platforms where the hotkey registrar
/// itself cannot deliver one (issue #39).
///
/// Background: on Windows the global hotkey is registered via `RegisterHotKey`
/// (the `hotkey_manager` package), which only ever produces `WM_HOTKEY` on
/// key-DOWN — Windows has no "hotkey up" message. That makes hold-to-talk
/// (push-to-talk) impossible through the registrar alone, so the push-to-talk
/// toggle is disabled there.
///
/// This monitor closes that gap WITHOUT taking over the hotkey: the native side
/// uses RawInput (`RIDEV_INPUTSINK`) to OBSERVE keyboard transitions globally
/// (it does not intercept or swallow keys, so the existing `RegisterHotKey`
/// still suppresses the keystroke and provides the key-DOWN). When the watched
/// hotkey's main key is released, the native side reports it here and the
/// [HotkeyService] turns it into an `onHotkeyReleased` event.
///
/// [supportsKeyUp] expresses *capability*, not active state: it is `true` on
/// Windows as soon as the native monitor is present, so the push-to-talk toggle
/// can be enabled even before a recording is in progress. macOS gets its key-up
/// from the registrar and needs no monitor.
///
/// Linux (experimental, handy-catchup/09): the same channel is served by the
/// GTK runner's `KeyboardMonitorHost`, which has two paths — XInput2 raw key
/// releases on the X display (X11 sessions) and the xdg-desktop-portal
/// `GlobalShortcuts` interface (Wayland, GNOME ≥ 48 / KDE Plasma ≥ 6), whose
/// `Activated`/`Deactivated` signals arrive here as `onKeyDown`/`onKeyUp`.
/// Which path works is only known at runtime, so on Linux [supportsKeyUp]
/// stays `false` until the native `start` probe reports one; a runner without
/// the host (`MissingPluginException`) keeps today's toggle-only behaviour.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show ValueChanged, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../core/logging/app_logger.dart';
import 'modifier_key_monitor.dart';

/// Who owns the global hotkey in a Linux Wayland session (XP-2-06).
///
/// There the X11 grab only fires while an XWayland window has focus, so the
/// hotkey works system-wide only once the compositor binds it through the
/// GlobalShortcuts portal. Everywhere else the registrar owns the hotkey and
/// this stays [notApplicable].
enum WaylandHotkeyBinding {
  /// Not a Wayland session (X11, Windows, macOS, or an older runner).
  notApplicable,

  /// Portal found, binding requested — the desktop may still be asking the
  /// user to confirm it.
  pending,

  /// The compositor owns the hotkey.
  bound,

  /// The portal could not identify WhisPaste (no installed desktop entry).
  noAppId,

  /// The session has no GlobalShortcuts portal.
  unavailable,

  /// The user or the desktop declined the binding.
  declined;

  /// Whether the hotkey does not work outside WhisPaste in this session.
  bool get isUnbound =>
      this == noAppId || this == unavailable || this == declined;
}

/// Maps a Linux host report (`start` reply or `onCapabilities` push) to a
/// [WaylandHotkeyBinding].
WaylandHotkeyBinding waylandHotkeyBindingFrom(Object? report) {
  if (report is! Map || report['wayland'] != true) {
    return WaylandHotkeyBinding.notApplicable;
  }
  if (report['bound'] == true) return WaylandHotkeyBinding.bound;
  if (report['portal'] == true) return WaylandHotkeyBinding.pending;
  return switch (report['reason']) {
    'no-app-id' => WaylandHotkeyBinding.noAppId,
    'declined' => WaylandHotkeyBinding.declined,
    _ => WaylandHotkeyBinding.unavailable,
  };
}

/// Observes key-up for the registered global hotkey on platforms whose hotkey
/// registrar is key-down only. Swap with a fake in unit tests.
abstract class KeyboardUpMonitor {
  /// Whether this monitor can deliver hotkey key-up on the current platform.
  ///
  /// Capability flag — independent of whether [start] has been called.
  bool get supportsKeyUp;

  /// Begins observing [hotKey] for the release (break) of its main key.
  ///
  /// Safe to call repeatedly; the latest [hotKey] replaces any previous watch.
  /// No-op when [supportsKeyUp] is `false`. [description] names the hotkey
  /// in the desktop's GlobalShortcuts dialog (Linux Wayland only).
  Future<void> start(HotKey hotKey, {String? description});

  /// Arms the release-watch — call when the hotkey fires (key-down). The native
  /// side snapshots the currently-held main key so its release ends the hold.
  ///
  /// Required because `RegisterHotKey` suppresses the hotkey key's DOWN from
  /// the RawInput stream, so the main key cannot be detected by observation
  /// alone (#39). [modifiers] are the hotkey's own modifiers: the native side
  /// keeps them as the combination that must stay intact, even when one was
  /// released before this call. No-op when [supportsKeyUp] is `false`.
  ///
  /// Resolves to whether the watched main key is still held at the snapshot.
  /// `false` means the press was already over before the arm, for example a
  /// click on an on-screen keyboard (down and up within milliseconds): no
  /// release event will follow. Unknown or unsupported reports `true`.
  Future<bool> armRelease({Iterable<HotKeyModifier> modifiers = const []});

  /// Stops observing. No-op when not started.
  Future<void> stop();

  /// Whether the key-up this monitor provides is experimental (Linux, not
  /// verified on a real GNOME/KDE desktop yet) — the settings UI labels the
  /// push-to-talk option accordingly.
  bool get experimental;

  /// Called when the watched hotkey's main key is released. The argument is
  /// how long the key was held, timed by the native host from the event
  /// timestamps (so a UI stall does not stretch it); null when the host cannot
  /// tell.
  set onKeyUp(ValueChanged<Duration?>? handler);

  /// Called when the monitor itself observes the hotkey press — only the
  /// Linux portal path does, since the compositor (not the X11 grab) owns the
  /// shortcut there.
  set onKeyDown(VoidCallback? handler);

  /// Who owns the global hotkey in a Linux Wayland session; see
  /// [WaylandHotkeyBinding]. Kept across [stop], like the key-up capability.
  WaylandHotkeyBinding get waylandBinding;

  /// Called whenever [waylandBinding] or [waylandTrigger] changes.
  set onWaylandBindingChanged(VoidCallback? handler);

  /// The shortcut the desktop reported for the bound hotkey (XDG
  /// `trigger_description`), or null when it did not say.
  String? get waylandTrigger;
}

/// No-op monitor for platforms that already have key-up (macOS) or have no
/// native host. [supportsKeyUp] is always `false`.
class NoopKeyboardUpMonitor implements KeyboardUpMonitor {
  @override
  bool get supportsKeyUp => false;

  @override
  bool get experimental => false;

  @override
  Future<void> start(HotKey hotKey, {String? description}) async {}

  @override
  Future<bool> armRelease({
    Iterable<HotKeyModifier> modifiers = const [],
  }) async => true;

  @override
  Future<void> stop() async {}

  @override
  set onKeyUp(ValueChanged<Duration?>? handler) {}

  @override
  set onKeyDown(VoidCallback? handler) {}

  @override
  WaylandHotkeyBinding get waylandBinding => WaylandHotkeyBinding.notApplicable;

  @override
  String? get waylandTrigger => null;

  @override
  set onWaylandBindingChanged(VoidCallback? handler) {}
}

/// Production monitor backed by the native `com.whispaste.keyboard_monitor`
/// channel (Windows RawInput host, Linux XInput2/portal host). Selected on
/// Windows and Linux; macOS uses a [NoopKeyboardUpMonitor].
class ChannelKeyboardUpMonitor implements KeyboardUpMonitor {
  ChannelKeyboardUpMonitor({
    @visibleForTesting bool? isWindows,
    @visibleForTesting bool? isLinux,
  }) : _isWindows = isWindows ?? Platform.isWindows,
       _isLinux = isLinux ?? Platform.isLinux {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final bool _isWindows;
  final bool _isLinux;

  /// Last capability the Linux host reported (`start` reply or a later
  /// `onCapabilities` push). Kept across [stop] so the settings UI does not
  /// flicker while the hotkey is re-registered.
  bool _linuxKeyUp = false;

  static final _log = AppLogger('KeyboardUpMonitor');

  static const MethodChannel _channel = MethodChannel(
    'com.whispaste.keyboard_monitor',
  );

  WaylandHotkeyBinding _waylandBinding = WaylandHotkeyBinding.notApplicable;
  String? _waylandTrigger;

  ValueChanged<Duration?>? _onKeyUp;
  VoidCallback? _onKeyDown;
  VoidCallback? _onWaylandBindingChanged;

  @override
  set onKeyUp(ValueChanged<Duration?>? handler) => _onKeyUp = handler;

  @override
  set onKeyDown(VoidCallback? handler) => _onKeyDown = handler;

  /// Receives modifier-only inputs from the Windows and Linux hosts.
  ValueChanged<ModifierInput>? _onModifierInput;
  set onModifierInput(ValueChanged<ModifierInput>? handler) =>
      _onModifierInput = handler;

  /// Asks the native host to pass [key] through as `onModifierDown`,
  /// `onModifierUp` and `onOtherKey`. Returns false when the host cannot see
  /// that key (Wayland, Fn off macOS), so the caller keeps the combination.
  Future<bool> watchModifier(ModifierHotkey key) async {
    if (!_isWindows && !_isLinux) return false;
    if (!modifierHotkeySupported(key, isMacOS: false)) return false;
    try {
      final watching =
          await _channel.invokeMethod<bool>('watchModifier', {
            'key': key.name,
          }) ??
          false;
      // The Linux X11 watch reports both press and release, so it gives the
      // key-up capability on its own (start() may not have set it).
      if (watching && _isLinux) _linuxKeyUp = true;
      return watching;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  WaylandHotkeyBinding get waylandBinding => _waylandBinding;

  @override
  String? get waylandTrigger => _waylandTrigger;

  @override
  set onWaylandBindingChanged(VoidCallback? handler) =>
      _onWaylandBindingChanged = handler;

  // Windows always ships the RawInput host; on Linux it depends on the
  // session (X11 vs. Wayland with/without portal) and is probed by [start].
  @override
  bool get supportsKeyUp => _isWindows || (_isLinux && _linuxKeyUp);

  @override
  bool get experimental => _isLinux && _linuxKeyUp;

  @override
  Future<void> start(HotKey hotKey, {String? description}) async {
    if (_isLinux) return _startLinux(hotKey, description);
    if (!supportsKeyUp) return;
    try {
      await _channel.invokeMethod<void>('start');
    } on Object catch (e) {
      // Missing-plugin / channel errors must never break hotkey registration —
      // hold-to-talk simply stays unavailable until the next attempt.
      _log.warning('Keyboard monitor start failed (key-up unavailable): $e');
    }
  }

  Future<void> _startLinux(HotKey hotKey, String? description) async {
    try {
      final reply = await _channel.invokeMethod<Object?>('start', {
        'trigger': xdgShortcutTrigger(hotKey),
        'description': ?description,
      });
      _applyLinuxCapabilities(reply);
    } on Object catch (e) {
      // MissingPluginException (runner without the host) or a channel error:
      // keep the toggle-only behaviour rather than failing registration.
      _linuxKeyUp = false;
      _log.info('Linux key-up monitor unavailable (toggle only): $e');
    }
  }

  void _applyLinuxCapabilities(Object? reply) {
    final x11 = reply is Map && reply['x11'] == true;
    final portal = reply is Map && reply['portal'] == true;
    _linuxKeyUp = x11 || portal;
    final binding = waylandHotkeyBindingFrom(reply);
    _log.info(
      'Linux key-up capability: x11=$x11 portal=$portal '
      'wayland=${binding.name}',
    );
    final raw = reply is Map ? reply['triggerDescription'] : null;
    final trigger = raw is String && raw.isNotEmpty ? raw : null;
    if (binding == _waylandBinding && trigger == _waylandTrigger) return;
    _waylandBinding = binding;
    _waylandTrigger = trigger;
    _onWaylandBindingChanged?.call();
  }

  @override
  Future<bool> armRelease({
    Iterable<HotKeyModifier> modifiers = const [],
  }) async {
    if (!supportsKeyUp) return true;
    try {
      // Hosts that predate the reply send nothing; treat that as "held".
      return await _channel.invokeMethod<bool>('armRelease', {
            'modifiers': armedModifierMask(modifiers),
          }) ??
          true;
    } on Object catch (e) {
      _log.debug('Keyboard monitor armRelease failed (non-fatal): $e');
      return true;
    }
  }

  @override
  Future<void> stop() async {
    // Linux always forwards the stop: a native watch started by watchModifier
    // runs without key-up capability too and must not outlive the hotkey.
    if (!supportsKeyUp && !_isLinux) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on Object catch (e) {
      _log.debug('Keyboard monitor stop failed (non-fatal): $e');
    }
  }

  /// The press length a native `onKeyUp` carries (`pressMs`), or null when the
  /// host could not time the press.
  @visibleForTesting
  static Duration? pressedForKeyUp(Object? arguments) {
    if (arguments is! Map) return null;
    final ms = arguments['pressMs'];
    return ms is int ? Duration(milliseconds: ms) : null;
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onKeyUp':
        _onKeyUp?.call(pressedForKeyUp(call.arguments));
      case 'onKeyDown':
        _onKeyDown?.call();
      case 'onCapabilities':
        if (_isLinux) _applyLinuxCapabilities(call.arguments);
      default:
        final input = modifierInputForNativeCall(call.method);
        if (input != null) _onModifierInput?.call(input);
    }
  }
}

/// The modifier bits the Windows host reads in `armRelease` (kArmedCtrl,
/// kArmedAlt, kArmedShift, kArmedWin in keyboard_monitor_host.cpp). Other
/// modifiers have no bit and count as none.
int armedModifierMask(Iterable<HotKeyModifier> modifiers) {
  var mask = 0;
  for (final modifier in modifiers) {
    mask |= switch (modifier) {
      HotKeyModifier.control => 0x1,
      HotKeyModifier.alt => 0x2,
      HotKeyModifier.shift => 0x4,
      HotKeyModifier.meta => 0x8,
      _ => 0,
    };
  }
  return mask;
}

const _xdgModifierOrder = <(HotKeyModifier, String)>[
  (HotKeyModifier.control, 'CTRL'),
  (HotKeyModifier.alt, 'ALT'),
  (HotKeyModifier.shift, 'SHIFT'),
  (HotKeyModifier.meta, 'LOGO'),
];

final _xdgNamedKeys = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.space: 'space',
  LogicalKeyboardKey.enter: 'Return',
  LogicalKeyboardKey.escape: 'Escape',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.backspace: 'BackSpace',
  LogicalKeyboardKey.insert: 'Insert',
  LogicalKeyboardKey.delete: 'Delete',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.pageUp: 'Page_Up',
  LogicalKeyboardKey.pageDown: 'Page_Down',
  LogicalKeyboardKey.arrowUp: 'Up',
  LogicalKeyboardKey.arrowDown: 'Down',
  LogicalKeyboardKey.arrowLeft: 'Left',
  LogicalKeyboardKey.arrowRight: 'Right',
  LogicalKeyboardKey.pause: 'Pause',
  LogicalKeyboardKey.scrollLock: 'Scroll_Lock',
};

final _fKeyLabel = RegExp(r'^F([1-9]|1[0-9]|2[0-4])$');
final _alnumLabel = RegExp(r'^[A-Za-z0-9]$');

/// [hotKey] as an XDG shortcut trigger (`CTRL+SHIFT+space`, see the
/// `shortcuts` spec of xdg-desktop-portal) — the portal's
/// `preferred_trigger`, so the Wayland binding proposes the same combination
/// as the X11 grab. `null` for keys without a known keysym; the portal then
/// lets the user pick one in its own dialog.
String? xdgShortcutTrigger(HotKey hotKey) {
  final key = hotKey.logicalKey;
  final label = key.keyLabel;
  final String keysym;
  if (_xdgNamedKeys[key] case final named?) {
    keysym = named;
  } else if (_fKeyLabel.hasMatch(label)) {
    keysym = label;
  } else if (_alnumLabel.hasMatch(label)) {
    keysym = label.toLowerCase();
  } else {
    return null;
  }
  final mods = hotKey.modifiers ?? const <HotKeyModifier>[];
  return [
    for (final (modifier, name) in _xdgModifierOrder)
      if (mods.contains(modifier)) name,
    keysym,
  ].join('+');
}
