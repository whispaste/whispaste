import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/logging/app_logger.dart';
import 'globe_key_action.dart';
import 'hotkey_observer_health.dart';
import 'tap_disabled_evidence.dart';

/// Single keys a user can assign as the dictation trigger, side-specific
/// (maintainer 2026-10-30). The names are shared with the native hosts (macOS
/// `ModifierKeyHost`, Windows and Linux keyboard hosts) and are stored.
enum ModifierHotkey {
  fn,
  leftShift,
  rightShift,
  leftControl,
  rightControl,
  leftAlt,
  rightAlt,
  leftMeta,
  rightMeta;

  /// Keys people also press for typing and shortcuts (all left keys, both
  /// Shift keys). A hold on them starts a recording only after
  /// [kBusyKeyHoldStartDelay] alone, so ⌘C or a capital letter never starts
  /// one.
  bool get isBusy => switch (this) {
    fn || rightControl || rightAlt || rightMeta => false,
    _ => true,
  };
}

/// Delay before a hold on a [ModifierHotkey.isBusy] key starts a recording.
const kBusyKeyHoldStartDelay = Duration(milliseconds: 250);

/// Raw input for the gesture layer: the watched key went down or up, or a
/// different key was pressed while it was held (which voids a tap).
enum ModifierInput { down, up, other }

/// Receives one [ModifierInput]. [pressed] comes only with [ModifierInput.up]:
/// how long the key was held, timed by the native host from the events' own
/// timestamps; null when the host could not time it.
typedef ModifierInputHandler =
    void Function(ModifierInput input, Duration? pressed);

/// The press length a native modifier release carries (`pressMs`), or null.
Duration? modifierPressedFromArgs(Object? arguments) {
  if (arguments is! Map) return null;
  final ms = arguments['pressMs'];
  return ms is int && ms >= 0 ? Duration(milliseconds: ms) : null;
}

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

/// Limits the log lines about a disabled event tap (#848). The first report
/// is logged at once; later ones at most once per [interval], with the number
/// of reports held back since. Pure: the caller passes the time.
class TapDisabledLogGate {
  TapDisabledLogGate({this.interval = const Duration(seconds: 30)});

  final Duration interval;
  DateTime? _lastLogged;
  int _held = 0;

  /// Returns the number of reports this line stands for (1 or more) when
  /// [now] should be logged, or 0 when the report is held back.
  int report(DateTime now) {
    final last = _lastLogged;
    if (last != null && now.difference(last) < interval) {
      _held++;
      return 0;
    }
    final n = _held + 1;
    _held = 0;
    _lastLogged = now;
    return n;
  }
}

