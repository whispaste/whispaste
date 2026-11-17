#include "x11_window.h"

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include "side_panel_edge_core.h"

std::string X11WindowResName(GdkDisplay* display, Window window) {
  Display* xdisplay = gdk_x11_display_get_xdisplay(display);
  XClassHint hint = {};
  Status status = 0;
  const bool clean = WithX11ErrorTrap(
      display, [&] { status = XGetClassHint(xdisplay, window, &hint); });

  std::string name;
  if (clean && status != 0 && hint.res_name != nullptr) name = hint.res_name;
  if (hint.res_name != nullptr) XFree(hint.res_name);
  if (hint.res_class != nullptr) XFree(hint.res_class);
  return name;
}

Window X11ActiveWindow(GdkDisplay* display) {
  Display* xdisplay = gdk_x11_display_get_xdisplay(display);
  Atom active = XInternAtom(xdisplay, "_NET_ACTIVE_WINDOW", True);
  if (active == None) return 0;

  Atom type = None;
  int format = 0;
  unsigned long count = 0;
  unsigned long after = 0;
  unsigned char* data = nullptr;
  int status = BadImplementation;
  const bool clean = WithX11ErrorTrap(display, [&] {
    status = XGetWindowProperty(xdisplay, DefaultRootWindow(xdisplay), active,
                                0, 1, False, XA_WINDOW, &type, &format, &count,
                                &after, &data);
  });
  Window window = 0;
  // Format 32 items are longs on the wire; Xlib hands them over as longs.
  if (clean && status == Success && data != nullptr && format == 32 &&
      count == 1) {
    window = reinterpret_cast<unsigned long*>(data)[0];
  }
  if (data != nullptr) XFree(data);
  return window;
}

bool X11WindowExists(GdkDisplay* display, Window window) {
  if (window == 0) return false;
  Display* xdisplay = gdk_x11_display_get_xdisplay(display);
  XWindowAttributes attributes = {};
  Status status = 0;
  const bool clean = WithX11ErrorTrap(display, [&] {
    status = XGetWindowAttributes(xdisplay, window, &attributes);
  });
  return clean && status != 0;
}

void X11RequestActivation(GdkDisplay* display, Window window) {
  Display* xdisplay = gdk_x11_display_get_xdisplay(display);
  XEvent event = {};
  event.xclient.type = ClientMessage;
  event.xclient.window = window;
  event.xclient.message_type =
      XInternAtom(xdisplay, "_NET_ACTIVE_WINDOW", False);
  event.xclient.format = 32;
  event.xclient.data.l[0] = 2;  // Source indication: pager.
  event.xclient.data.l[1] = CurrentTime;
  WithX11ErrorTrap(display, [&] {
    XSendEvent(xdisplay, DefaultRootWindow(xdisplay), False,
               SubstructureRedirectMask | SubstructureNotifyMask, &event);
    XFlush(xdisplay);
  });
}

unsigned long X11WindowPid(GdkDisplay* display, Window window) {
  if (window == 0) return 0;
  Display* xdisplay = gdk_x11_display_get_xdisplay(display);
  Atom pid_atom = XInternAtom(xdisplay, "_NET_WM_PID", True);
  if (pid_atom == None) return 0;

  Atom type = None;
  int format = 0;
  unsigned long count = 0;
  unsigned long after = 0;
  unsigned char* data = nullptr;
  int status = BadImplementation;
  const bool clean = WithX11ErrorTrap(display, [&] {
    status = XGetWindowProperty(xdisplay, window, pid_atom, 0, 1, False,
                                XA_CARDINAL, &type, &format, &count, &after,
                                &data);
  });
  unsigned long pid = 0;
  if (clean && status == Success && data != nullptr && format == 32 &&
      count == 1) {
    pid = reinterpret_cast<unsigned long*>(data)[0];
  }
  if (data != nullptr) XFree(data);
  return pid;
}

