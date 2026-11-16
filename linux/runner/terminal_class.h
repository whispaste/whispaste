#ifndef RUNNER_TERMINAL_CLASS_H_
#define RUNNER_TERMINAL_CLASS_H_

#include <algorithm>
#include <cctype>
#include <string>

// Whether the X11 WM_CLASS instance name [res_name] belongs to a terminal or
// to an app that embeds one (code editors, IDEs). Ctrl+Z there suspends the
// running process (SIGTSTP) instead of undoing, so the keystroke undo must not
// go to such a window. This list alone is fail-open for unknown classes; the
// host therefore asks IsUndoSafeWindowClass below, which is fail-closed.
// Editors with an embedded terminal are listed as a whole because the focused
// pane cannot be told from the window class.
inline bool IsTerminalWindowClass(const std::string& res_name) {
  std::string name = res_name;
  std::transform(name.begin(), name.end(), name.begin(),
                 [](unsigned char c) { return std::tolower(c); });
  if (name.empty()) return false;
  static const char* const kExact[] = {
      // Terminal emulators.
      "gnome-terminal", "gnome-terminal-server", "konsole", "xterm", "uxterm",
      "urxvt", "rxvt", "alacritty", "kitty", "wezterm", "wezterm-gui", "foot",
      "footclient", "tilix", "terminator", "xfce4-terminal", "mate-terminal",
      "lxterminal", "qterminal", "st", "st-256color", "sakura", "guake",
      "yakuake", "ptyxis", "kgx", "ghostty", "terminology", "tabby", "hyper",
      "cool-retro-term", "warp", "rio", "contour", "blackbox", "gnome-console",
      // Reverse-DNS classes of newer terminals (as published by their
      // desktop files).
      "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "org.gnome.console",
      "org.gnome.ptyxis", "org.gnome.terminal", "org.kde.konsole",
      "org.kde.yakuake", "org.codeberg.dnkl.foot", "io.alacritty",
      "org.contourterminal.contour", "com.raggesilver.blackbox",
      // Editors and IDEs with an integrated terminal.
      "code", "code-oss", "vscodium", "cursor", "windsurf", "zed", "emacs",
      "idea", "pycharm", "clion", "webstorm", "goland", "rustrover", "rider",
      "phpstorm", "datagrip", "android-studio", "sublime_text", "kate",
      "kdevelop", "gnome-builder",
  };
  for (const char* known : kExact) {
    if (name == known) return true;
  }
  return name.rfind("jetbrains-", 0) == 0;
}

// Whether the keystroke undo (Ctrl+Z) may go to a window of this WM_CLASS
// instance name: only classes known to be plain text targets and not listed as
// terminal. Everything else (unknown classes included) takes the clipboard
// path, because Ctrl+Z in a terminal suspends the running process. Extend the
// list with real WM_CLASS values seen on a lab VM, never with guesses.
inline bool IsUndoSafeWindowClass(const std::string& res_name) {
  if (IsTerminalWindowClass(res_name)) return false;
  std::string name = res_name;
  std::transform(name.begin(), name.end(), name.begin(),
                 [](unsigned char c) { return std::tolower(c); });
  static const char* const kSafe[] = {
      // Browsers (Firefox reports "Navigator" as instance name).
      "navigator", "firefox", "firefox-esr", "chromium", "chromium-browser",
      "google-chrome", "brave-browser", "microsoft-edge", "vivaldi-stable",
      "epiphany", "org.gnome.epiphany",
      // Plain editors and office.
      "gedit", "org.gnome.gedit", "gnome-text-editor", "org.gnome.texteditor",
      "mousepad", "pluma", "xed", "kwrite", "libreoffice", "soffice",
      "libreoffice-writer", "libreoffice-calc", "libreoffice-impress",
      "onlyoffice", "obsidian", "logseq", "typora", "marktext",
      // Mail and chat.
      "thunderbird", "evolution", "geary", "slack", "discord",
      "telegram-desktop", "signal", "element", "teams-for-linux",
  };
  for (const char* known : kSafe) {
    if (name == known) return true;
  }
  return false;
}

// How the host's wait for the paste target to come to the front goes on
// (#428 activateTarget). A pure decision so it is testable without X11 or
// real time: [elapsed_ms] is passed in.
enum class ActivateStep { kWait, kDone, kFailed };
inline ActivateStep DecideActivateStep(unsigned long active_window,
                                       unsigned long target_window,
                                       long elapsed_ms, long timeout_ms) {
  if (target_window == 0) return ActivateStep::kFailed;
  if (active_window == target_window) return ActivateStep::kDone;
  if (elapsed_ms >= timeout_ms) return ActivateStep::kFailed;
  return ActivateStep::kWait;
}

// Last check right before the keystroke undo (#731), same decisions as
// Windows' DecideUndoSend. Pure so it is testable without X11 or real time.
// [since_paste_s] is the time since the paste; input counts as the user's
// when it is more recent than the paste and not the host's own synthetic key
// (within [kSyntheticKeyToleranceS]). Only clicks outside WhisPaste count.
constexpr double kSyntheticKeyToleranceS = 0.05;
enum class UndoSendCheck {
  kSend,
  kWatcherInactive,
  kForegroundChanged,
  kUnsafeTarget,
  kUserInput,
};
inline UndoSendCheck DecideUndoSend(bool watcher_running,
                                    unsigned long active_window,
                                    unsigned long target_window,
                                    const std::string& window_class,
                                    double since_paste_s, double key_idle_s,
                                    double synthetic_idle_s,
                                    double foreign_click_idle_s) {
  if (!watcher_running) return UndoSendCheck::kWatcherInactive;
  if (active_window == 0 || target_window == 0 ||
      active_window != target_window) {
    return UndoSendCheck::kForegroundChanged;
  }
  if (!IsUndoSafeWindowClass(window_class)) return UndoSendCheck::kUnsafeTarget;
  const bool typed = key_idle_s < since_paste_s &&
                     key_idle_s < synthetic_idle_s - kSyntheticKeyToleranceS;
  const bool clicked = foreign_click_idle_s < since_paste_s;
  return typed || clicked ? UndoSendCheck::kUserInput : UndoSendCheck::kSend;
}

// Status string sendUndoShortcut answers; Dart takes the clipboard path for
// everything but "sent".
inline const char* UndoSendStatus(UndoSendCheck check) {
  switch (check) {
    case UndoSendCheck::kSend:
      return "sent";
    case UndoSendCheck::kWatcherInactive:
      return "watcher_inactive";
    case UndoSendCheck::kForegroundChanged:
      return "foreground_changed";
    case UndoSendCheck::kUnsafeTarget:
      return "unsafe_target";
    case UndoSendCheck::kUserInput:
      return "user_input";
  }
  return "unknown";
}

#endif  // RUNNER_TERMINAL_CLASS_H_
