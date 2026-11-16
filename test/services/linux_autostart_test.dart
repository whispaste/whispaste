// Linux autostart entry (#85): the file is named after the application ID,
// so GNOME gives the autostarted process the ID the GlobalShortcuts portal
// bound the hotkey to; an entry written under the old name is moved.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/linux_autostart.dart';

void main() {
  late Directory home;
  late Directory autostart;

  setUp(() {
    home = Directory.systemTemp.createTempSync('wp-autostart');
    autostart = Directory(p.join(home.path, '.config', 'autostart'));
  });
  tearDown(() => home.deleteSync(recursive: true));

  LinuxAutostartBackend backend({
    Map<String, String> extra = const {},
    bool localBuild = false,
  }) => LinuxAutostartBackend(
    env: {'HOME': home.path, ...extra},
    resolvedExecutable: '/usr/lib/whispaste/whispaste',
    localBuild: localBuild,
  );

  File entry(String name) => File(p.join(autostart.path, name));

  test('enable writes the entry under the application ID', () async {
    await backend().enable();
    expect(entry('de.whispaste.app.desktop').existsSync(), isTrue);
    expect(
      entry('de.whispaste.app.desktop').readAsStringSync(),
      contains('Exec="/usr/lib/whispaste/whispaste" --autostart\n'),
    );
    expect(await backend().isEnabled(), isTrue);
  });

  test('a local build uses its own ID and leaves the release alone', () async {
    await backend().enable();
    await backend(localBuild: true).enable();
    await backend(localBuild: true).disable();
    expect(entry('de.whispaste.app.dev.desktop').existsSync(), isFalse);
    expect(entry('de.whispaste.app.desktop').existsSync(), isTrue);
  });

  test('a legacy entry is moved and stays enabled', () async {
    autostart.createSync(recursive: true);
    entry('WhisPaste.desktop').writeAsStringSync('[Desktop Entry]\n');
    expect(await backend().isEnabled(), isTrue);
    expect(entry('WhisPaste.desktop').existsSync(), isFalse);
    expect(entry('de.whispaste.app.desktop').existsSync(), isTrue);
  });

  test('disable removes the entry and a legacy one', () async {
    await backend().enable();
    entry('WhisPaste.desktop').writeAsStringSync('[Desktop Entry]\n');
    await backend().disable();
    expect(autostart.listSync(), isEmpty);
    expect(await backend().isEnabled(), isFalse);
  });

  test('an AppImage starts the image file, and a move is refreshed', () async {
    final appImage = backend(extra: {'APPIMAGE': '/opt/a/WhisPaste.AppImage'});
    await appImage.enable();
    final moved = backend(extra: {'APPIMAGE': '/opt/b/WhisPaste.AppImage'});
    expect(await moved.isEnabled(), isTrue);
    expect(
      entry('de.whispaste.app.desktop').readAsStringSync(),
      contains('Exec="/opt/b/WhisPaste.AppImage" --autostart\n'),
    );
  });

  test('the Exec key quotes the path the Desktop Entry Spec way', () async {
    // Double quotes with `"`, `\`, `$` and backtick escaped, `%` doubled.
    // Single quotes are literal to KDE and other non-GLib launchers.
    await backend(
      extra: {'APPIMAGE': r'/home/a b/My "App"/100%\$.AppImage'},
    ).enable();
    expect(
      entry('de.whispaste.app.desktop').readAsStringSync(),
      contains(
        r'Exec="/home/a b/My \\"App\\"/100%%\\\\\\$.AppImage" --autostart'
        '\n',
      ),
    );
  });

  test('a path the Exec key cannot carry is refused, not written', () async {
    await expectLater(
      backend(extra: {'APPIMAGE': 'relative/WhisPaste.AppImage'}).enable(),
      throwsA(isA<ArgumentError>()),
    );
    expect(autostart.existsSync() && autostart.listSync().isNotEmpty, isFalse);
  });

  test('XDG_CONFIG_HOME decides the folder', () async {
    final config = p.join(home.path, 'cfg');
    await backend(extra: {'XDG_CONFIG_HOME': config}).enable();
    expect(
      File(
        p.join(config, 'autostart', 'de.whispaste.app.desktop'),
      ).existsSync(),
      isTrue,
    );
  });
}
