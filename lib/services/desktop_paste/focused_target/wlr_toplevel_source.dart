/// Focus source for wlroots-style compositors (labwc, Wayfire, river with
/// the protocol, and Sway/niri/Hyprland when their IPC socket is out of
/// reach, e.g. inside Flatpak): `zwlr_foreign_toplevel_manager_v1` on the
/// session's own Wayland socket. Speaks the Wayland wire format directly;
/// one lookup is a fresh connection with two round trips.
///
/// The protocol carries one name per window and no client type: the app id
/// for Wayland windows, the WM_CLASS class for XWayland ones (checked
/// against sway 1.x, test/scripts/focus_sources_e2e.sh).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/logging/app_logger.dart';
import 'compositor_ipc_sources.dart' show focusedTargetIpcTimeout;
import 'focused_target.dart';

final _log = AppLogger('FocusedTarget');

class WlrToplevelFocusSource implements FocusedTargetSource {
  WlrToplevelFocusSource(this.socketPath);

  final String socketPath;

  static const managerInterface = 'zwlr_foreign_toplevel_manager_v1';

  /// `zwlr_foreign_toplevel_handle_v1.state` value for the focused window.
  static const stateActivated = 2;

  @override
  String get name => 'wlr-toplevel';

  /// `WAYLAND_DISPLAY` as a path: absolute as given, else under
  /// `XDG_RUNTIME_DIR` (default name `wayland-0`).
  static String? socketFor(Map<String, String> env) {
    final display = env['WAYLAND_DISPLAY'];
    final name = (display == null || display.isEmpty) ? 'wayland-0' : display;
    if (name.startsWith('/')) return name;
    final runtime = env['XDG_RUNTIME_DIR'];
    if (runtime == null || runtime.isEmpty) return null;
    return '$runtime/$name';
  }

  /// Whether the compositor offers the toplevel manager to this client.
  Future<bool> isAvailable() async {
    try {
      final session = await _Session.open(socketPath);
      try {
        return await session
            .managerGlobal()
            .then((g) => g != null)
            .timeout(focusedTargetIpcTimeout);
      } finally {
        session.close();
      }
    } on Object catch (e) {
      _log.debug('$name: manager unknown', e);
      return false;
    }
  }

  @override
  Future<FocusedTarget?> focusedTarget() async {
    try {
      final session = await _Session.open(socketPath);
      try {
        return await session.activatedAppId().timeout(focusedTargetIpcTimeout);
      } finally {
        session.close();
      }
    } on Object catch (e) {
      // No socket, no manager or a slow compositor: target unknown.
      _log.debug('$name: focused window unknown', e);
      return null;
    }
  }
}

/// One Wayland message: sender object, opcode and the raw argument bytes.
@visibleForTesting
class WaylandMessage {
  WaylandMessage(this.sender, this.opcode, this.args);

  final int sender;
  final int opcode;
  final ByteData args;

  /// Splits [buffer] into whole messages; the rest stays in [buffer].
  static List<WaylandMessage> drain(BytesBuilder buffer) {
    final bytes = buffer.takeBytes();
    final out = <WaylandMessage>[];
    var offset = 0;
    while (bytes.length - offset >= 8) {
      final view = ByteData.sublistView(bytes, offset);
      final sender = view.getUint32(0, Endian.little);
      final word = view.getUint32(4, Endian.little);
      final size = word >> 16;
      if (size < 8) throw const FormatException('bad Wayland message size');
      if (bytes.length - offset < size) break;
      out.add(
        WaylandMessage(
          sender,
          word & 0xffff,
          ByteData.sublistView(bytes, offset + 8, offset + size),
        ),
      );
      offset += size;
    }
    buffer.add(bytes.sublist(offset));
    return out;
  }

  /// Encodes a request. [args] are `int` (uint32) or `String`.
  static Uint8List encode(int object, int opcode, List<Object> args) {
    final body = BytesBuilder();
    for (final arg in args) {
      if (arg is int) {
        body.add(_u32(arg));
      } else if (arg is String) {
        final text = utf8.encode(arg);
        body
          ..add(_u32(text.length + 1))
          ..add(text)
          ..add(Uint8List(_pad(text.length + 1) - text.length));
      }
    }
    final size = 8 + body.length;
    return (BytesBuilder()
          ..add(_u32(object))
          ..add(_u32(size << 16 | opcode))
          ..add(body.takeBytes()))
        .takeBytes();
  }

  int u32(int index) => args.getUint32(index * 4, Endian.little);

