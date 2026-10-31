/// Linux only (V1 Wayland): the global hotkey through the desktop's own
/// shortcut settings where the GlobalShortcuts portal is missing (GNOME
/// before 48, e.g. Ubuntu 24.04). There an app cannot grab keys for native
/// Wayland windows; a GNOME custom keybinding can, and runs a small launcher
/// that hands the toggle to the running WhisPaste.
///
/// The launcher writes the single-instance signal file itself (a few ms)
/// instead of booting a second WhisPaste process for `--toggle` (about
/// 370 ms warm in a debug build, measured in headless sway). With no
/// WhisPaste running it falls back to `--toggle`, which starts the app.
library;

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import 'desktop_paste/focused_target/linux_focused_target.dart';
import 'hotkey_key_resolver.dart';
import 'path_service.dart' as paths;
import 'single_instance_service.dart';

final _log = AppLogger('LinuxDesktopShortcut');

/// Runs a command line tool; injectable so tests never touch dconf.
typedef CommandRunner =
    Future<ProcessResult> Function(String executable, List<String> args);

Future<ProcessResult> _runProcess(String executable, List<String> args) =>
    Process.run(executable, args);

/// What the hotkey section offers on this session.
enum DesktopShortcutFallback {
  /// The hotkey works on its own (X11, the portal, or not Linux).
  notNeeded,

  /// GNOME on Wayland without the portal: WhisPaste can add the shortcut.
  gnome,

  /// Another Wayland desktop without the portal, or Flatpak (no host
  /// gsettings): the user binds the shown command themselves.
  manual,
}

/// Which fallback applies, from the session [env] and whether the
/// GlobalShortcuts portal answered.
DesktopShortcutFallback desktopShortcutFallbackFor(
  Map<String, String> env, {
  required bool portalAvailable,
}) {
  final desktop = detectLinuxFocusDesktop(env);
  if (desktop == LinuxFocusDesktop.x11 || portalAvailable) {
    return DesktopShortcutFallback.notNeeded;
  }
  final sandboxed = env['FLATPAK_ID']?.isNotEmpty ?? false;
  return desktop == LinuxFocusDesktop.gnome && !sandboxed
      ? DesktopShortcutFallback.gnome
      : DesktopShortcutFallback.manual;
}

/// Whether the session bus offers `org.freedesktop.portal.GlobalShortcuts`.
/// The portal frontend only exports interfaces its backend implements, so a
/// readable `version` means the desktop can bind shortcuts for apps.
Future<bool> globalShortcutsPortalAvailable(DBusClient bus) async {
  try {
    final portal = DBusRemoteObject(
      bus,
      name: 'org.freedesktop.portal.Desktop',
      path: DBusObjectPath('/org/freedesktop/portal/desktop'),
    );
    final version = await portal
        .getProperty('org.freedesktop.portal.GlobalShortcuts', 'version')
        .timeout(const Duration(seconds: 2));
    return version is DBusUint32 && version.value >= 1;
  } on Object catch (e) {
    _log.debug('GlobalShortcuts portal not reachable', e);
    return false;
  } finally {
    await bus.close();
  }
}

/// What a shortcut starts: the AppImage file itself (its mount point
/// changes with every start), else this executable.
String toggleExecutable(Map<String, String> env, String resolvedExecutable) {
  final appImage = env['APPIMAGE'];
  return (appImage != null && appImage.isNotEmpty)
      ? appImage
      : resolvedExecutable;
}

/// The command a user binds by hand ([DesktopShortcutFallback.manual]).
String manualToggleCommand(Map<String, String> env, String executable) {
  final app = env['FLATPAK_ID'];
  if (app != null && app.isNotEmpty) return 'flatpak run $app --toggle';
  return '${shellQuote(toggleExecutable(env, executable))} --toggle';
}

/// POSIX single quoting, also understood by `g_shell_parse_argv`, which
/// GNOME uses for custom keybinding commands.
String shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// GNOME accelerator syntax (`<Control><Shift>d`) for a stored hotkey, or
/// null for a key GNOME cannot name.
String? gnomeAccelerator(String modifiers, String key) {
  final name = _gnomeKeyName(key);
  if (name == null) return null;
  final mods = {for (final m in modifiers.toLowerCase().split('+')) m.trim()};
  return [
    if (mods.contains('ctrl') || mods.contains('control')) '<Control>',
    if (mods.contains('shift')) '<Shift>',
    if (mods.contains('alt')) '<Alt>',
    if (mods.contains('meta') || mods.contains('super')) '<Super>',
    name,
  ].join();
}