/// The log line for a `tapDisabled` host event, or null when [args] is not
/// one. Carries counters and the reason only, never key data.
String? tapDisabledLogLine(Object? args, int reports) {
  if (args is! Map || args['type'] != 'tapDisabled') return null;
  final reason = args['reason'] == 'userInput' ? 'userInput' : 'timeout';
  final count = args['count'];
  final since = args['sinceLastMs'];
  return 'event tap disabled by system ($reason) and re-enabled; '
      'count since start: ${count is int ? count : '?'}'
      '${since is int ? ', ${since}ms after the previous' : ''}'
      '${reports > 1 ? ', $reports reports in this interval' : ''}';
}

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
  ModifierKeyMonitor({
    bool? isMacOS,
    MethodChannel? channel,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.whispaste.modifier_monitor',
  );

  static final _log = AppLogger('ModifierKeyMonitor');

  final bool _isMacOS;
  final MethodChannel _channel;
  final TapDisabledLogGate _tapLogGate = TapDisabledLogGate();

  final DateTime Function() _now;

  /// Receives every observed input, synchronously from the platform event.
  ModifierInputHandler? onInput;

  /// Whether macOS currently grants Input Monitoring, read live without a
  /// prompt. `null` off macOS or when the host does not answer.
  Future<bool?> listenAccess() async {
    if (!_isMacOS) return null;
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>('status');
      final access = reply?['listenAccess'];
      return access is bool ? access : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// The macOS setting "Press 🌐 key to" (#778), read only. [GlobeKeyAction.none]
  /// off macOS (no conflict), [GlobeKeyAction.unknown] when the host does not
  /// answer, so the generic Fn warning still shows.
  Future<GlobeKeyAction> globeKeyAction() async {
    if (!_isMacOS) return GlobeKeyAction.none;
    try {
      return globeKeyActionFromRaw(
        await _channel.invokeMethod<Object?>('globeKeyAction'),
      );
    } on PlatformException {
      return GlobeKeyAction.unknown;
    } on MissingPluginException {
      return GlobeKeyAction.unknown;
    }
  }

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
      // The channel has one handler. The instance that starts observing owns
      // it, so another instance on the same channel (the permission flow)
      // cannot take the events over.
      _channel.setMethodCallHandler(handleNativeCall);
      final started =
          await _channel.invokeMethod<bool>('start', {'key': key.name}) ??
          false;
      _log.info('event tap start (${key.name}): ${started ? 'ok' : 'failed'}');
      return started;
    } on PlatformException catch (e) {
      _log.info('event tap start (${key.name}) failed: ${e.message ?? e.code}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Whether the watched key is physically down right now (#791), read from
  /// the hardware state. [keyCode] is the macOS virtual key code of a
  /// registered key combination's main key; without it the host reads the
  /// modifier it observes. `null` when nothing is watched, without the Input Monitoring grant, on a host that
  /// predates the call, or off macOS: the caller then keeps waiting for the
  /// release event.
  Future<bool?> isHeld({int? keyCode}) async {
    if (!_isMacOS) return null;
    try {
      return await _channel.invokeMethod<bool>(
        'isHeld',
        keyCode == null ? null : {'keyCode': keyCode},
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// The observer's health (#773), read from the host's `status` reply:
  /// `listenAccess` false means the Input Monitoring grant was withdrawn,
  /// `tapActive` false (once the host reports it) a tap the system disabled.
  /// [ObserverHealth.unknown] off macOS and when the host does not answer.
  Future<ObserverHealth> health() async {
    if (!_isMacOS) return ObserverHealth.unknown;
    try {
      return observerHealthFromReply(
        await _channel.invokeMapMethod<String, Object?>('status'),
      );
    } on PlatformException {
      return ObserverHealth.unknown;
    } on MissingPluginException {
      return ObserverHealth.unknown;
    } on Object {
      return ObserverHealth.unknown;
    }
  }

  /// Whether [isHeld] can answer on this platform (macOS).
  bool get supportsHeld => _isMacOS;

  Future<void> stop() async {
    if (!_isMacOS) return;
    try {
      await _channel.invokeMethod<void>('stop');
      _log.info('event tap stopped');
    } on PlatformException catch (e) {
      _log.debug('modifier monitor stop failed: ${e.code}');
    } on MissingPluginException {
      _log.debug('modifier monitor host not registered; nothing to stop');
    }
  }

  /// The native event time (`atMs`) of the event being delivered right now,
  /// or null outside a callback and for events without a stamp. Same meaning
  /// as `ChannelKeyboardUpMonitor.lastEventAt`.
  Duration? get lastEventAt => _lastEventAt;
  Duration? _lastEventAt;

  /// The press length of the release being delivered right now, or null.
  Duration? get lastPressed => _lastPressed;
  Duration? _lastPressed;

  /// Handles one event from the macOS host. Public for tests.
  @visibleForTesting
  Future<void> handleNativeCall(MethodCall call) async {
    if (call.method != 'event') return;
    final args = call.arguments;
    final at = args is Map ? args['atMs'] : null;
    _lastEventAt = at is int && at >= 0 ? Duration(milliseconds: at) : null;
    try {
      _deliver(args);
    } finally {
      _lastEventAt = null;
      _lastPressed = null;
    }
  }

  void _deliver(Object? args) {
    final type = args is Map ? args['type'] : null;
    if (type == 'tapDisabled') {
      tapDisabledEvidence.record(_now());
      final reports = _tapLogGate.report(_now());
      final line = reports > 0 ? tapDisabledLogLine(args, reports) : null;
      if (line != null) _log.warning(line);
      return;
    }
    final input = switch (type) {
      'down' => ModifierInput.down,
      'up' => ModifierInput.up,
      'other' => ModifierInput.other,
      _ => null,
    };
    if (input == null) return;
    final pressed = input == ModifierInput.up
        ? modifierPressedFromArgs(args)
        : null;
    _lastPressed = pressed;
    onInput?.call(input, pressed);
  }
}
