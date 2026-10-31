#ifndef RUNNER_X11_WINDOW_H_
#define RUNNER_X11_WINDOW_H_

#include <gdk/gdkx.h>

#include <string>
#include <utility>

// Runs Xlib calls that name a window WhisPaste does not own. Such a window can
// disappear at any moment (the user closes the paste target while the
// dictation is transcribed), and GDK's default X error handler terminates the
// whole process on the resulting BadWindow (XP-7-18). Returns false when the
// calls raised an X error; their results are then meaningless.
template <typename Calls>
bool WithX11ErrorTrap(GdkDisplay* display, Calls&& calls) {
  gdk_x11_display_error_trap_push(display);
  std::forward<Calls>(calls)();
  return gdk_x11_display_error_trap_pop(display) == 0;
}

// WM_CLASS res_name of [window], or "" when the window is gone, has no class
// hint or an empty name.
std::string X11WindowResName(GdkDisplay* display, Window window);

// The window the window manager reports as focused (EWMH _NET_ACTIVE_WINDOW),
// or 0 when there is none, the window manager does not publish it, or a
// Wayland app has focus (XWayland only knows X windows).
Window X11ActiveWindow(GdkDisplay* display);

// Whether [window] still exists. Minimised windows count: activating them
// brings them back.
bool X11WindowExists(GdkDisplay* display, Window window);

// Asks the window manager to focus [window] (EWMH _NET_ACTIVE_WINDOW client
// message). Source "pager", so focus-stealing prevention does not drop the
// request of a background app; the result shows in X11ActiveWindow later.
void X11RequestActivation(GdkDisplay* display, Window window);

#endif  // RUNNER_X11_WINDOW_H_
