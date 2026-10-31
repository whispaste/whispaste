/// V1 Wayland: the hotkey fallback through a GNOME custom keybinding, for
/// desktops without the GlobalShortcuts portal.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/linux_desktop_shortcut.dart';
import 'package:whispaste/services/single_instance_service.dart';

/// `gsettings` against an in-memory dconf: `get`/`set`/`reset`, keyed by
/// `schema[:path] key`. Values are kept as the GVariant text they were set to.
class _FakeGsettings {
  _FakeGsettings({String list = '@as []'}) {
    values['${GnomeToggleShortcut.listSchema} '
            '${GnomeToggleShortcut.listKey}'] =
        list;
  }

  final values = <String, String>{};
  final calls = <List<String>>[];
  bool fail = false;

  Future<ProcessResult> call(String executable, List<String> args) async {
    expect(executable, 'gsettings');
    calls.add(args);
    if (fail) return ProcessResult(0, 1, '', 'No such schema');
    final key = '${args[1]} ${args[2]}';
    switch (args[0]) {
      case 'get':
        return ProcessResult(0, 0, '${values[key] ?? "''"}\n', '');
      case 'set':
        values[key] = args[3];
      case 'reset':
        values.remove(key);
    }
    return ProcessResult(0, 0, '', '');
  }

  String get list =>
      values['${GnomeToggleShortcut.listSchema} '
          '${GnomeToggleShortcut.listKey}']!;

  String? entry(String key) =>
      values['${GnomeToggleShortcut.entrySchema}:${GnomeToggleShortcut.entryPath} '
          '$key'];
}

