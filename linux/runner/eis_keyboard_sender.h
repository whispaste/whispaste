#ifndef FLUTTER_EIS_KEYBOARD_SENDER_H_
#define FLUTTER_EIS_KEYBOARD_SENDER_H_

#include <cstdint>

struct ei;
struct ei_device;
struct ei_event;
struct LibeiApi;

// Keyboard shortcuts over libei, the sender side of the EIS protocol. The EIS
// socket comes from xdg-desktop-portal RemoteDesktop.ConnectToEIS (see
// portal_remote_desktop.h); this class only speaks the libei protocol on it.
//
// libei is loaded with dlopen() at run time, so the .deb gets no hard
// dependency on it. Without the libei headers at build time (WHISPASTE_HAVE_LIBEI
// undefined) the class is compiled out and IsLibeiAvailable() is false.
//
// Not thread-safe: use it from the GTK main thread only.
class EisKeyboardSender {
 public:
  // Takes ownership of [fd] (libei closes it on teardown), even on failure.
  explicit EisKeyboardSender(int fd);
  ~EisKeyboardSender();

  EisKeyboardSender(const EisKeyboardSender&) = delete;
  EisKeyboardSender& operator=(const EisKeyboardSender&) = delete;

  // True when libei.so.1 can be dlopen()ed and this build has libei support.
  static bool IsLibeiAvailable();

  // Runs the EIS handshake (seat, keyboard capability, device resumed) until
  // the keyboard device is ready or [timeout_ms] has passed. Blocking, meant
  // once right after connecting.
  bool WaitUntilReady(int timeout_ms);

  bool ready() const { return keyboard_ready_; }

  // Sends Ctrl+<keycode> (Ctrl+Shift+<keycode> with [shift]) as one EIS frame:
  // modifiers and key are pressed and released in that frame. Returns false
  // when the keyboard device is not ready, nothing is sent then.
  // [keycode] is an evdev code (KEY_V, KEY_C, ...).
  bool SendCtrlShortcut(uint32_t keycode, bool shift);

  // Sends the disconnect and drops the device. Safe to call more than once.
  void Close();

 private:
  // Processes all queued libei events and tracks the keyboard device state.
  void DrainEvents();
  void HandleEvent(struct ei_event* event);

  int fd_ = -1;
  ei* ctx_ = nullptr;
  ei_device* keyboard_ = nullptr;
  bool bound_ = false;
  bool keyboard_ready_ = false;
  bool disconnected_ = false;
  uint32_t sequence_ = 0;
  // libei function pointers, resolved by dlopen (see eis_keyboard_sender.cc).
  const LibeiApi* api_ = nullptr;
};

#endif  // FLUTTER_EIS_KEYBOARD_SENDER_H_
