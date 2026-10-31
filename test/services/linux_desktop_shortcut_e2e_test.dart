/// V1 Wayland end to end: the GNOME shortcut against the real `gsettings`
/// and dconf, and its launcher against a real running instance.
///
/// Run by test/scripts/gnome_shortcut_e2e.sh inside its own D-Bus session
/// with a throwaway XDG_CONFIG_HOME, so the user's dconf is never touched.
/// Skipped otherwise.
@TestOn('linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/linux_desktop_shortcut.dart';
import 'package:whispaste/services/single_instance_service.dart';

void main() {
  final env = Platform.environment;
  final skip = env['WP_GNOME_SHORTCUT_E2E'] == '1'
      ? false
      : 'needs test/scripts/gnome_shortcut_e2e.sh';
  const entry =
      '${GnomeToggleShortcut.entrySchema}:${GnomeToggleShortcut.entryPath}';

  Future<String> gsettings(List<String> args) async {
    final result = await Process.run('gsettings', args);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return '${result.stdout}'.trim();
  }

  test('install, sync and remove land in dconf as GNOME reads them', () async {
    final dir = Directory.systemTemp.createTempSync('wp_gnome_shortcut_e2e_');
    addTearDown(() async {
      await SingleInstanceService.release();
      SingleInstanceService.onRemoteCommand = null;
      SingleInstanceService.lockDirOverride = null;
      dir.deleteSync(recursive: true);
    });
    SingleInstanceService.lockDirOverride = dir.path;
    await gsettings([
      'set',
      GnomeToggleShortcut.listSchema,
      GnomeToggleShortcut.listKey,
      "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']",
    ]);
    final shortcut = GnomeToggleShortcut(
      launcherPath: p.join(dir.path, 'toggle.sh'),
      executable: Platform.resolvedExecutable,
    );

    await shortcut.install(gnomeAccelerator('ctrl+shift', 'D')!);

    expect(
      parseGvStringList(
        await gsettings([
          'get',
          GnomeToggleShortcut.listSchema,
          GnomeToggleShortcut.listKey,
        ]),
      ),
      [
        '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/',
        GnomeToggleShortcut.entryPath,
      ],
    );
    expect(await gsettings(['get', entry, 'binding']), "'<Control><Shift>d'");
    expect(await gsettings(['get', entry, 'name']), "'WhisPaste'");
    final command = await gsettings(['get', entry, 'command']);

    // What GNOME runs on the key press: the stored command, split the way
    // g_shell_parse_argv does for a plain `sh '<path>'`.
    expect(await SingleInstanceService.ensureSingleInstance(), isTrue);
    final delivered = Completer<InstanceCommand>();
    SingleInstanceService.onRemoteCommand = delivered.complete;
    // GVariant prints a string holding ' in double quotes.
    expect(command, '"sh \'${p.join(dir.path, 'toggle.sh')}\'"');
    final watch = Stopwatch()..start();
    final run = await Process.run('sh', [p.join(dir.path, 'toggle.sh')]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    expect(
      await delivered.future.timeout(const Duration(seconds: 5)),
      InstanceCommand.toggle,
    );
    // ignore: avoid_print
    print(
      '[E2E] launcher → toggle delivered in ${watch.elapsedMilliseconds} ms',
    );

    await shortcut.sync(gnomeAccelerator('alt', 'F9')!);
    expect(await gsettings(['get', entry, 'binding']), "'<Alt>F9'");

    await shortcut.remove();
    expect(await shortcut.isInstalled(), isFalse);
    expect(await gsettings(['get', entry, 'binding']), "''");
    expect(File(p.join(dir.path, 'toggle.sh')).existsSync(), isFalse);
  }, skip: skip);
}
