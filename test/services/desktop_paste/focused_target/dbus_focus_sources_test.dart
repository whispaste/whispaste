/// V1 Wayland: the GNOME-extension and KWin focus sources against a private
/// D-Bus server with fake compositor objects (no session bus involved).
@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/focused_target/dbus_focus_sources.dart';
import 'package:whispaste/services/desktop_paste/focused_target/focused_target.dart';

import 'private_bus.dart';

class _FakeShellFocus extends DBusObject {
  _FakeShellFocus(this.reply)
    : super(DBusObjectPath(GnomeShellFocusSource.objectPath));

  Map<String, DBusValue> reply;
  var calls = 0;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != GnomeShellFocusSource.interfaceName ||
        call.name != 'GetFocusedWindow') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    calls++;
    return DBusMethodSuccessResponse([DBusDict.stringVariant(reply)]);
  }
}

/// Plays KWin's scripting API: loadScript remembers the file, run executes
/// the one thing our script does (callDBus back with the window's names).
class _FakeKWin {
  _FakeKWin(this.client, this.names, {this.plasma5 = false});

  final DBusClient client;
  List<String> names;
  final bool plasma5;
  final loaded = <String, String>{};
  final log = <String>[];

  Future<void> register() async {
    await client.registerObject(_KWinScripting(this));
    await client.registerObject(
      _KWinScript(this, DBusObjectPath(plasma5 ? '/7' : '/Scripting/Script7')),
    );
  }
}

class _KWinScripting extends DBusObject {
  _KWinScripting(this.kwin) : super(DBusObjectPath('/Scripting'));
  final _FakeKWin kwin;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    switch (call.name) {
      case 'loadScript':
        final path = call.values[0].asString();
        final plugin = call.values[1].asString();
        kwin.log.add('load $plugin');
        if (kwin.loaded.containsKey(plugin)) {
          return DBusMethodSuccessResponse([const DBusInt32(-1)]);
        }
        kwin.loaded[plugin] = File(path).readAsStringSync();
        return DBusMethodSuccessResponse([const DBusInt32(7)]);
      case 'unloadScript':
        final plugin = call.values[0].asString();
        kwin.log.add('unload $plugin');
        return DBusMethodSuccessResponse([
          DBusBoolean(kwin.loaded.remove(plugin) != null),
        ]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

class _KWinScript extends DBusObject {
  _KWinScript(this.kwin, DBusObjectPath path) : super(path);
  final _FakeKWin kwin;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.name != 'run') return DBusMethodErrorResponse.unknownMethod();
    final script = kwin.loaded.values.single;
    kwin.log.add('run');
    final callback = RegExp(
      r'callDBus\("([^"]+)", "([^"]+)", "([^"]+)", '
      r'"([^"]+)"',
    ).firstMatch(script)!;
    await kwin.client.callMethod(
      destination: callback[1],
      path: DBusObjectPath(callback[2]!),
      interface: callback[3],
      name: callback[4]!,
      // KWin always sends the three names; missing ones are empty.
      values: [
        for (var i = 0; i < 3; i++)
          DBusString(i < kwin.names.length ? kwin.names[i] : ''),
      ],
    );
    return DBusMethodSuccessResponse();
  }
}

void main() {
  late Directory dir;
  late DBusServer server;
  late DBusAddress address;
  final clients = <DBusClient>[];

  Future<DBusClient> connect({String? name}) async {
    final client = privateBusClient(address);
    clients.add(client);
    if (name != null) await client.requestName(name);
    return client;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('wp_dbus_');
    server = DBusServer();
    address = await server.listenAddress(
      DBusAddress.unix(path: '${dir.path}/bus'),
    );
  });

  tearDown(() async {
    for (final c in clients) {
      await c.close();
    }
    clients.clear();
    await server.close();
    dir.deleteSync(recursive: true);
  });