String? _gnomeKeyName(String key) {
  // F keys by their stored label: [resolveKey] maps them to ids that carry
  // no key label.
  final fn = RegExp(r'^F([1-9]|1[0-2])$').firstMatch(key.trim().toUpperCase());
  if (fn != null) return 'F${fn.group(1)}';
  final String label;
  try {
    label = resolveKey(key).keyLabel;
  } on ArgumentError {
    return null;
  }
  if (label.length == 1) {
    final c = label.codeUnitAt(0);
    if ((c >= 0x41 && c <= 0x5a) || (c >= 0x30 && c <= 0x39)) {
      return label.toLowerCase();
    }
  }
  return _gnomeNamedKeys[label];
}

/// `keyLabel` of the named and punctuation keys [resolveKey] knows, mapped
/// to their X keysym names.
const _gnomeNamedKeys = {
  ' ': 'space',
  'Space': 'space',
  'Enter': 'Return',
  'Tab': 'Tab',
  'Escape': 'Escape',
  'Backspace': 'BackSpace',
  'Delete': 'Delete',
  'Insert': 'Insert',
  'Home': 'Home',
  'End': 'End',
  'Page Up': 'Page_Up',
  'Page Down': 'Page_Down',
  'Arrow Left': 'Left',
  'Arrow Right': 'Right',
  'Arrow Up': 'Up',
  'Arrow Down': 'Down',
  ';': 'semicolon',
  "'": 'apostrophe',
  '`': 'grave',
  ',': 'comma',
  '-': 'minus',
  '.': 'period',
  '/': 'slash',
  '=': 'equal',
  '[': 'bracketleft',
  ']': 'bracketright',
  r'\': 'backslash',
};

/// The launcher the GNOME shortcut runs. [signalFile] and [executable] are
/// absolute. [processName] is the running WhisPaste's executable name, which
/// `pgrep -x` matches as the kernel keeps it (15 characters); for an
/// AppImage it differs from [executable].
String toggleLauncherScript({
  required String signalFile,
  required String executable,
  required String processName,
}) {
  final name = processName.length > 15
      ? processName.substring(0, 15)
      : processName;
  return '''
#!/bin/sh
# Written by WhisPaste for its GNOME keyboard shortcut; rewritten on change.
# A running WhisPaste picks the toggle up from the signal file in a few ms.
if pgrep -u "\$(id -u)" -x ${shellQuote(name)} >/dev/null 2>&1; then
  printf '%s toggle' "\$(date +%s.%N)" > ${shellQuote(signalFile)}
else
  exec ${shellQuote(executable)} --toggle
fi
''';
}

/// The WhisPaste entry in GNOME's custom keybindings (dconf through the
/// `gsettings` tool). Every write is idempotent.
class GnomeToggleShortcut {
  GnomeToggleShortcut({
    CommandRunner? run,
    String? launcherPath,
    String? signalFile,
    String? executable,
  }) : _run = run ?? _runProcess,
       _launcherPathOverride = launcherPath,
       _signalFileOverride = signalFile,
       _executableOverride = executable;

  static const listSchema = 'org.gnome.settings-daemon.plugins.media-keys';
  static const listKey = 'custom-keybindings';
  static const entrySchema =
      'org.gnome.settings-daemon.plugins.media-keys.custom-keybinding';
  static const entryPath =
      '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/whispaste-toggle/';

  final CommandRunner _run;
  final String? _launcherPathOverride;
  final String? _signalFileOverride;
  final String? _executableOverride;

  String get launcherPath =>
      _launcherPathOverride ??
      p.join(paths.appDataDir(), 'desktop-shortcut-toggle.sh');

  String get _entry => '$entrySchema:$entryPath';

  /// Whether WhisPaste's entry is in the custom keybinding list.
  Future<bool> isInstalled() async => (await _list()).contains(entryPath);

  /// Adds or updates the shortcut for [accelerator]. The list entry comes
  /// last, so GNOME never sees a half-written binding.
  Future<void> install(String accelerator) async {
    await _writeLauncher();
    await _set(_entry, 'name', _gvString('WhisPaste'));
    await _set(_entry, 'command', _gvString('sh ${shellQuote(launcherPath)}'));
    await _set(_entry, 'binding', _gvString(accelerator));
    final list = await _list();
    if (!list.contains(entryPath)) {
      await _set(listSchema, listKey, _gvList([...list, entryPath]));
    }
  }

  /// Takes the shortcut out of GNOME again and deletes the launcher.
  Future<void> remove() async {
    final list = await _list();
    if (list.contains(entryPath)) {
      await _set(
        listSchema,
        listKey,
        _gvList([...list.where((e) => e != entryPath)]),
      );
    }
    for (final key in const ['name', 'command', 'binding']) {
      await _gsettings(['reset', _entry, key]);
    }
    final launcher = File(launcherPath);
    if (launcher.existsSync()) await launcher.delete();
  }

