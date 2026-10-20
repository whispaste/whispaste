#include "x11_window.h"

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

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
