// Unit test for window_manager_kind.h (XP-6-10). Pure C++17, no GTK/X11.
#include "window_manager_kind.h"

#include <cstdio>

static int failures = 0;

static void Expect(bool actual, bool expected, const char* name) {
  if (actual != expected) {
    std::fprintf(stderr, "FAIL: %s -> %d, expected %d\n", name, actual,
                 expected);
    ++failures;
  }
}

int main() {
  // Tiling WMs as they name themselves via _NET_SUPPORTING_WM_CHECK.
  Expect(IsTilingWindowManager("wlroots wm"), true, "wlroots wm (sway)");
  Expect(IsTilingWindowManager("i3"), true, "i3");
  Expect(IsTilingWindowManager("Hyprland"), true, "Hyprland");
  Expect(IsTilingWindowManager("bspwm"), true, "bspwm");
  Expect(IsTilingWindowManager("awesome"), true, "awesome");
  Expect(IsTilingWindowManager("xmonad"), true, "xmonad");
  Expect(IsTilingWindowManager("herbstluftwm"), true, "herbstluftwm");
  Expect(IsTilingWindowManager("qtile"), true, "qtile");
  Expect(IsTilingWindowManager("dwm"), true, "dwm");

  // Stacking WMs keep the WM-managed toplevel.
  Expect(IsTilingWindowManager("GNOME Shell"), false, "GNOME Shell");
  Expect(IsTilingWindowManager("Mutter"), false, "Mutter");
  Expect(IsTilingWindowManager("KWin"), false, "KWin");
  Expect(IsTilingWindowManager("Xfwm4"), false, "Xfwm4");
  Expect(IsTilingWindowManager("Openbox"), false, "Openbox");
  Expect(IsTilingWindowManager("Mutter (Muffin)"), false, "Muffin");

  // Unknown or missing names keep today's behaviour.
  Expect(IsTilingWindowManager("unknown"), false, "unknown");
  Expect(IsTilingWindowManager(""), false, "empty");
  Expect(IsTilingWindowManager(nullptr), false, "null");
  // No substring matches: "i3" must not hit a longer, unrelated name.
  Expect(IsTilingWindowManager("Fluxi3box"), false, "substring");

  if (failures == 0) std::printf("window_manager_kind_test: all passed\n");
  return failures == 0 ? 0 : 1;
}