  /// Keeps an installed shortcut on the current hotkey and executable (an
  /// AppImage may have moved). Does nothing when it is not installed.
  Future<void> sync(String accelerator) async {
    if (!await isInstalled()) return;
    await install(accelerator);
  }

  Future<void> _writeLauncher() async {
    final file = File(launcherPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      toggleLauncherScript(
        signalFile:
            _signalFileOverride ?? SingleInstanceService.signalFilePath(),
        executable:
            _executableOverride ??
            toggleExecutable(Platform.environment, Platform.resolvedExecutable),
        processName: p.basename(Platform.resolvedExecutable),
      ),
      flush: true,
    );
  }

  Future<List<String>> _list() async =>
      parseGvStringList(await _gsettings(['get', listSchema, listKey]));

  Future<void> _set(String schema, String key, String value) =>
      _gsettings(['set', schema, key, value]);

  Future<String> _gsettings(List<String> args) async {
    final result = await _run('gsettings', args);
    if (result.exitCode != 0) {
      throw ProcessException(
        'gsettings',
        args,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
    return '${result.stdout}'.trim();
  }
}

String _gvString(String value) =>
    "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

String _gvList(List<String> values) => '[${values.map(_gvString).join(', ')}]';

/// Reads a GVariant string array as `gsettings get` prints it
/// (`@as []`, `['/a/', '/b/']`).
List<String> parseGvStringList(String text) => [
  for (final m in RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(text))
    m.group(1)!.replaceAllMapped(RegExp(r'\\(.)'), (e) => e.group(1)!),
];

/// Whether GTK was forced onto native Wayland (`GDK_BACKEND=wayland`, which
/// some sway and Hyprland guides set). The runner only picks x11 when the
/// variable is unset; under native Wayland the X11 key grab reaches no
/// window at all, and GTK logs "already grabbed" (XP-6-13).
bool gdkBackendForcedWayland(Map<String, String> env) =>
    (env['GDK_BACKEND'] ?? '').split(',').first.trim().toLowerCase() ==
    'wayland';

/// The fallback for this session. Re-read with `ref.invalidate`.
final desktopShortcutFallbackProvider = FutureProvider<DesktopShortcutFallback>(
  (ref) async {
    if (!ref.watch(linuxDesktopShortcutHostProvider)) {
      return DesktopShortcutFallback.notNeeded;
    }
    final env = Platform.environment;
    if (detectLinuxFocusDesktop(env) == LinuxFocusDesktop.x11) {
      return DesktopShortcutFallback.notNeeded;
    }
    final fallback = desktopShortcutFallbackFor(
      env,
      portalAvailable: await globalShortcutsPortalAvailable(
        DBusClient.session(),
      ),
    );
    if (fallback != DesktopShortcutFallback.notNeeded) {
      // The hotkey service still reports its key grab as registered; say
      // here that it does not reach native Wayland windows.
      _log.warning(
        gdkBackendForcedWayland(env)
            ? 'GDK_BACKEND=wayland: the X11 key grab reaches no window; the '
                  'hotkey works only through the desktop shortcut ($fallback)'
            : 'No GlobalShortcuts portal: the X11 key grab reaches only '
                  'XWayland windows; system-wide needs the desktop shortcut '
                  '($fallback)',
      );
    }
    return fallback;
  },
);

/// Whether the main hotkey still waits for the desktop's own shortcut to
/// work system-wide (XP-6-14): a GNOME session until WhisPaste added its
/// entry; another desktop always, because a binding made by hand cannot be
/// seen from here.
final desktopShortcutPendingProvider = Provider<bool>((ref) {
  final fallback =
      ref.watch(desktopShortcutFallbackProvider).value ??
      DesktopShortcutFallback.notNeeded;
  return switch (fallback) {
    DesktopShortcutFallback.notNeeded => false,
    DesktopShortcutFallback.gnome =>
      !(ref.watch(gnomeToggleShortcutInstalledProvider).value ?? false),
    DesktopShortcutFallback.manual => true,
  };
});

final gnomeToggleShortcutProvider = Provider<GnomeToggleShortcut>(
  (ref) => GnomeToggleShortcut(),
);

/// Whether WhisPaste's GNOME shortcut is set up. Re-read with
/// `ref.invalidate` after adding or removing it.
/// Whether this host can carry a desktop shortcut at all. Off under
/// `flutter test` (`FLUTTER_TEST`), so widget tests on a Linux host never ask
/// the real D-Bus or dconf; tests that want the block override it.
final linuxDesktopShortcutHostProvider = Provider<bool>(
  (ref) =>
      Platform.isLinux && !Platform.environment.containsKey('FLUTTER_TEST'),
);

final gnomeToggleShortcutInstalledProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(linuxDesktopShortcutHostProvider)) return false;
  try {
    return await ref.read(gnomeToggleShortcutProvider).isInstalled();
  } on Object catch (e) {
    _log.debug('GNOME shortcut state unknown', e);
    return false;
  }
});

