/// V1 Wayland: the status the settings show for target detection.
@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/focused_target/dbus_focus_sources.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart';

import 'private_bus.dart';

void main() {
  late Directory dir;
  late DBusServer server;
  late DBusAddress address;
  final owners = <DBusClient>[];

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('wp_focus_status_');
    server = DBusServer();
    address = await server.listenAddress(
      DBusAddress.unix(path: '${dir.path}/bus'),
    );
  });

  tearDown(() async {
    for (final c in owners) {
      await c.close();
    }
    owners.clear();
    await server.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> own(String name) async {
    final client = privateBusClient(address);
    owners.add(client);
    await client.requestName(name);
  }

  Future<LinuxFocusStatus> probe(Map<String, String> env) =>
      probeLinuxFocusStatus(env, sessionBus: () => privateBusClient(address));

  const wayland = {'WAYLAND_DISPLAY': 'wayland-0'};

  test('X11 is always available', () async {
    expect(
      await probe({'XDG_SESSION_TYPE': 'x11'}),
      LinuxFocusStatus.available,
    );
  });

  test('an unknown Wayland compositor is unsupported', () async {
    expect(
      await probe({...wayland, 'XDG_CURRENT_DESKTOP': 'COSMIC'}),
      LinuxFocusStatus.unsupported,
    );
  });

  test('Sway counts only when its socket is reachable', () async {
    final path = '${dir.path}/sway.sock';
    final socket = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    addTearDown(socket.close);
    expect(
      await probe({...wayland, 'SWAYSOCK': path}),
      LinuxFocusStatus.available,
    );
    // A Flatpak sees the variable but not the socket behind it.
    expect(
      await probe({...wayland, 'SWAYSOCK': '${dir.path}/hidden.sock'}),
      LinuxFocusStatus.unsupported,
    );
  });

  test('GNOME needs the WhisPaste extension on the bus', () async {
    const gnome = {...wayland, 'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME'};
    expect(await probe(gnome), LinuxFocusStatus.gnomeExtensionMissing);
    await own(GnomeShellFocusSource.busName);
    expect(await probe(gnome), LinuxFocusStatus.available);
  });

  test('KDE counts when KWin is on the bus', () async {
    const kde = {...wayland, 'XDG_CURRENT_DESKTOP': 'KDE'};
    expect(await probe(kde), LinuxFocusStatus.unsupported);
    await own('org.kde.KWin');
    expect(await probe(kde), LinuxFocusStatus.available);
  });
}
