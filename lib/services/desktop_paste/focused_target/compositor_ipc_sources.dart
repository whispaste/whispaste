/// Focus sources for compositors with a local IPC socket: Sway (i3 IPC),
/// Hyprland and niri. Each request is one short round trip on a Unix socket
/// the compositor exports to the session through an environment variable.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/logging/app_logger.dart';
import 'focused_target.dart';

final _log = AppLogger('FocusedTarget');

/// How long one IPC request may take before the source reports no target.
const focusedTargetIpcTimeout = Duration(milliseconds: 300);

Future<T?> _guard<T>(String source, Future<T?> Function() request) async {
  try {
    return await request().timeout(focusedTargetIpcTimeout);
  } on Object catch (e) {
    // Any socket or parse failure means "target unknown", never a failed paste.
    _log.debug('$source: focused window unknown', e);
    return null;
  }
}

Future<Socket> _connect(String path) =>
    Socket.connect(InternetAddress(path, type: InternetAddressType.unix), 0);

/// Sway and other i3-IPC compositors (`SWAYSOCK`): GET_TREE, then the node
/// marked `focused`.
class SwayFocusSource implements FocusedTargetSource {
  SwayFocusSource(this.socketPath);

  final String socketPath;

  static const _magic = 'i3-ipc';
  static const _getTree = 4;

  @override
  String get name => 'sway';

  @override
  Future<FocusedTarget?> focusedTarget() => _guard(name, () async {
    final socket = await _connect(socketPath);
    try {
      final header = ByteData(14);
      for (var i = 0; i < _magic.length; i++) {
        header.setUint8(i, _magic.codeUnitAt(i));
      }
      header
        ..setUint32(6, 0, Endian.host)
        ..setUint32(10, _getTree, Endian.host);
      socket.add(header.buffer.asUint8List());
      await socket.flush();
      final reply = await _readI3Reply(socket);
      return focusedNodeTarget(jsonDecode(reply), source: name);
    } finally {
      socket.destroy();
    }
  });

  static Future<String> _readI3Reply(Stream<List<int>> socket) async {
    final buffer = BytesBuilder(copy: false);
    int? length;
    await for (final chunk in socket) {
      buffer.add(chunk);
      if (length == null && buffer.length >= 14) {
        final bytes = buffer.toBytes();
        length = ByteData.sublistView(bytes, 6, 10).getUint32(0, Endian.host);
      }
      if (length != null && buffer.length >= 14 + length) break;
    }
    final bytes = buffer.takeBytes();
    if (length == null || bytes.length < 14 + length) {
      throw const FormatException('short i3-ipc reply');
    }
    return utf8.decode(bytes.sublist(14, 14 + length));
  }

  /// The focused window in a GET_TREE answer. Native Wayland windows carry
  /// `app_id`; XWayland windows `window_properties` with class and instance.
  static FocusedTarget? focusedNodeTarget(
    Object? tree, {
    String source = 'sway',
  }) {
    final node = _findFocused(tree);
    if (node == null) return null;
    final props = node['window_properties'];
    if (props is Map) {
      return FocusedTarget.from(
        [_s(props['instance']), _s(props['class']), _s(node['app_id'])],
        source: source,
        clientType: FocusedClientType.x11,
      );
    }
    return FocusedTarget.from(
      [_s(node['app_id'])],
      source: source,
      clientType: FocusedClientType.wayland,
    );
  }

  static Map<Object?, Object?>? _findFocused(Object? node) {
    if (node is! Map) return null;
    final type = node['type'];
    if (node['focused'] == true && (type == 'con' || type == 'floating_con')) {
      return node;
    }
    for (final key in const ['nodes', 'floating_nodes']) {
      final children = node[key];
      if (children is! List) continue;
      for (final child in children) {
        final hit = _findFocused(child);
        if (hit != null) return hit;
      }
    }
    return null;
  }
}

/// Hyprland (`HYPRLAND_INSTANCE_SIGNATURE`): `j/activewindow` on the
/// request socket, which answers with one JSON object and closes.
class HyprlandFocusSource implements FocusedTargetSource {
  HyprlandFocusSource(this.socketPath);

  /// The socket for [signature]: `$XDG_RUNTIME_DIR/hypr/<sig>/.socket.sock`
  /// since Hyprland 0.40, `/tmp/hypr/<sig>/.socket.sock` before.
  static String? socketFor(Map<String, String> env) {
    final signature = env['HYPRLAND_INSTANCE_SIGNATURE'];
    if (signature == null || signature.isEmpty) return null;
    final runtime = env['XDG_RUNTIME_DIR'];
    final current = runtime == null
        ? null
        : '$runtime/hypr/$signature/.socket.sock';
    if (current != null &&
        FileSystemEntity.typeSync(current) ==
            FileSystemEntityType.unixDomainSock) {
      return current;
    }
    return '/tmp/hypr/$signature/.socket.sock';
  }

  final String socketPath;

  @override
  String get name => 'hyprland';

  @override
  Future<FocusedTarget?> focusedTarget() => _guard(name, () async {
    final socket = await _connect(socketPath);
    try {
      socket.add(utf8.encode('j/activewindow'));
      await socket.flush();
      final reply = await utf8.decodeStream(socket);
      return activeWindowTarget(jsonDecode(reply), source: name);
    } finally {
      socket.destroy();
    }
  });

  /// `class` is the app id (Wayland) or the WM_CLASS class (XWayland);
  /// Hyprland reports no instance name. Without focus the object is empty.
  static FocusedTarget? activeWindowTarget(
    Object? window, {
    String source = 'hyprland',
  }) {
    if (window is! Map) return null;
    final xwayland = window['xwayland'];
    return FocusedTarget.from(
      [_s(window['class']), _s(window['initialClass'])],
      source: source,
      clientType: xwayland == true
          ? FocusedClientType.x11
          : xwayland == false
          ? FocusedClientType.wayland
          : FocusedClientType.unknown,
    );
  }
}

/// niri (`NIRI_SOCKET`): the `"FocusedWindow"` request, answered with one
/// JSON line `{"Ok":{"FocusedWindow":{…}|null}}`.
class NiriFocusSource implements FocusedTargetSource {
  NiriFocusSource(this.socketPath);

  final String socketPath;

  @override
  String get name => 'niri';

  @override
  Future<FocusedTarget?> focusedTarget() => _guard(name, () async {
    final socket = await _connect(socketPath);
    try {
      socket.add(utf8.encode('"FocusedWindow"\n'));
      await socket.flush();
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first;
      return focusedWindowTarget(jsonDecode(line), source: name);
    } finally {
      socket.destroy();
    }
  });

  /// niri runs X11 apps through xwayland-satellite, which reports them with
  /// their WM_CLASS as app id, so the type stays unknown.
  static FocusedTarget? focusedWindowTarget(
    Object? reply, {
    String source = 'niri',
  }) {
    if (reply is! Map) return null;
    final ok = reply['Ok'];
    if (ok is! Map) return null;
    final window = ok['FocusedWindow'];
    if (window is! Map) return null;
    return FocusedTarget.from([_s(window['app_id'])], source: source);
  }
}

String? _s(Object? value) => value is String ? value : null;
