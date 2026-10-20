// Runtime test of the X error trap (x11_window.h) on a real X display: reading
// the class of a window that is already gone must not end the process
// (XP-7-18). Run via test/scripts/x11_window_test.sh (private Xvfb).
#include "x11_window.h"

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <gtk/gtk.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cstdio>

namespace {

// No client owns this ID on a fresh Xvfb.
constexpr Window kMissingWindow = 0x7ffffff;

int failures = 0;

void Expect(bool ok, const char* what) {
  if (!ok) {
    std::fprintf(stderr, "FAIL: %s\n", what);
    ++failures;
  }
}

// Control: the same read without the trap ends the process. Without this,
// the test would also pass on a GDK that ignores X errors on its own.
bool UntrappedReadEndsProcess() {
  const pid_t pid = fork();
  if (pid == 0) {
    gtk_init(nullptr, nullptr);
    Display* xdisplay =
        gdk_x11_display_get_xdisplay(gdk_display_get_default());
    XClassHint hint = {};
    XGetClassHint(xdisplay, kMissingWindow, &hint);
    XSync(xdisplay, False);
    _exit(0);
  }
  int status = 0;
  waitpid(pid, &status, 0);
  return !(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

}  // namespace

int main() {
  Expect(UntrappedReadEndsProcess(),
         "control: an untrapped BadWindow ends the process");

  g_set_prgname("x11-window-test");
  gtk_init(nullptr, nullptr);
  GdkDisplay* display = gdk_display_get_default();

  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_widget_realize(window);
  const Window xid = GDK_WINDOW_XID(gtk_widget_get_window(window));
  Expect(X11WindowResName(display, xid) == "x11-window-test",
         "reads the class name of a live window");

  Display* xdisplay = gdk_x11_display_get_xdisplay(display);
  Expect(X11ActiveWindow(display) == 0,
         "no active window without a window manager");
  // What an EWMH window manager publishes when the window has focus.
  const Atom active = XInternAtom(xdisplay, "_NET_ACTIVE_WINDOW", False);
  XChangeProperty(xdisplay, DefaultRootWindow(xdisplay), active, XA_WINDOW,
                  32, PropModeReplace,
                  reinterpret_cast<const unsigned char*>(&xid), 1);
  gdk_display_sync(display);
  Expect(X11ActiveWindow(display) == xid, "reads the active window");
  Expect(X11WindowExists(display, xid), "a live window exists");

  gtk_widget_destroy(window);
  gdk_display_sync(display);
  Expect(!X11WindowExists(display, xid), "a closed window no longer exists");
  Expect(!X11WindowExists(display, kMissingWindow),
         "an unknown window ID does not exist");
  // Asking to focus a closed window must not end the process either.
  X11RequestActivation(display, xid);
  gdk_display_sync(display);
  Expect(X11WindowResName(display, xid).empty(),
         "a closed window reads as empty instead of ending the process");
  Expect(X11WindowResName(display, kMissingWindow).empty(),
         "an unknown window ID reads as empty");

  bool ran = false;
  Expect(!WithX11ErrorTrap(display,
                           [&] {
                             ran = true;
                             XClassHint hint = {};
                             XGetClassHint(gdk_x11_display_get_xdisplay(
                                               display),
                                           kMissingWindow, &hint);
                           }),
         "the trap reports the X error");
  Expect(ran, "the trap runs the calls");

  if (failures == 0) std::printf("x11_window_test: all checks passed\n");
  return failures == 0 ? 0 : 1;
}
