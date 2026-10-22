import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/logging/app_logger.dart';

/// Modifier-only hotkeys a user can assign. The names are shared with the
/// native hosts (macOS `ModifierKeyHost`, Windows and Linux keyboard hosts).
enum ModifierHotkey { rightControl, rightAlt, rightMeta, fn }

/// Raw input for the gesture layer: the watched key went down or up, or a
/// different key was pressed while it was held (which voids a tap).
enum ModifierInput { down, up, other }

/// Whether [key] can be assigned on this platform. Fn exists on macOS only.
bool modifierHotkeySupported(ModifierHotkey key, {required bool isMacOS}) =>
    key != ModifierHotkey.fn || isMacOS;

/// Maps a method name from the Windows or Linux keyboard host to an input.
/// Returns null for unrelated methods.
ModifierInput? modifierInputForNativeCall(String method) => switch (method) {
  'onModifierDown' => ModifierInput.down,
  'onModifierUp' => ModifierInput.up,
  'onOtherKey' => ModifierInput.other,
  _ => null,
};

/// Observes a modifier-only hotkey on macOS through its own channel.
///
/// Uses a listen-only event tap, which needs the Input Monitoring grant
/// (`CGPreflightListenEventAccess`). The grant is asked only after the user
/// has chosen such a gesture and has seen the explanation. Apple's
/// documentation was not conclusive on Input Monitoring for sandboxed apps,
/// so this path is verified on the Mac App Store build (plan item 16a).
///
/// Windows and Linux do not use this class: their hosts deliver the same
/// inputs on `com.whispaste.keyboard_monitor`, where the existing
/// `ChannelKeyboardUpMonitor` owns the one method-call handler.
class ModifierKeyMonitor {
  ModifierKeyMonitor({bool? isMacOS, MethodChannel? channel})
    : _isMacOS = isMacOS ?? Platform.isMacOS,
      _channel = channel ?? _defaultChannel {
    if (_isMacOS) _channel.setMethodCallHandler(handleNativeCall);
  }

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.whispaste.modifier_monitor',
  );

  static final _log = AppLogger('ModifierKeyMonitor');

  final bool _isMacOS;
  final MethodChannel _channel;

  /// Receives every observed input, synchronously from the platform event.
  ValueChanged<ModifierInput>? onInput;

  /// Shows the system Input Monitoring prompt. Call only after the user has
  /// seen the explanation for a modifier gesture. Returns the state the
  /// system reports right away; a fresh grant may need a restart to apply.
  Future<bool> requestAccess() async {
    if (!_isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>('requestListenAccess') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Starts observing [key]. Returns false when the platform cannot observe
  /// it (no Input Monitoring grant, the tap could not be created, or not
  /// macOS). The caller then keeps the normal key combination and shows the
  /// hint instead.
  Future<bool> start(ModifierHotkey key) async {
    if (!_isMacOS) return false;
    try {
      final status = await _channel.invokeMapMethod<String, Object?>('status');
      if (status?['listenAccess'] != true) return false;
      return await _channel.invokeMethod<bool>('start', {'key': key.name}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> stop() async {
    if (!_isMacOS) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      _log.debug('modifier monitor stop failed: ${e.code}');
    } on MissingPluginException {
      _log.debug('modifier monitor host not registered; nothing to stop');
    }
  }

  /// Handles one event from the macOS host. Public for tests.
  @visibleForTesting
  Future<void> handleNativeCall(MethodCall call) async {
    if (call.method != 'event') return;
    final args = call.arguments;
    final type = args is Map ? args['type'] : null;
    final input = switch (type) {
      'down' => ModifierInput.down,
      'up' => ModifierInput.up,
      'other' => ModifierInput.other,
      _ => null,
    };
    if (input != null) onInput?.call(input);
  }
}
