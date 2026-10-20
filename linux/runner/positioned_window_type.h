#ifndef RUNNER_POSITIONED_WINDOW_TYPE_H_
#define RUNNER_POSITIONED_WINDOW_TYPE_H_

#include <gtk/gtk.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "window_manager_kind.h"

// GtkWindowType for helper windows that must sit at an exact screen
// position: a WM-managed TOPLEVEL normally, so keep-above and the
// NOTIFICATION hint reach the WM; override-redirect POPUP on a tiling WM,
// which would otherwise tile it (XP-6-10, see window_manager_kind.h).
inline GtkWindowType PositionedHelperWindowType() {
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gdk_screen_get_default();
  if (screen != nullptr && GDK_IS_X11_SCREEN(screen) &&
      IsTilingWindowManager(gdk_x11_screen_get_window_manager_name(screen))) {
    return GTK_WINDOW_POPUP;
  }
#endif
  return GTK_WINDOW_TOPLEVEL;
}

#endif  // RUNNER_POSITIONED_WINDOW_TYPE_H_