  /// The string argument starting at byte [offset]; returns it and the
  /// offset after it.
  (String, int) string(int offset) {
    final length = args.getUint32(offset, Endian.little);
    final start = offset + 4;
    final text = length == 0
        ? ''
        : utf8.decode(
            args.buffer.asUint8List(args.offsetInBytes + start, length - 1),
            allowMalformed: true,
          );
    return (text, start + _pad(length));
  }

  /// The array argument at byte [offset] as uint32 values.
  List<int> u32Array(int offset) {
    final length = args.getUint32(offset, Endian.little);
    return [
      for (var i = 0; i < length ~/ 4; i++)
        args.getUint32(offset + 4 + i * 4, Endian.little),
    ];
  }

  static Uint8List _u32(int value) =>
      (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

  static int _pad(int length) => (length + 3) & ~3;
}

class _Global {
  _Global(this.name, this.version);
  final int name;
  final int version;
}

class _Toplevel {
  String? appId;
  bool activated = false;
}

/// One short-lived client connection. Object ids: 1 display, 2 registry,
/// 3 and 5 sync callbacks, 4 the toplevel manager; handles get the ids the
/// compositor allocates.
class _Session {
  _Session(this._socket) {
    _subscription = _socket.listen(
      (chunk) {
        _buffer.add(chunk);
        try {
          WaylandMessage.drain(_buffer).forEach(_handle);
        } on Object catch (e) {
          _fail(e);
        }
      },
      onError: _fail,
      onDone: () => _fail(const SocketException('Wayland socket closed')),
    );
  }

  static const _display = 1;
  static const _registry = 2;
  static const _globalsDone = 3;
  static const _manager = 4;
  static const _toplevelsDone = 5;

  final Socket _socket;
  late final StreamSubscription<List<int>> _subscription;
  final _buffer = BytesBuilder(copy: false);
  final _toplevels = <int, _Toplevel>{};
  _Global? _managerGlobal;
  final _globals = Completer<_Global?>();
  final _done = Completer<FocusedTarget?>();

  static Future<_Session> open(String path) async => _Session(
    await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    ),
  );

  void _send(int object, int opcode, List<Object> args) =>
      _socket.add(WaylandMessage.encode(object, opcode, args));

  Future<_Global?> managerGlobal() {
    _send(_display, 1, [_registry]); // wl_display.get_registry
    _send(_display, 0, [_globalsDone]); // wl_display.sync
    return _globals.future;
  }

  Future<FocusedTarget?> activatedAppId() async {
    final global = await managerGlobal();
    if (global == null) return null;
    // wl_registry.bind(name, interface, version, new_id)
    _send(_registry, 0, [
      global.name,
      WlrToplevelFocusSource.managerInterface,
      global.version < 3 ? global.version : 3,
      _manager,
    ]);
    _send(_display, 0, [_toplevelsDone]);
    return _done.future;
  }

  void _handle(WaylandMessage m) {
    switch (m.sender) {
      case _display when m.opcode == 0: // wl_display.error
        final (message, _) = m.string(8);
        _fail(StateError('Wayland error ${m.u32(1)}: $message'));
      case _registry when m.opcode == 0: // wl_registry.global
        final (interface, next) = m.string(4);
        if (interface == WlrToplevelFocusSource.managerInterface) {
          _managerGlobal = _Global(
            m.u32(0),
            m.args.getUint32(next, Endian.little),
          );
        }
      case _globalsDone:
        if (!_globals.isCompleted) _globals.complete(_managerGlobal);
      case _manager when m.opcode == 0: // manager.toplevel(new_id)
        _toplevels[m.u32(0)] = _Toplevel();
      case _toplevelsDone:
        if (!_done.isCompleted) _done.complete(_activatedTarget());
      default:
        final toplevel = _toplevels[m.sender];
        if (toplevel == null) return;
        switch (m.opcode) {
          case 1: // handle.app_id; opcode 0 (title) is never read
            toplevel.appId = m.string(0).$1;
          case 4: // handle.state
            toplevel.activated = m
                .u32Array(0)
                .contains(WlrToplevelFocusSource.stateActivated);
          case 6: // handle.closed
            _toplevels.remove(m.sender);
        }
    }
  }

  FocusedTarget? _activatedTarget() {
    for (final toplevel in _toplevels.values) {
      if (toplevel.activated) {
        return FocusedTarget.from([toplevel.appId], source: 'wlr-toplevel');
      }
    }
    return null;
  }

  void _fail(Object error) {
    if (!_globals.isCompleted) _globals.completeError(error);
    if (!_done.isCompleted) _done.completeError(error);
    // Nobody may await the other future; keep its error from going unhandled.
    _globals.future.ignore();
    _done.future.ignore();
  }

  void close() {
    unawaited(_subscription.cancel());
    _socket.destroy();
  }
}
