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

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../core/logging/app_logger.dart';

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
  /// No-op when [supportsKeyUp] is `false`.
  Future<void> start(HotKey hotKey);

  /// Arms the release-watch — call when the hotkey fires (key-down). The native
  /// side snapshots the currently-held main key so its release ends the hold.
  ///
  /// Required because `RegisterHotKey` suppresses the hotkey key's DOWN from
  /// the RawInput stream, so the main key cannot be detected by observation
  /// alone (#39). No-op when [supportsKeyUp] is `false`.
  Future<void> armRelease();

  /// Stops observing. No-op when not started.
  Future<void> stop();

  /// Whether the key-up this monitor provides is experimental (Linux, not
  /// verified on a real GNOME/KDE desktop yet) — the settings UI labels the
  /// push-to-talk option accordingly.
  bool get experimental;

  /// Called when the watched hotkey's main key is released.
  set onKeyUp(VoidCallback? handler);

  /// Called when the monitor itself observes the hotkey press — only the
  /// Linux portal path does, since the compositor (not the X11 grab) owns the
  /// shortcut there.
  set onKeyDown(VoidCallback? handler);
}

/// No-op monitor for platforms that already have key-up (macOS) or have no
/// native host. [supportsKeyUp] is always `false`.
class NoopKeyboardUpMonitor implements KeyboardUpMonitor {
  @override
  bool get supportsKeyUp => false;

  @override
  bool get experimental => false;

  @override
  Future<void> start(HotKey hotKey) async {}

  @override
  Future<void> armRelease() async {}

  @override
  Future<void> stop() async {}

  @override
  set onKeyUp(VoidCallback? handler) {}

  @override
  set onKeyDown(VoidCallback? handler) {}
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

  VoidCallback? _onKeyUp;
  VoidCallback? _onKeyDown;

  @override
  set onKeyUp(VoidCallback? handler) => _onKeyUp = handler;

  @override
  set onKeyDown(VoidCallback? handler) => _onKeyDown = handler;

  // Windows always ships the RawInput host; on Linux it depends on the
  // session (X11 vs. Wayland with/without portal) and is probed by [start].
  @override
  bool get supportsKeyUp => _isWindows || (_isLinux && _linuxKeyUp);

  @override
  bool get experimental => _isLinux && _linuxKeyUp;

  @override
  Future<void> start(HotKey hotKey) async {
    if (_isLinux) return _startLinux(hotKey);
    if (!supportsKeyUp) return;
    try {
      await _channel.invokeMethod<void>('start');
    } on Object catch (e) {
      // Missing-plugin / channel errors must never break hotkey registration —
      // hold-to-talk simply stays unavailable until the next attempt.
      _log.warning('Keyboard monitor start failed (key-up unavailable): $e');
    }
  }

  Future<void> _startLinux(HotKey hotKey) async {
    try {
      final reply = await _channel.invokeMethod<Object?>('start', {
        'trigger': xdgShortcutTrigger(hotKey),
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
    _log.info('Linux key-up capability: x11=$x11 portal=$portal');
  }

  @override
  Future<void> armRelease() async {
    if (!supportsKeyUp) return;
    try {
      await _channel.invokeMethod<void>('armRelease');
    } on Object catch (e) {
      _log.debug('Keyboard monitor armRelease failed (non-fatal): $e');
    }
  }

  @override
  Future<void> stop() async {
    if (!supportsKeyUp) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on Object catch (e) {
      _log.debug('Keyboard monitor stop failed (non-fatal): $e');
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onKeyUp':
        _onKeyUp?.call();
      case 'onKeyDown':
        _onKeyDown?.call();
      case 'onCapabilities':
        if (_isLinux) _applyLinuxCapabilities(call.arguments);
    }
  }
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
