#include "x11_button_watcher.h"

#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>
#include <cerrno>
#include <gdk/gdk.h>
#include <gdk/gdkx.h>
#include <poll.h>
#include <unistd.h>

namespace {
constexpr double kNever = 1e9;
}  // namespace

X11ButtonWatcher::~X11ButtonWatcher() { Stop(); }

void X11ButtonWatcher::Stop() {
  if (stop_pipe_[1] >= 0) {
    const char byte = 0;
    if (write(stop_pipe_[1], &byte, 1) < 0) {
      // The thread ends with the process anyway.
    }
  }
  if (thread_.joinable()) thread_.join();
  // Button presses queued for the main loop before the join must not run
  // against this object after it is gone.
  g_idle_remove_by_data(this);
  for (int& fd : stop_pipe_) {
    if (fd >= 0) close(fd);
    fd = -1;
  }
  running_.store(false);
  last_key_ns_.store(0);
  last_button_ns_.store(0);
  last_foreign_button_ns_.store(0);
  pending_clicks_.store(0);
}

// static
int64_t X11ButtonWatcher::NowNs() {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

// static
double X11ButtonWatcher::Since(const std::atomic<int64_t>& stamp) {
  const int64_t at = stamp.load();
  if (at == 0) return kNever;
  return static_cast<double>(NowNs() - at) / 1e9;
}

double X11ButtonWatcher::KeyIdleSeconds() const { return Since(last_key_ns_); }
double X11ButtonWatcher::MouseIdleSeconds() const {
  return Since(last_button_ns_);
}
double X11ButtonWatcher::MouseIdleOutsideAppSeconds() const {
  return Since(last_foreign_button_ns_);
}

bool X11ButtonWatcher::Start() {
  if (running_.load()) return true;
  // A thread that ended on its own (failed poll) is cleaned up first.
  Stop();
  GdkDisplay* gdk_display = gdk_display_get_default();
  if (gdk_display == nullptr || !GDK_IS_X11_DISPLAY(gdk_display)) return false;
  if (pipe(stop_pipe_) != 0) {
    stop_pipe_[0] = stop_pipe_[1] = -1;
    return false;
  }
  // Own connection: the thread blocks in poll() and must not share Xlib
  // state with GDK's connection.
  Display* display = XOpenDisplay(nullptr);
  if (display == nullptr) return false;
  int opcode = 0;
  int event_base = 0;
  int error_base = 0;
  int major = 2;
  int minor = 0;
  if (!XQueryExtension(display, "XInputExtension", &opcode, &event_base,
                       &error_base) ||
      XIQueryVersion(display, &major, &minor) != Success) {
    XCloseDisplay(display);
    return false;
  }
  unsigned char mask_bits[XIMaskLen(XI_LASTEVENT)] = {};
  XIEventMask mask;
  mask.deviceid = XIAllMasterDevices;
  mask.mask_len = sizeof(mask_bits);
  mask.mask = mask_bits;
  if (watch_keys_) XISetMask(mask_bits, XI_RawKeyPress);
  XISetMask(mask_bits, XI_RawButtonPress);
  XISelectEvents(display, DefaultRootWindow(display), &mask, 1);
  XFlush(display);

  running_.store(true);
  const int stop_fd = stop_pipe_[0];
  thread_ = std::thread([this, display, opcode, stop_fd] {
    const int x_fd = ConnectionNumber(display);
    while (true) {
      while (XPending(display) > 0) {
        XEvent event;
        XNextEvent(display, &event);
        XGenericEventCookie* cookie = &event.xcookie;
        if (cookie->type != GenericEvent || cookie->extension != opcode ||
            !XGetEventData(display, cookie)) {
          continue;
        }
        if (cookie->evtype == XI_RawKeyPress) {
          last_key_ns_.store(NowNs());
        } else if (cookie->evtype == XI_RawButtonPress) {
          // Scroll wheel steps (buttons 4-7) count as clicks too: more input
          // only makes the undo take the safe clipboard path.
          last_button_ns_.store(NowNs());
          // Buttons 4-7 are wheel steps: no click for the click callback.
          const int button =
              static_cast<XIRawEvent*>(cookie->data)->detail;
          if (button < 4 || button > 7) pending_clicks_.fetch_add(1);
          // Where the pointer is can only be asked on the main thread (GDK).
          g_idle_add(OnButtonOnMainThread, this);
        }
        XFreeEventData(display, cookie);
      }
      struct pollfd fds[2] = {{x_fd, POLLIN, 0}, {stop_fd, POLLIN, 0}};
      if (poll(fds, 2, -1) < 0) {
        // A failing poll() would spin the thread; only EINTR is retried. The
        // watcher then stops and the undo gate answers "unsupported".
        if (errno == EINTR) continue;
        break;
      }
      if ((fds[1].revents & POLLIN) != 0) break;
    }
    running_.store(false);
    XCloseDisplay(display);
  });
  return true;
}

// static
gboolean X11ButtonWatcher::OnButtonOnMainThread(gpointer user_data) {
  auto* self = static_cast<X11ButtonWatcher*>(user_data);
  GdkDisplay* display = gdk_display_get_default();
  GdkSeat* seat = display != nullptr ? gdk_display_get_default_seat(display)
                                     : nullptr;
  GdkDevice* pointer = seat != nullptr ? gdk_seat_get_pointer(seat) : nullptr;
  // A window is returned only when it belongs to this process, so a click on
  // the undo action (or any WhisPaste window) is not "outside".
  const bool own =
      pointer != nullptr &&
      gdk_device_get_window_at_position(pointer, nullptr, nullptr) != nullptr;
  if (!own) self->last_foreign_button_ns_.store(NowNs());
  if (self->pending_clicks_.exchange(0) > 0 && self->on_click_cb_ != nullptr) {
    self->on_click_cb_(self->on_click_user_data_);
  }
  return G_SOURCE_REMOVE;
}
