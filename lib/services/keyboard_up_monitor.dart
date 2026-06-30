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
/// from the registrar and needs no monitor; Linux has no implementation yet.
library;

import 'dart:io';

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

  /// Called when the watched hotkey's main key is released.
  set onKeyUp(VoidCallback? handler);
}

/// No-op monitor for platforms that already have key-up (macOS) or have no
/// implementation (Linux). [supportsKeyUp] is always `false`.
class NoopKeyboardUpMonitor implements KeyboardUpMonitor {
  @override
  bool get supportsKeyUp => false;

  @override
  Future<void> start(HotKey hotKey) async {}

  @override
  Future<void> armRelease() async {}

  @override
  Future<void> stop() async {}

  @override
  set onKeyUp(VoidCallback? handler) {}
}

/// Production monitor backed by the native `com.whispaste.keyboard_monitor`
/// channel (Windows RawInput host). Selected only on Windows; elsewhere the
/// service uses a [NoopKeyboardUpMonitor].
class ChannelKeyboardUpMonitor implements KeyboardUpMonitor {
  ChannelKeyboardUpMonitor() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final _log = AppLogger('KeyboardUpMonitor');

  static const MethodChannel _channel = MethodChannel(
    'com.whispaste.keyboard_monitor',
  );

  VoidCallback? _onKeyUp;

  @override
  set onKeyUp(VoidCallback? handler) => _onKeyUp = handler;

  // Only Windows ships the native RawInput host; macOS uses the registrar's
  // key-up and Linux has none.
  @override
  bool get supportsKeyUp => Platform.isWindows;

  @override
  Future<void> start(HotKey hotKey) async {
    if (!supportsKeyUp) return;
    try {
      await _channel.invokeMethod<void>('start');
    } on Object catch (e) {
      // Missing-plugin / channel errors must never break hotkey registration —
      // hold-to-talk simply stays unavailable until the next attempt.
      _log.warning('Keyboard monitor start failed (key-up unavailable): $e');
    }
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
    if (call.method == 'onKeyUp') {
      _onKeyUp?.call();
    }
  }
}
