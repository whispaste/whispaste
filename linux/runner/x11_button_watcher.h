#ifndef RUNNER_X11_BUTTON_WATCHER_H_
#define RUNNER_X11_BUTTON_WATCHER_H_

#include <glib.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <thread>

// Tells hardware key presses and mouse clicks apart for the keystroke undo
// (#428, #579). XScreenSaver only knows one idle time for everything, so the
// click on the undo action itself would read as typing. This watcher reads
// the XInput2 raw key and button presses of an X11 session on its own
// connection and keeps when the last one happened; a click only counts as
// "outside WhisPaste" when the pointer was not over a window of this process.
// It only runs while an undo can still follow an insert (the host starts it
// after a paste and stops it again), so key and click times are not observed
// the rest of the time. Wayland sessions have no such source: [running] stays false there and the
// undo takes the clipboard path.
//
// The snippet picker (#1680) runs a second watcher with |watch_keys| false
// while it is open, to see a click outside it: it never selects key events
// and only uses the click callback ([SetOnClick]).
class X11ButtonWatcher {
 public:
  explicit X11ButtonWatcher(bool watch_keys = true) : watch_keys_(watch_keys) {}
  ~X11ButtonWatcher();

  X11ButtonWatcher(const X11ButtonWatcher&) = delete;
  X11ButtonWatcher& operator=(const X11ButtonWatcher&) = delete;

  // Opens the connection and starts the thread. False (and nothing running)
  // when the session is not X11 or XInput2 is missing. Call once, on the
  // GTK main thread.
  bool Start();

  // Ends the thread, closes the connection and forgets all times. Safe when
  // not running; Start() works again afterwards. Main thread only.
  void Stop();

  bool running() const { return running_.load(); }

  // Seconds since the last raw key press, the last click anywhere and the
  // last click outside this process's windows; 1e9 when there was none.
  double KeyIdleSeconds() const;
  double MouseIdleSeconds() const;
  double MouseIdleOutsideAppSeconds() const;

  // Called on the GTK main thread after a button press (not a scroll-wheel
  // step), once per batch of presses. Set before Start(); main thread only.
  using OnClickCallback = void (*)(void* user_data);
  void SetOnClick(OnClickCallback cb, void* user_data) {
    on_click_cb_ = cb;
    on_click_user_data_ = user_data;
  }

 private:
  void Run(int stop_fd);
  static int64_t NowNs();
  static double Since(const std::atomic<int64_t>& stamp);
  static gboolean OnButtonOnMainThread(gpointer user_data);

  const bool watch_keys_;
  OnClickCallback on_click_cb_ = nullptr;
  void* on_click_user_data_ = nullptr;
  // Non-wheel presses not yet handed to the main thread.
  std::atomic<int> pending_clicks_{0};

  std::thread thread_;
  int stop_pipe_[2] = {-1, -1};
  std::atomic<bool> running_{false};
  std::atomic<int64_t> last_key_ns_{0};
  std::atomic<int64_t> last_button_ns_{0};
  std::atomic<int64_t> last_foreign_button_ns_{0};
};

#endif  // RUNNER_X11_BUTTON_WATCHER_H_
