/// V1 Wayland: the wlr foreign-toplevel focus source against a fake
/// compositor that speaks the Wayland wire format on a Unix socket.
@TestOn('linux || mac-os')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/focused_target/compositor_ipc_sources.dart';
import 'package:whispaste/services/desktop_paste/focused_target/focused_target.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart';
import 'package:whispaste/services/desktop_paste/focused_target/wlr_toplevel_source.dart';

class _Window {
  const _Window(this.appId, {this.activated = false});
  final String appId;
  final bool activated;
}

/// Plays a wlroots compositor: answers get_registry with its globals, sync
/// with done, and a bind of the toplevel manager with one handle per window.
class _FakeCompositor {
  _FakeCompositor(this.windows, {this.offerManager = true, this.error = false});

  List<_Window> windows;
  final bool offerManager;
  final bool error;
  final requests = <String>[];
  late ServerSocket _server;

  Future<String> start(Directory dir) async {
    final path = '${dir.path}/wayland-test';
    _server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    _server.listen(_serve);
    return path;
  }

  Future<void> stop() => _server.close();

  void _serve(Socket client) {
    final buffer = BytesBuilder(copy: false);
    var registry = 0;
    client.listen((chunk) {
      buffer.add(chunk);
      for (final m in WaylandMessage.drain(buffer)) {
        if (m.sender == 1 && m.opcode == 1) {
          registry = m.u32(0);
          requests.add('get_registry');
          if (error) {
            client.add(
              _event(1, 0, [_u32(1), _u32(1), _string('invalid object')]),
            );
            continue;
          }
          client.add(
            _event(registry, 0, [_u32(1), _string('wl_seat'), _u32(7)]),
          );
          if (offerManager) {
            client.add(
              _event(registry, 0, [
                _u32(9),
                _string(WlrToplevelFocusSource.managerInterface),
                _u32(3),
              ]),
            );
          }
        } else if (m.sender == 1 && m.opcode == 0) {
          requests.add('sync');
          client.add(_event(m.u32(0), 0, [_u32(1)]));
        } else if (m.sender == registry && m.opcode == 0) {
          final (interface, next) = m.string(4);
          final version = m.args.getUint32(next, Endian.little);
          final manager = m.args.getUint32(next + 4, Endian.little);
          requests.add('bind ${m.u32(0)} $interface v$version');
          var id = 0xff000000;
          for (final w in windows) {
            client
              ..add(_event(manager, 0, [_u32(id)]))
              ..add(_event(id, 0, [_string('secret title')]))
              ..add(_event(id, 1, [_string(w.appId)]))
              ..add(
                _event(id, 4, [
                  _array([if (w.activated) 2, 0]),
                ]),
              )
              ..add(_event(id, 5, []));
            id++;
          }
        }
      }
    });
  }

