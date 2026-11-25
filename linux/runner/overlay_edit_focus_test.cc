// Unit test for overlay_edit_focus.h (#254). Pure C++17, no GTK/X11.
// Build: g++ -std=c++17 -o /tmp/overlay_edit_focus_test \
//   linux/runner/overlay_edit_focus_test.cc && /tmp/overlay_edit_focus_test
#include "overlay_edit_focus.h"

#include <cstdio>

static int failures = 0;

static void Expect(unsigned long actual, unsigned long expected,
                   const char* name) {
  if (actual != expected) {
    std::fprintf(stderr, "FAIL: %s -> %lu, expected %lu\n", name, actual,
                 expected);
    ++failures;
  }
}

int main() {
  // Only plain X11 with a managed overlay and the EWMH active-window hint.
  Expect(OverlayEditFocusSupported(true, false, true, true), 1, "x11");
  Expect(OverlayEditFocusSupported(true, true, true, true), 0,
         "wayland session (XWayland)");
  Expect(OverlayEditFocusSupported(false, false, true, true), 0,
         "native wayland display");
  Expect(OverlayEditFocusSupported(true, false, false, true), 0,
         "tiling WM, override-redirect overlay");
  Expect(OverlayEditFocusSupported(true, false, true, false), 0,
         "no _NET_ACTIVE_WINDOW");

  Expect(OverlayWantsEditFocus(true, true, true), 1, "open field");
  Expect(OverlayWantsEditFocus(true, true, false), 0, "field closed");
  Expect(OverlayWantsEditFocus(true, false, true), 0, "overlay hidden");
  Expect(OverlayWantsEditFocus(false, true, true), 0, "unsupported");

  // The overlay still has the focus: back to the window from before.
  Expect(OverlayFocusRestoreWindow(7, 7, 3), 3, "esc in the field");
  // The insert already activated the target app.
  Expect(OverlayFocusRestoreWindow(3, 7, 3), 0, "after insert");
  // The user clicked another window meanwhile.
  Expect(OverlayFocusRestoreWindow(9, 7, 3), 0, "user moved on");
  Expect(OverlayFocusRestoreWindow(7, 7, 0), 0, "nothing was active");
  Expect(OverlayFocusRestoreWindow(7, 7, 7), 0, "overlay was active");
  Expect(OverlayFocusRestoreWindow(0, 0, 3), 0, "no overlay window");

  if (failures == 0) std::printf("overlay_edit_focus_test: all passed\n");
  return failures == 0 ? 0 : 1;
}