bool X11HasActiveWindowHint(GdkDisplay* display) {
  Display* xdisplay = gdk_x11_display_get_xdisplay(display);
  Atom supported = XInternAtom(xdisplay, "_NET_SUPPORTED", True);
  const Atom active = XInternAtom(xdisplay, "_NET_ACTIVE_WINDOW", False);
  if (supported == None) return false;

  Atom type = None;
  int format = 0;
  unsigned long count = 0;
  unsigned long after = 0;
  unsigned char* data = nullptr;
  int status = BadImplementation;
  const bool clean = WithX11ErrorTrap(display, [&] {
    status = XGetWindowProperty(xdisplay, DefaultRootWindow(xdisplay),
                                supported, 0, 4096, False, XA_ATOM, &type,
                                &format, &count, &after, &data);
  });
  bool found = false;
  if (clean && status == Success && data != nullptr && format == 32) {
    const unsigned long* atoms = reinterpret_cast<unsigned long*>(data);
    for (unsigned long i = 0; i < count; ++i) {
      if (atoms[i] == active) found = true;
    }
  }
  if (data != nullptr) XFree(data);
  return found;
}

namespace {

// Whether the atom list [property] of [window] contains [atom] (EWMH
// _NET_WM_STATE, _NET_WM_WINDOW_TYPE). False when an atom is unknown to the
// server or the window is gone.
bool X11WindowListsAtom(GdkDisplay* display, Window window,
                        const char* property, const char* atom) {
  Display* xdisplay = gdk_x11_display_get_xdisplay(display);
  const Atom list = XInternAtom(xdisplay, property, True);
  const Atom wanted = XInternAtom(xdisplay, atom, True);
  if (list == None || wanted == None) return false;

  Atom type = None;
  int format = 0;
  unsigned long count = 0;
  unsigned long after = 0;
  unsigned char* data = nullptr;
  int status = BadImplementation;
  const bool clean = WithX11ErrorTrap(display, [&] {
    status = XGetWindowProperty(xdisplay, window, list, 0, 64, False, XA_ATOM,
                                &type, &format, &count, &after, &data);
  });
  bool found = false;
  if (clean && status == Success && data != nullptr && format == 32) {
    const unsigned long* atoms = reinterpret_cast<unsigned long*>(data);
    for (unsigned long i = 0; i < count; ++i) {
      if (atoms[i] == wanted) found = true;
    }
  }
  if (data != nullptr) XFree(data);
  return found;
}

}  // namespace

bool X11WindowIsFullscreen(GdkDisplay* display, Window window) {
  if (window == 0) return false;
  if (X11WindowListsAtom(display, window, "_NET_WM_STATE",
                         "_NET_WM_STATE_FULLSCREEN")) {
    return true;
  }
  // The desktop (icons/wallpaper window) fills the monitor too, but is no
  // fullscreen app.
  if (X11WindowListsAtom(display, window, "_NET_WM_WINDOW_TYPE",
                         "_NET_WM_WINDOW_TYPE_DESKTOP")) {
    return false;
  }

  // Frame in root coordinates (physical px).
  Display* xdisplay = gdk_x11_display_get_xdisplay(display);
  XWindowAttributes attributes = {};
  Status got = 0;
  int root_x = 0;
  int root_y = 0;
  Window child = 0;
  const bool clean = WithX11ErrorTrap(display, [&] {
    got = XGetWindowAttributes(xdisplay, window, &attributes);
    if (got != 0) {
      XTranslateCoordinates(xdisplay, window, attributes.root, 0, 0, &root_x,
                            &root_y, &child);
    }
  });
  if (!clean || got == 0) return false;
  const side_panel_edge::Rect frame{root_x, root_y, root_x + attributes.width,
                                    root_y + attributes.height};
  const int n = gdk_display_get_n_monitors(display);
  for (int i = 0; i < n; ++i) {
    GdkMonitor* monitor = gdk_display_get_monitor(display, i);
    if (monitor == nullptr) continue;
    GdkRectangle g;
    gdk_monitor_get_geometry(monitor, &g);
    // GDK reports application (scaled) px; X11 frames are physical px.
    const int scale = gdk_monitor_get_scale_factor(monitor);
    const side_panel_edge::Rect rect{g.x * scale, g.y * scale,
                                     (g.x + g.width) * scale,
                                     (g.y + g.height) * scale};
    if (side_panel_edge::CoversMonitor(frame, rect)) return true;
  }
  return false;
}
