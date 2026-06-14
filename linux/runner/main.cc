#include "my_application.h"

int main(int argc, char** argv) {
  // Force the X11/XWayland GDK backend before GTK initialises.
  //
  // Why: the floating overlay needs two capabilities that native Wayland
  // (via libwayland-client) does NOT provide under GNOME/Mutter:
  //   1. gtk_window_set_keep_above — Mutter ignores this on Wayland; the
  //      compositor controls all stacking and forbids app-driven always-on-top.
  //   2. gtk_window_move — absolute positioning is not available in the
  //      Wayland shell protocol; only the compositor decides where windows go.
  //
  // Under XWayland (Mutter's built-in X11 compatibility layer), both features
  // are available via the EWMH _NET_WM_STATE_ABOVE hint and XMoveWindow,
  // respectively. The main application window also uses XWayland, so there is
  // no visual regression — font rendering and HiDPI scaling behave identically.
  //
  // We only set the variable if the caller has not already overridden it, so
  // that test harnesses or CI environments that explicitly need Wayland can
  // still pass GDK_BACKEND=wayland on the command line or in the environment.
  //
  // COMPILE RISK: on a pure X11 system (no Wayland compositor at all) this
  // env var is a no-op — GDK already picks the X11 backend.
  if (g_getenv("GDK_BACKEND") == nullptr) {
    g_setenv("GDK_BACKEND", "x11", TRUE);
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
