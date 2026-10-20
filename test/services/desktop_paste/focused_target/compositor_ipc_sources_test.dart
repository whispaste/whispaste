/// V1 Wayland: the Sway, Hyprland and niri focus sources against fake
/// compositor sockets that speak each wire format.
@TestOn('linux || mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/focused_target/compositor_ipc_sources.dart';
import 'package:whispaste/services/desktop_paste/focused_target/focused_target.dart';

void main() {
  late Directory dir;
  final servers = <ServerSocket>[];

  setUp(() => dir = Directory.systemTemp.createTempSync('wp_ipc_'));
  tearDown(() async {
    for (final s in servers) {
      await s.close();
    }
    servers.clear();
    dir.deleteSync(recursive: true);
  });

  /// A one-shot fake compositor: hands each request to [answer] and writes
  /// back what it returns (null: stay silent).
  Future<String> serve(
    String name,
    FutureOr<List<int>?> Function(List<int> request) answer, {
    bool closeAfter = true,
  }) async {
    final path = '${dir.path}/$name';
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    servers.add(server);
    server.listen((client) {
      final request = <int>[];
      client.listen((chunk) async {
        request.addAll(chunk);
        final reply = await answer(request);
        if (reply == null) return;
        client.add(reply);
        await client.flush();
        if (closeAfter) await client.close();
      });
    });
    return path;
  }

  List<int> i3Reply(Object json) {
    final payload = utf8.encode(jsonEncode(json));
    final header = ByteData(14);
    'i3-ipc'.codeUnits.asMap().forEach(header.setUint8);
    header
      ..setUint32(6, payload.length, Endian.host)
      ..setUint32(10, 4, Endian.host);
    return [...header.buffer.asUint8List(), ...payload];
  }

  Map<String, Object?> tree(Map<String, Object?> focused) => {
    'type': 'root',
    'focused': false,
    'nodes': [
      {
        'type': 'output',
        'focused': false,
        'nodes': [
          {
            'type': 'workspace',
            'focused': false,
            'nodes': [
              {'type': 'con', 'focused': false, 'app_id': 'firefox'},
            ],
            'floating_nodes': [
              {'type': 'floating_con', 'focused': true, ...focused},
            ],
          },
        ],
      },
    ],
  };

  group('Sway', () {
    test('sends GET_TREE and reads the focused Wayland window', () async {
      List<int>? seen;
      final path = await serve('sway.sock', (request) {
        if (request.length < 14) return null;
        seen = List.of(request);
        return i3Reply(tree({'app_id': 'foot'}));
      });

      final target = await SwayFocusSource(path).focusedTarget();

      expect(utf8.decode(seen!.sublist(0, 6)), 'i3-ipc');
      expect(
        ByteData.sublistView(
          Uint8List.fromList(seen!),
          10,
          14,
        ).getUint32(0, Endian.host),
        4,
      );
      expect(target!.id, 'foot');
      expect(target.clientType, FocusedClientType.wayland);
      expect(target.source, 'sway');
    });

    test('an XWayland window reports its WM_CLASS instance first', () {
      final target = SwayFocusSource.focusedNodeTarget(
        tree({
          'app_id': null,
          'shell': 'xwayland',
          'window_properties': {
            'class': 'Gnome-terminal',
            'instance': 'gnome-terminal-server',
          },
        }),
      );
      expect(target!.identifiers, ['gnome-terminal-server', 'Gnome-terminal']);
      expect(target.clientType, FocusedClientType.x11);
    });

    test('an empty workspace has no target', () {
      expect(
        SwayFocusSource.focusedNodeTarget({
          'type': 'workspace',
          'focused': true,
          'nodes': <Object>[],
        }),
        isNull,
      );
    });

    test('a reply split across chunks is read whole', () async {
      final path = await serve('split.sock', (request) async {
        if (request.length < 14) return null;
        return i3Reply(tree({'app_id': 'org.gnome.Ptyxis'}));
      });
      expect(
        (await SwayFocusSource(path).focusedTarget())!.id,
        'org.gnome.Ptyxis',
      );
    });
  });

  group('Hyprland', () {
    test('asks j/activewindow and reads class and xwayland', () async {
      String? seen;
      final path = await serve('.socket.sock', (request) {
        seen = utf8.decode(request);
        return utf8.encode(
          jsonEncode({
            'class': 'com.mitchellh.ghostty',
            'initialClass': 'com.mitchellh.ghostty',
            'title': 'never read',
            'xwayland': false,
          }),
        );
      });

      final target = await HyprlandFocusSource(path).focusedTarget();

      expect(seen, 'j/activewindow');
      expect(target!.identifiers, ['com.mitchellh.ghostty']);
      expect(target.clientType, FocusedClientType.wayland);
    });

    test('no focused window answers an empty object', () {
      expect(
        HyprlandFocusSource.activeWindowTarget(<String, Object?>{}),
        isNull,
      );
    });

    test('prefers the socket under XDG_RUNTIME_DIR', () async {
      Directory('${dir.path}/hypr/abc').createSync(recursive: true);
      final path = await serve('hypr/abc/.socket.sock', (_) => null);
      expect(
        HyprlandFocusSource.socketFor({
          'HYPRLAND_INSTANCE_SIGNATURE': 'abc',
          'XDG_RUNTIME_DIR': dir.path,
        }),
        path,
      );
      expect(
        HyprlandFocusSource.socketFor({
          'HYPRLAND_INSTANCE_SIGNATURE': 'old',
          'XDG_RUNTIME_DIR': dir.path,
        }),
        '/tmp/hypr/old/.socket.sock',
      );
      expect(HyprlandFocusSource.socketFor({}), isNull);
    });
  });

  group('niri', () {
    test('sends "FocusedWindow" and reads app_id from the Ok reply', () async {
      String? seen;
      final path = await serve('niri.sock', (request) {
        seen = utf8.decode(request);
        return utf8.encode(
          '${jsonEncode({
            'Ok': {
              'FocusedWindow': {'id': 3, 'app_id': 'Alacritty', 'title': 'x'},
            },
          })}\n',
        );
      }, closeAfter: false);

      final target = await NiriFocusSource(path).focusedTarget();

      expect(seen, '"FocusedWindow"\n');
      expect(target!.id, 'Alacritty');
    });

    test('no focus and errors give no target', () {
      expect(
        NiriFocusSource.focusedWindowTarget({
          'Ok': {'FocusedWindow': null},
        }),
        isNull,
      );
      expect(NiriFocusSource.focusedWindowTarget({'Err': 'nope'}), isNull);
    });
  });

  group('failures report no target, never throw', () {
    test('a missing socket', () async {
      expect(
        await SwayFocusSource('${dir.path}/absent').focusedTarget(),
        isNull,
      );
      expect(
        await NiriFocusSource('${dir.path}/absent').focusedTarget(),
        isNull,
      );
    });

    test('a compositor that never answers times out quickly', () async {
      final path = await serve('silent.sock', (_) => null);
      final watch = Stopwatch()..start();
      expect(await HyprlandFocusSource(path).focusedTarget(), isNull);
      expect(watch.elapsed, lessThan(focusedTargetIpcTimeout * 3));
    });

    test('garbage instead of JSON', () async {
      final path = await serve('junk.sock', (_) => utf8.encode('not json'));
      expect(await HyprlandFocusSource(path).focusedTarget(), isNull);
    });
  });
}
