/// Linux terminals that paste with Ctrl+Shift+V and copy with Ctrl+Shift+C
/// (V1). In a terminal, plain Ctrl+V inserts a literal ^V and Ctrl+C sends
/// SIGINT to the running program.
///
/// [linuxTerminalWmInstances] holds X11 WM_CLASS instance names, the value
/// the native host reports for X11 and XWayland windows (linux/runner/
/// desktop_paste_host.cc). [linuxTerminalAppIds] holds the Wayland app ids
/// the compositor focus sources report (focused_target/, V1 Wayland).
///
/// Not listed on purpose:
/// - xterm and urxvt: by default they paste only the primary selection
///   (Shift+Insert, middle click), so no clipboard shortcut reaches them.
/// - VS Code's terminal: it lives inside the editor window (`code`), which
///   needs Ctrl+V for the editor.
library;

import 'focused_target/focused_target.dart';

const linuxTerminalWmInstances = {
  'alacritty',
  'gnome-terminal-server',
  'guake',
  'kgx', // GNOME Console
  'kitty',
  'konsole',
  'lxterminal',
  'mate-terminal',
  'org.wezfurlong.wezterm',
  'ptyxis',
  'qterminal',
  'st-256color',
  'terminator',
  'terminology',
  'tilix',
  'xfce4-terminal',
  'yakuake',
};

/// Wayland app ids (xdg_toplevel app_id) of terminals, lower case. Several
/// terminals use their X11 instance name as app id too (`kitty`,
/// `alacritty`); those already sit in [linuxTerminalWmInstances].
const linuxTerminalAppIds = {
  'app.devsuite.ptyxis',
  'com.gexperts.tilix',
  'com.mitchellh.ghostty',
  'com.raggesilver.blackbox',
  'contour',
  'foot',
  'footclient',
  'io.elementary.terminal',
  'org.gnome.console',
  'org.gnome.ptyxis',
  'org.gnome.terminal',
  'org.kde.konsole',
  'org.kde.yakuake',
  'org.xfce.terminal',
  'rio',
  'wezterm',
};

/// Whether any name of the focused window [target] is a terminal.
bool isLinuxTerminalFocus(FocusedTarget target) => target.identifiers.any(
  (id) =>
      isLinuxTerminalTarget(id) ||
      linuxTerminalAppIds.contains(id.toLowerCase()),
);

/// Whether [wmInstance] (the captured target's WM_CLASS instance name) is a
/// terminal. `null` and empty mean the target is unknown.
bool isLinuxTerminalTarget(String? wmInstance) =>
    wmInstance != null &&
    linuxTerminalWmInstances.contains(wmInstance.toLowerCase());