  static Uint8List _u32(int v) =>
      (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

  static Uint8List _string(String s) {
    final bytes = utf8.encode(s);
    final padded = (bytes.length + 1 + 3) & ~3;
    return Uint8List.fromList([
      ..._u32(bytes.length + 1),
      ...bytes,
      ...List.filled(padded - bytes.length, 0),
    ]);
  }

  static Uint8List _array(List<int> values) => Uint8List.fromList([
    ..._u32(values.length * 4),
    for (final v in values) ..._u32(v),
  ]);

  static Uint8List _event(int object, int opcode, List<Uint8List> args) {
    final body = [for (final a in args) ...a];
    return Uint8List.fromList([
      ..._u32(object),
      ..._u32((8 + body.length) << 16 | opcode),
      ...body,
    ]);
  }
}

void main() {
  late Directory dir;
  final compositors = <_FakeCompositor>[];

  setUp(() => dir = Directory.systemTemp.createTempSync('wp_wlr_'));
  tearDown(() async {
    for (final c in compositors) {
      await c.stop();
    }
    compositors.clear();
    dir.deleteSync(recursive: true);
  });

  Future<(String, _FakeCompositor)> compositor(
    List<_Window> windows, {
    bool offerManager = true,
    bool error = false,
  }) async {
    final c = _FakeCompositor(
      windows,
      offerManager: offerManager,
      error: error,
    );
    compositors.add(c);
    return (await c.start(dir), c);
  }

  test('reports the activated window by app id, never the title', () async {
    final (path, fake) = await compositor([
      const _Window('firefox'),
      const _Window('foot', activated: true),
      const _Window('org.gnome.Nautilus'),
    ]);

    final target = await WlrToplevelFocusSource(path).focusedTarget();

    expect(target!.identifiers, ['foot']);
    expect(target.source, 'wlr-toplevel');
    expect(target.clientType, FocusedClientType.unknown);
    expect(fake.requests, [
      'get_registry',
      'sync',
      'bind 9 zwlr_foreign_toplevel_manager_v1 v3',
      'sync',
    ]);
  });

  test('no activated window means no target', () async {
    final (path, _) = await compositor([const _Window('firefox')]);
    expect(await WlrToplevelFocusSource(path).focusedTarget(), isNull);
  });

  test('a compositor without the manager: unavailable, no target', () async {
    final (path, fake) = await compositor([
      const _Window('foot', activated: true),
    ], offerManager: false);
    final source = WlrToplevelFocusSource(path);

    expect(await source.isAvailable(), isFalse);
    expect(await source.focusedTarget(), isNull);
    expect(fake.requests, isNot(contains(startsWith('bind'))));
  });

  test('the manager on offer makes the source available', () async {
    final (path, _) = await compositor([]);
    expect(await WlrToplevelFocusSource(path).isAvailable(), isTrue);
  });

  test(
    'a protocol error or a missing socket gives no target, quickly',
    () async {
      final (path, _) = await compositor([], error: true);
      final watch = Stopwatch()..start();
      expect(await WlrToplevelFocusSource(path).focusedTarget(), isNull);
      expect(
        await WlrToplevelFocusSource('${dir.path}/absent').focusedTarget(),
        isNull,
      );
      expect(watch.elapsed, lessThan(focusedTargetIpcTimeout * 2));
    },
  );

  test('messages split across reads are put back together', () {
    final message = WaylandMessage.encode(7, 1, [
      'zwlr_foreign_toplevel_manager_v1',
      3,
    ]);
    final buffer = BytesBuilder(copy: false)..add(message.sublist(0, 11));
    expect(WaylandMessage.drain(buffer), isEmpty);
    buffer.add(message.sublist(11));
    final [m] = WaylandMessage.drain(buffer);
    expect(m.sender, 7);
    expect(m.opcode, 1);
    expect(m.string(0).$1, 'zwlr_foreign_toplevel_manager_v1');
  });

  test('socketFor reads WAYLAND_DISPLAY like libwayland', () {
    expect(
      WlrToplevelFocusSource.socketFor({
        'WAYLAND_DISPLAY': 'wayland-1',
        'XDG_RUNTIME_DIR': '/run/user/1000',
      }),
      '/run/user/1000/wayland-1',
    );
    expect(
      WlrToplevelFocusSource.socketFor({'XDG_RUNTIME_DIR': '/run/user/1000'}),
      '/run/user/1000/wayland-0',
    );
    expect(
      WlrToplevelFocusSource.socketFor({'WAYLAND_DISPLAY': '/tmp/w'}),
      '/tmp/w',
    );
    expect(WlrToplevelFocusSource.socketFor({'WAYLAND_DISPLAY': 'w'}), isNull);
  });

  group('source choice', () {
    final wl = {
      'WAYLAND_DISPLAY': 'wayland-1',
      'XDG_RUNTIME_DIR': '/run/user/1',
    };

    test('other wlroots compositors use the toplevel protocol', () {
      expect(
        waylandFocusSourceFor(LinuxFocusDesktop.otherWayland, wl),
        isA<WlrToplevelFocusSource>(),
      );
    });

    test('inside Flatpak an unreachable IPC socket falls back to it', () {
      final env = {
        ...wl,
        'FLATPAK_ID': 'de.whispaste.app',
        'SWAYSOCK': '/absent',
      };
      expect(
        waylandFocusSourceFor(LinuxFocusDesktop.sway, env),
        isA<WlrToplevelFocusSource>(),
      );
      expect(
        waylandFocusSourceFor(LinuxFocusDesktop.niri, {
          ...env,
          'NIRI_SOCKET': '/absent',
        }),
        isA<WlrToplevelFocusSource>(),
      );
    });

    test('outside Flatpak, or with the socket visible, IPC stays', () async {
      expect(
        waylandFocusSourceFor(LinuxFocusDesktop.sway, {
          ...wl,
          'SWAYSOCK': '/absent',
        }),
        isA<SwayFocusSource>(),
      );
      final (path, _) = await compositor([]);
      expect(
        waylandFocusSourceFor(LinuxFocusDesktop.sway, {
          ...wl,
          'FLATPAK_ID': 'de.whispaste.app',
          'SWAYSOCK': path,
        }),
        isA<SwayFocusSource>(),
      );
    });
  });

  group('status probe', () {
    test('another wlroots compositor with the manager is available', () async {
      final (path, _) = await compositor([]);
      expect(
        await probeLinuxFocusStatus({'WAYLAND_DISPLAY': path}),
        LinuxFocusStatus.available,
      );
    });

    test('without the manager it is unsupported', () async {
      final (path, _) = await compositor([], offerManager: false);
      expect(
        await probeLinuxFocusStatus({'WAYLAND_DISPLAY': path}),
        LinuxFocusStatus.unsupported,
      );
    });
  });
}
