#include "keybinder_raw.h"

#include <keybinder.h>
#include <gdk/gdkx.h>
#include <X11/Xlib.h>
#include <X11/XKBlib.h>
#include <array>

namespace {
std::array<bool, 256> held{};
bool repeat = false;
Bool detectable_repeat = False;

GdkFilterReturn ObserveKey(GdkXEvent* raw, GdkEvent*, gpointer) {
  const auto* event = static_cast<XEvent*>(raw);
  if (event->type != KeyPress && event->type != KeyRelease) {
    return GDK_FILTER_CONTINUE;
  }
  const auto code = event->xkey.keycode;
  if (code >= held.size()) return GDK_FILTER_CONTINUE;
  if (event->type == KeyPress) {
    repeat = held[code];
    held[code] = true;
  } else {
    // Without XKB detectable repeat, X11 emits a release/press pair with
    // identical timestamps. It is not a physical release.
    if (!detectable_repeat && XPending(event->xkey.display)) {
      XEvent next;
      XPeekEvent(event->xkey.display, &next);
      if (next.type == KeyPress && next.xkey.keycode == code &&
          next.xkey.time == event->xkey.time) {
        return GDK_FILTER_CONTINUE;
      }
    }
    held[code] = false;
  }
  return GDK_FILTER_CONTINUE;
}
}  // namespace

bool keybinder_is_repeat() { return repeat; }

void keybinder_init_raw() {
  // Install before keybinder's filter: its callback reads this event's state.
  static bool observing = false;
  if (!observing) {
    auto* display = gdk_display_get_default();
    if (GDK_IS_X11_DISPLAY(display)) {
      // Detectable repeat emits only repeated downs. Its releases are always
      // real, even when two very fast presses share a millisecond timestamp.
      XkbSetDetectableAutoRepeat(GDK_DISPLAY_XDISPLAY(display), True,
                                &detectable_repeat);
    }
    gdk_window_add_filter(nullptr, ObserveKey, nullptr);
    observing = true;
  }
  keybinder_init();
  keybinder_set_use_cooked_accelerators(FALSE);
}