  group('GNOME Shell extension', () {
    test('reads a Wayland window by app id', () async {
      final shell = await connect(name: GnomeShellFocusSource.busName);
      await shell.registerObject(
        _FakeShellFocus({
          'app_id': const DBusString('org.gnome.Ptyxis'),
          'wm_class': const DBusString('org.gnome.Ptyxis'),
          'wm_class_instance': const DBusString(''),
          'client_type': const DBusString('wayland'),
        }),
      );
      final source = GnomeShellFocusSource(await connect());

      expect(await source.isAvailable(), isTrue);
      final target = await source.focusedTarget();
      expect(target!.identifiers, ['org.gnome.Ptyxis']);
      expect(target.clientType, FocusedClientType.wayland);
      expect(target.source, 'gnome-extension');
    });

    test('an X11 window puts the WM_CLASS instance first', () {
      final target = GnomeShellFocusSource.targetFromReply({
        'app_id': const DBusString('org.gnome.Terminal'),
        'wm_class': const DBusString('Gnome-terminal'),
        'wm_class_instance': const DBusString('gnome-terminal-server'),
        'client_type': const DBusString('x11'),
      });
      expect(target!.identifiers, [
        'gnome-terminal-server',
        'Gnome-terminal',
        'org.gnome.Terminal',
      ]);
      expect(target.clientType, FocusedClientType.x11);
    });

    test('no focus gives no target', () async {
      final shell = await connect(name: GnomeShellFocusSource.busName);
      await shell.registerObject(_FakeShellFocus({}));
      expect(
        await GnomeShellFocusSource(await connect()).focusedTarget(),
        isNull,
      );
    });

    test('without the extension: unavailable and no target', () async {
      final source = GnomeShellFocusSource(await connect());
      expect(await source.isAvailable(), isFalse);
      expect(await source.focusedTarget(), isNull);
    });
  });

  group('KWin', () {
    for (final plasma5 in [false, true]) {
      test(
        'loads, runs and unloads the script (Plasma ${plasma5 ? 5 : 6})',
        () async {
          final kwinClient = await connect(name: 'org.kde.KWin');
          final kwin = _FakeKWin(kwinClient, [
            'konsole',
            'org.kde.konsole',
            'org.kde.konsole',
          ], plasma5: plasma5);
          await kwin.register();
          final source = KWinFocusSource(await connect(), scriptDirectory: dir);

          final target = await source.focusedTarget();

          expect(target!.identifiers, ['org.kde.konsole', 'konsole']);
          expect(target.clientType, FocusedClientType.wayland);
          expect(target.source, 'kwin');
          expect(kwin.loaded, isEmpty, reason: 'script must be unloaded');
          expect(kwin.log, containsAllInOrder(['load whispaste-focus', 'run']));
          expect(kwin.log.last, 'unload whispaste-focus');
        },
      );
    }

    test('tells Wayland and X11 windows apart by their names', () {
      final wayland = kwinTarget(
        'python3.14',
        'de.whispaste.FocusProbe',
        'de.whispaste.FocusProbe',
      )!;
      expect(wayland.identifiers, ['de.whispaste.FocusProbe', 'python3.14']);
      expect(wayland.clientType, FocusedClientType.wayland);

      final x11 = kwinTarget('konsole', 'konsole', 'org.kde.konsole')!;
      expect(x11.identifiers, ['konsole', 'org.kde.konsole']);
      expect(x11.clientType, FocusedClientType.x11);

      expect(kwinTarget('', '', ''), isNull);
    });

    test('the script reads names only, never the window title', () {
      final script = kwinFocusScript(':1.42');
      expect(script, contains('resourceName'));
      expect(script, contains('workspace.activeWindow'));
      expect(script, contains('workspace.activeClient'));
      expect(script, isNot(contains('caption')));
      expect(script, isNot(contains('title')));
    });

    test('back-to-back lookups each get their own answer', () async {
      final kwin = _FakeKWin(await connect(name: 'org.kde.KWin'), ['kate']);
      await kwin.register();
      final source = KWinFocusSource(await connect(), scriptDirectory: dir);

      final first = source.focusedTarget();
      kwin.names = ['dolphin'];
      final second = source.focusedTarget();

      expect((await first)?.id, isNotNull);
      expect((await second)!.id, 'dolphin');
    });

    test('without KWin there is no target, quickly', () async {
      final source = KWinFocusSource(await connect(), scriptDirectory: dir);
      final watch = Stopwatch()..start();
      expect(await source.focusedTarget(), isNull);
      expect(watch.elapsed, lessThan(focusedTargetDbusTimeout * 3));
    });
  });
}
