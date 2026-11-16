/// Linux autostart entry (`$XDG_CONFIG_HOME/autostart/<app id>.desktop`).
///
/// The file name must be the application ID (`de.whispaste.app`, local builds
/// `de.whispaste.app.dev`, set in linux/CMakeLists.txt): GNOME derives the
/// app ID of an autostarted process from it, and the GlobalShortcuts portal
/// binds the hotkey to that ID. Under the plugin's `WhisPaste.desktop` the
/// process ran as `app-gnome-WhisPaste-*`, so the hotkey did nothing after
/// login until the app was restarted (#85, GitHub #159).
///
/// An entry the plugin wrote earlier is moved to the new name on the first
/// check, so an existing autostart keeps working.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'autostart_backend.dart';
import 'desktop_paste/linux_package_format.dart';
import 'linux_desktop_shortcut.dart' show toggleExecutable;
import 'linux_portal_autostart.dart';
import 'path_service.dart' show isLocalBuild;

/// Application ID of this build, as linux/CMakeLists.txt sets it.
String linuxApplicationId({bool localBuild = isLocalBuild}) =>
    localBuild ? 'de.whispaste.app.dev' : 'de.whispaste.app';

/// File name the `launch_at_startup` plugin used before #85.
String legacyAutostartFileName({bool localBuild = isLocalBuild}) =>
    localBuild ? 'WhisPaste Dev.desktop' : 'WhisPaste.desktop';

/// Stable launcher of the snap. The binary path under `/snap/<name>/<rev>/`
/// is invalid after every refresh (#97).
const snapLauncher = '/snap/bin/whispaste';

/// The autostart folder: `$XDG_CONFIG_HOME/autostart`, else
/// `~/.config/autostart`.
String autostartDir(Map<String, String> env) {
  final config = env['XDG_CONFIG_HOME'];
  if (config != null && config.isNotEmpty && p.isAbsolute(config)) {
    return p.join(config, 'autostart');
  }
  return p.join(env['HOME'] ?? '', '.config', 'autostart');
}

/// One argument of the Exec key (Desktop Entry Spec, "The Exec key"), the
/// same rule as `DesktopExecArg` in linux/runner/desktop_entry.h: always in
/// double quotes, `"`, backtick, `$` and `\` escaped inside them, `%` doubled
/// so it is never a field code, and the string-value escape (`\` to `\\`)
/// on top. Single quotes are not quoting in the spec; KDE takes them
/// literally. Throws for a relative path or a control character.
String desktopExecArg(String path) {
  if (path.isEmpty || !path.startsWith('/')) {
    throw ArgumentError.value(path, 'executable', 'not an absolute path');
  }
  final out = StringBuffer('"');
  for (final rune in path.runes) {
    if (rune < 0x20 || rune == 0x7f) {
      throw ArgumentError.value(path, 'executable', 'control character');
    }
    switch (String.fromCharCode(rune)) {
      case '"' || '`' || r'$':
        out
          ..write(r'\\')
          ..writeCharCode(rune);
      case r'\':
        out.write(r'\\\\');
      case '%':
        out.write('%%');
      default:
        out.writeCharCode(rune);
    }
  }
  return (out..write('"')).toString();
}

/// Content of the entry. [executable] is what the session starts: the
/// AppImage file itself (its mount point changes with every start), else the
/// installed binary.
String linuxAutostartEntry({
  required String executable,
  bool localBuild = isLocalBuild,
}) {
  final name = localBuild ? 'WhisPaste Dev' : 'WhisPaste';
  return '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=$name\n'
      'Exec=${desktopExecArg(executable)} --autostart\n'
      'Icon=${linuxApplicationId(localBuild: localBuild)}\n'
      'StartupNotify=false\n'
      'Terminal=false\n'
      'X-GNOME-Autostart-enabled=true\n';
}

/// [AutostartBackend] for Linux; the session's environment and executable
/// are injectable so tests write into a temporary folder.
class LinuxAutostartBackend implements AutostartBackend {
  LinuxAutostartBackend({
    Map<String, String>? env,
    String? resolvedExecutable,
    this.localBuild = isLocalBuild,
    this.format = LinuxPackageFormat.native,
  }) : _env = env ?? Platform.environment,
       _resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable;

  final Map<String, String> _env;
  final String _resolvedExecutable;
  final bool localBuild;

  /// Snap writes [snapLauncher] into the entry; snapd starts it (the app's
  /// `autostart:` key in snapcraft.yaml), `HOME` is `$SNAP_USER_DATA`.
  final LinuxPackageFormat format;

  File get _entry => File(
    p.join(
      autostartDir(_env),
      '${linuxApplicationId(localBuild: localBuild)}.desktop',
    ),
  );

  File get _legacy => File(
    p.join(autostartDir(_env), legacyAutostartFileName(localBuild: localBuild)),
  );

  String get _content => linuxAutostartEntry(
    executable: format == LinuxPackageFormat.snap
        ? snapLauncher
        : toggleExecutable(_env, _resolvedExecutable),
    localBuild: localBuild,
  );

  /// Also moves a legacy entry to the new name, so an autostart the user
  /// switched on before #85 stays on, and rewrites an entry whose content is
  /// out of date (an AppImage that moved).
  @override
  Future<bool> isEnabled() async {
    final entry = _entry;
    if (await _legacy.exists() ||
        (await entry.exists() && await entry.readAsString() != _content)) {
      await enable();
      return true;
    }
    return entry.exists();
  }

  /// Writes the entry and removes a legacy one.
  @override
  Future<void> enable() async {
    final entry = _entry;
    // Built first: a path the Exec key cannot carry must not leave a folder.
    final content = _content;
    await entry.parent.create(recursive: true);
    await entry.writeAsString(content);
    if (await _legacy.exists()) await _legacy.delete();
  }

  @override
  Future<void> disable() async {
    for (final file in [_entry, _legacy]) {
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<bool> requiresApproval() async => false;

  @override
  Future<void> openLoginItems() async {}
}

/// Picks the backend for the package [format]: the portal in Flatpak, the
/// entry file everywhere else (Snap with the stable launcher).
AutostartBackend linuxAutostartBackendFor({
  required LinuxPackageFormat format,
  Map<String, String>? env,
  BackgroundPortalCall? portalCall,
}) => format == LinuxPackageFormat.flatpak
    ? FlatpakPortalAutostartBackend(
        env: env ?? Platform.environment,
        call: portalCall,
      )
    : LinuxAutostartBackend(env: env, format: format);