void main() {
  group('gnomeAccelerator', () {
    test('spells the stored hotkey the way GNOME reads it', () {
      expect(gnomeAccelerator('ctrl+shift', 'D'), '<Control><Shift>d');
      expect(gnomeAccelerator('alt+meta', 'F9'), '<Alt><Super>F9');
      expect(gnomeAccelerator('ctrl', '7'), '<Control>7');
      expect(gnomeAccelerator('ctrl+alt', 'SPACE'), '<Control><Alt>space');
      expect(gnomeAccelerator('ctrl', 'PAGEDOWN'), '<Control>Page_Down');
      expect(gnomeAccelerator('ctrl', '→'), '<Control>Right');
      expect(gnomeAccelerator('ctrl+shift', ';'), '<Control><Shift>semicolon');
      expect(gnomeAccelerator('', 'F12'), 'F12');
    });

    test('an unknown key gives no accelerator', () {
      expect(gnomeAccelerator('ctrl', 'NOPE'), isNull);
    });
  });

  group('desktopShortcutFallbackFor', () {
    const gnome = {
      'XDG_SESSION_TYPE': 'wayland',
      'WAYLAND_DISPLAY': 'wayland-0',
      'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME',
    };

    test('GNOME on Wayland without the portal: WhisPaste adds it', () {
      expect(
        desktopShortcutFallbackFor(gnome, portalAvailable: false),
        DesktopShortcutFallback.gnome,
      );
    });

    test('the portal or an X11 session need no fallback', () {
      expect(
        desktopShortcutFallbackFor(gnome, portalAvailable: true),
        DesktopShortcutFallback.notNeeded,
      );
      expect(
        desktopShortcutFallbackFor({
          'XDG_SESSION_TYPE': 'x11',
          'XDG_CURRENT_DESKTOP': 'GNOME',
        }, portalAvailable: false),
        DesktopShortcutFallback.notNeeded,
      );
    });

    test('other desktops and Flatpak get the command to bind', () {
      expect(
        desktopShortcutFallbackFor({
          ...gnome,
          'FLATPAK_ID': 'de.whispaste.app',
        }, portalAvailable: false),
        DesktopShortcutFallback.manual,
      );
      expect(
        desktopShortcutFallbackFor({
          ...gnome,
          'SWAYSOCK': '/run/user/1/sway.sock',
        }, portalAvailable: false),
        DesktopShortcutFallback.manual,
      );
    });
  });

  test('the manual command fits the package', () {
    expect(
      manualToggleCommand({'FLATPAK_ID': 'de.whispaste.app'}, '/app/bin/x'),
      'flatpak run de.whispaste.app --toggle',
    );
    expect(
      manualToggleCommand({}, "/opt/Whis Paste/it's"),
      r"'/opt/Whis Paste/it'\''s' --toggle",
    );
  });

  test('an AppImage shortcut starts the AppImage, not its mount', () {
    const env = {'APPIMAGE': '/home/u/Apps/WhisPaste.AppImage'};
    expect(
      toggleExecutable(env, '/tmp/.mount_WhisPa1/whispaste'),
      '/home/u/Apps/WhisPaste.AppImage',
    );
    expect(
      manualToggleCommand(env, '/tmp/.mount_WhisPa1/whispaste'),
      "'/home/u/Apps/WhisPaste.AppImage' --toggle",
    );
    expect(toggleExecutable({}, '/usr/bin/whispaste'), '/usr/bin/whispaste');
  });

  test('the launcher matches the process name, not the AppImage file', () {
    final script = toggleLauncherScript(
      signalFile: '/s/focus.signal',
      executable: '/home/u/WhisPaste.AppImage',
      processName: 'whispaste-with-a-long-name',
    );
    expect(script, contains("-x 'whispaste-with-' "));
    expect(script, contains("exec '/home/u/WhisPaste.AppImage' --toggle"));
  });

  test('parseGvStringList reads what gsettings prints', () {
    expect(parseGvStringList('@as []'), isEmpty);
    expect(parseGvStringList(r"['/a/', '/b\'c/']"), ['/a/', "/b'c/"]);
  });

  group('GnomeToggleShortcut', () {
    late Directory dir;
    late _FakeGsettings gsettings;
    late GnomeToggleShortcut shortcut;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('wp_gnome_shortcut_');
      gsettings = _FakeGsettings(list: "['/custom0/']");
      shortcut = GnomeToggleShortcut(
        run: gsettings.call,
        launcherPath: p.join(dir.path, 'toggle.sh'),
        signalFile: '/s/focus.signal',
        executable: '/opt/whispaste/whispaste',
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('install writes the entry, then adds it next to the others', () async {
      expect(await shortcut.isInstalled(), isFalse);

      await shortcut.install('<Control><Shift>d');

      expect(gsettings.entry('name'), "'WhisPaste'");
      expect(gsettings.entry('binding'), "'<Control><Shift>d'");
      // gsettings stores the command as a string literal, so every backslash
      // of the Windows path is escaped as '\\'.
      final quoted = p.join(dir.path, 'toggle.sh').replaceAll(r'\', r'\\');
      expect(gsettings.entry('command'), "'sh \\'$quoted\\''");
      expect(parseGvStringList(gsettings.list), [
        '/custom0/',
        GnomeToggleShortcut.entryPath,
      ]);
      expect(gsettings.calls.last, [
        'set',
        GnomeToggleShortcut.listSchema,
        GnomeToggleShortcut.listKey,
        "['/custom0/', '${GnomeToggleShortcut.entryPath}']",
      ]);
      expect(await shortcut.isInstalled(), isTrue);
      expect(
        File(p.join(dir.path, 'toggle.sh')).readAsStringSync(),
        contains("exec '/opt/whispaste/whispaste' --toggle"),
      );
    });

    test('a second install only updates the binding', () async {
      await shortcut.install('<Control><Shift>d');
      await shortcut.install('<Alt>F9');

      expect(gsettings.entry('binding'), "'<Alt>F9'");
      expect(parseGvStringList(gsettings.list), [
        '/custom0/',
        GnomeToggleShortcut.entryPath,
      ]);
    });

    test(
      'remove leaves the other shortcuts and deletes the launcher',
      () async {
        await shortcut.install('<Control><Shift>d');

        await shortcut.remove();

        expect(parseGvStringList(gsettings.list), ['/custom0/']);
        expect(gsettings.entry('binding'), isNull);
        expect(File(p.join(dir.path, 'toggle.sh')).existsSync(), isFalse);
        expect(await shortcut.isInstalled(), isFalse);
      },
    );

    test('sync follows a new hotkey only when installed', () async {
      await shortcut.sync('<Alt>F9');
      expect(gsettings.entry('binding'), isNull);

      await shortcut.install('<Control><Shift>d');
      await shortcut.sync('<Alt>F9');
      expect(gsettings.entry('binding'), "'<Alt>F9'");
    });

    test('the factory reset takes an installed shortcut out', () async {
      await shortcut.install('<Control><Shift>d');

      await removeDesktopShortcutForReset(shortcut, isLinux: true);

      expect(await shortcut.isInstalled(), isFalse);
      expect(parseGvStringList(gsettings.list), ['/custom0/']);
    });

    test('the factory reset leaves dconf alone without our entry', () async {
      await removeDesktopShortcutForReset(shortcut, isLinux: true);
      expect(gsettings.calls.where((c) => c.first != 'get'), isEmpty);

      await removeDesktopShortcutForReset(shortcut, isLinux: false);
      gsettings.fail = true;
      // No gsettings, or no GNOME schema: nothing to remove, no failure.
      await removeDesktopShortcutForReset(shortcut, isLinux: true);
    });

    test('a failing gsettings is an error, not a silent success', () async {
      gsettings.fail = true;
      await expectLater(
        shortcut.install('<Control><Shift>d'),
        throwsA(isA<ProcessException>()),
      );
    });
  });

  group('launcher', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('wp_toggle_launcher_');
      SingleInstanceService.lockDirOverride = dir.path;
    });
    tearDown(() async {
      await SingleInstanceService.release();
      SingleInstanceService.onRemoteCommand = null;
      SingleInstanceService.lockDirOverride = null;
      dir.deleteSync(recursive: true);
    });

    Future<String> launcher(String executable) async {
      final file = File(p.join(dir.path, 'launcher.sh'));
      await file.writeAsString(
        toggleLauncherScript(
          signalFile: SingleInstanceService.signalFilePath(),
          executable: executable,
          processName: p.basename(executable),
        ),
      );
      return file.path;
    }

    test(
      'a running WhisPaste gets the toggle through the signal file',
      () async {
        expect(await SingleInstanceService.ensureSingleInstance(), isTrue);
        final delivered = Completer<InstanceCommand>();
        SingleInstanceService.onRemoteCommand = delivered.complete;

        // This test process is the running "WhisPaste": its own executable
        // name is what the launcher looks for.
        final script = await launcher(Platform.resolvedExecutable);
        final watch = Stopwatch()..start();
        final result = await Process.run('sh', [script]);
        final ranFor = watch.elapsed;

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          await delivered.future.timeout(const Duration(seconds: 5)),
          InstanceCommand.toggle,
        );
        // Hands over without booting a second process.
        expect(ranFor, lessThan(const Duration(milliseconds: 300)));
      },
    );

    test(
      'without a running WhisPaste it starts the app with --toggle',
      () async {
        final marker = p.join(dir.path, 'started');
        final fake = File(
          p.join(dir.path, 'wp-not-running-x'),
        )..writeAsStringSync('#!/bin/sh\necho "\$@" > ${shellQuote(marker)}\n');
        await Process.run('chmod', ['+x', fake.path]);

        final result = await Process.run('sh', [await launcher(fake.path)]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(File(marker).readAsStringSync().trim(), '--toggle');
        expect(
          File(SingleInstanceService.signalFilePath()).existsSync(),
          isFalse,
        );
      },
    );
  }, skip: Platform.isLinux ? false : 'the launcher is a Linux shell script');
}