/// The binding an installed shortcut carries: the main hotkey, or none
/// (GNOME's "disabled") while the hotkey is switched off.
String desktopShortcutAccelerator(AppSettings settings) =>
    settings.hotkeyEnabled
    ? gnomeAccelerator(
            settings.hotkey.hotkeyModifiers,
            settings.hotkey.hotkeyKey,
          ) ??
          ''
    : '';

/// Keeps an installed GNOME shortcut on the current hotkey, and rewrites its
/// launcher once per start (the executable may have moved). Watched for the
/// app lifetime by the service bootstrap.
final desktopShortcutSyncProvider = Provider<void>((ref) {
  if (!ref.watch(linuxDesktopShortcutHostProvider)) return;
  ref.listen<AsyncValue<AppSettings>>(settingsProvider, (prev, next) {
    final settings = next.value;
    if (settings == null) return;
    final accelerator = desktopShortcutAccelerator(settings);
    final before = prev?.value;
    if (before != null && desktopShortcutAccelerator(before) == accelerator) {
      return;
    }
    unawaited(
      ref.read(gnomeToggleShortcutProvider).sync(accelerator).catchError((
        Object e,
      ) {
        // No gsettings or no GNOME schema: nothing of ours to keep in step.
        _log.debug('GNOME shortcut not synced', e);
      }),
    );
  }, fireImmediately: true);
});

/// Factory reset: WhisPaste's GNOME shortcut goes with the rest of its data.
/// Throws only when the shortcut is there and could not be removed. Runs
/// before the settings reset, so [desktopShortcutSyncProvider] finds nothing
/// to re-add.
Future<void> removeDesktopShortcutForReset(
  GnomeToggleShortcut shortcut, {
  bool? isLinux,
}) async {
  if (!(isLinux ?? Platform.isLinux)) return;
  final bool installed;
  try {
    installed = await shortcut.isInstalled();
  } on Object catch (e) {
    _log.debug('no GNOME shortcut to remove', e);
    return;
  }
  if (installed) await shortcut.remove();
}

/// The command [DesktopShortcutFallback.manual] shows, and the one the
/// Wayland hotkey notice copies. A provider so tests do not depend on the
/// test runner's own executable.
final manualToggleCommandProvider = Provider<String>(
  (ref) =>
      manualToggleCommand(Platform.environment, Platform.resolvedExecutable),
);

/// Executable and arguments that open [desktop]'s keyboard shortcut settings,
/// or null for a desktop WhisPaste cannot open them on.
(String, List<String>)? keyboardShortcutSettingsCommand(
  LinuxFocusDesktop desktop,
) => switch (desktop) {
  LinuxFocusDesktop.gnome => ('gnome-control-center', ['keyboard']),
  LinuxFocusDesktop.kde => ('systemsettings', ['kcm_keys']),
  _ => null,
};

/// Opens the keyboard shortcut settings of [desktop]. Returns false when they
/// cannot be opened.
Future<bool> openKeyboardShortcutSettings(LinuxFocusDesktop desktop) async {
  final command = keyboardShortcutSettingsCommand(desktop);
  if (command == null) return false;
  final (executable, args) = command;
  try {
    await Process.start(executable, args, mode: ProcessStartMode.detached);
    return true;
  } on ProcessException catch (e) {
    _log.warning('Could not open keyboard settings ($executable): $e');
    return false;
  }
}

/// Injected so tests never start a settings app.
final keyboardShortcutSettingsOpenerProvider =
    Provider<Future<bool> Function(LinuxFocusDesktop)>(
      (ref) => openKeyboardShortcutSettings,
    );

/// The desktop whose keyboard shortcut settings WhisPaste can open (GNOME,
/// KDE), or null. Not inside Flatpak: the settings app would start inside the
/// sandbox, where it is not installed.
final keyboardShortcutSettingsDesktopProvider = Provider<LinuxFocusDesktop?>((
  ref,
) {
  if (!ref.watch(linuxDesktopShortcutHostProvider)) return null;
  final env = Platform.environment;
  if ((env['FLATPAK_ID'] ?? '').isNotEmpty) return null;
  final desktop = detectLinuxFocusDesktop(env);
  return keyboardShortcutSettingsCommand(desktop) == null ? null : desktop;
});
