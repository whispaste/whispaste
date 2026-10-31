#ifndef RUNNER_WINDOW_MANAGER_KIND_H_
#define RUNNER_WINDOW_MANAGER_KIND_H_

// Tiling window managers tile every managed toplevel, including the
// undecorated NOTIFICATION windows WhisPaste uses for the edge sensor, the
// side panel, the recording overlay and the floating button; fixed-size or
// UTILITY windows float but get centred (XP-6-10, measured on sway). Those
// helper windows must sit at an exact screen position, so on a tiling WM
// they bypass the WM as override-redirect windows instead.
//
// Pure and free of GTK/X11 so window_manager_kind_test.cc runs on any host.
// [wm_name] is what the WM publishes via _NET_SUPPORTING_WM_CHECK, as
// returned by gdk_x11_screen_get_window_manager_name().

#include <cctype>
#include <string>

inline bool IsTilingWindowManager(const char* wm_name) {
  if (wm_name == nullptr) return false;
  std::string name(wm_name);
  for (char& c : name) {
    c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  }
  // "wlroots wm" is the XWayland WM of sway, river and other wlroots
  // compositors.
  static const char* const kTiling[] = {
      "wlroots wm", "i3",    "hyprland", "bspwm",        "awesome",
      "xmonad",     "qtile", "dwm",      "herbstluftwm", "spectrwm",
      "leftwm",
  };
  for (const char* tiling : kTiling) {
    if (name == tiling) return true;
  }
  return false;
}

#endif  // RUNNER_WINDOW_MANAGER_KIND_H_
