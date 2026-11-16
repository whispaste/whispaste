#include "eis_keyboard_sender.h"

#include <unistd.h>

#include <chrono>
#include <utility>

#ifdef WHISPASTE_HAVE_LIBEI

#include <dlfcn.h>
#include <linux/input-event-codes.h>
#include <poll.h>

#include <cerrno>
#include <libei-1.0/libei.h>

// Function pointers resolved from libei.so.1 at run time. The types come from
// the libei header, so a signature change there is a build error, not a crash.
struct LibeiApi {
  decltype(&ei_new_sender) new_sender;
  decltype(&ei_configure_name) configure_name;
  decltype(&ei_setup_backend_fd) setup_backend_fd;
  decltype(&ei_get_fd) get_fd;
  decltype(&ei_dispatch) dispatch;
  decltype(&ei_get_event) get_event;
  decltype(&ei_event_get_type) event_get_type;
  decltype(&ei_event_get_seat) event_get_seat;
  decltype(&ei_event_get_device) event_get_device;
  decltype(&ei_event_unref) event_unref;
  decltype(&ei_seat_bind_capabilities) seat_bind_capabilities;
  decltype(&ei_seat_has_capability) seat_has_capability;
  decltype(&ei_device_has_capability) device_has_capability;
  decltype(&ei_device_ref) device_ref;
  decltype(&ei_device_unref) device_unref;
  decltype(&ei_device_start_emulating) device_start_emulating;
  decltype(&ei_device_stop_emulating) device_stop_emulating;
  decltype(&ei_device_keyboard_key) device_keyboard_key;
  decltype(&ei_device_frame) device_frame;
  decltype(&ei_now) now;
  decltype(&ei_disconnect) disconnect;
  decltype(&ei_unref) unref;
};

namespace {

// Loaded once. Null when libei.so.1 is missing or lacks one of the symbols.
const LibeiApi* LoadLibei() {
  static const LibeiApi* const api = []() -> const LibeiApi* {
    void* lib = dlopen("libei.so.1", RTLD_LAZY | RTLD_LOCAL);
    if (lib == nullptr) return nullptr;
    static LibeiApi loaded = {};
#define WP_LOAD(field, symbol)                                          \
  loaded.field = reinterpret_cast<decltype(loaded.field)>(              \
      dlsym(lib, #symbol));                                             \
  if (loaded.field == nullptr) return nullptr;
    WP_LOAD(new_sender, ei_new_sender)
    WP_LOAD(configure_name, ei_configure_name)
    WP_LOAD(setup_backend_fd, ei_setup_backend_fd)
    WP_LOAD(get_fd, ei_get_fd)
    WP_LOAD(dispatch, ei_dispatch)
    WP_LOAD(get_event, ei_get_event)
    WP_LOAD(event_get_type, ei_event_get_type)
    WP_LOAD(event_get_seat, ei_event_get_seat)
    WP_LOAD(event_get_device, ei_event_get_device)
    WP_LOAD(event_unref, ei_event_unref)
    WP_LOAD(seat_bind_capabilities, ei_seat_bind_capabilities)
    WP_LOAD(seat_has_capability, ei_seat_has_capability)
    WP_LOAD(device_has_capability, ei_device_has_capability)
    WP_LOAD(device_ref, ei_device_ref)
    WP_LOAD(device_unref, ei_device_unref)
    WP_LOAD(device_start_emulating, ei_device_start_emulating)
    WP_LOAD(device_stop_emulating, ei_device_stop_emulating)
    WP_LOAD(device_keyboard_key, ei_device_keyboard_key)
    WP_LOAD(device_frame, ei_device_frame)
    WP_LOAD(now, ei_now)
    WP_LOAD(disconnect, ei_disconnect)
    WP_LOAD(unref, ei_unref)
#undef WP_LOAD
    return &loaded;
  }();
  return api;
}

}  // namespace

EisKeyboardSender::EisKeyboardSender(int fd) : fd_(fd) {
  api_ = LoadLibei();
  if (api_ == nullptr) {
    close(fd_);
    fd_ = -1;
    return;
  }
  ctx_ = api_->new_sender(nullptr);
  if (ctx_ == nullptr) {
    close(fd_);
    fd_ = -1;
    return;
  }
  api_->configure_name(ctx_, "whispaste");
  // libei owns fd from here on, also when the setup fails.
  if (api_->setup_backend_fd(ctx_, fd_) != 0) {
    api_->unref(ctx_);
    ctx_ = nullptr;
  }
  fd_ = -1;
}

EisKeyboardSender::~EisKeyboardSender() { Close(); }

// static
bool EisKeyboardSender::IsLibeiAvailable() { return LoadLibei() != nullptr; }

bool EisKeyboardSender::WaitUntilReady(int timeout_ms) {
  if (ctx_ == nullptr) return false;
  using Clock = std::chrono::steady_clock;
  const auto deadline = Clock::now() + std::chrono::milliseconds(timeout_ms);

  // Events may already be queued from the connect itself.
  api_->dispatch(ctx_);
  DrainEvents();
  while (!keyboard_ready_ && !disconnected_) {
    const auto left = std::chrono::duration_cast<std::chrono::milliseconds>(
        deadline - Clock::now());
    if (left.count() <= 0) break;
    pollfd pfd = {api_->get_fd(ctx_), POLLIN, 0};
    const int n = poll(&pfd, 1, static_cast<int>(left.count()));
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) break;
    api_->dispatch(ctx_);
    DrainEvents();
  }
  return keyboard_ready_;
}

bool EisKeyboardSender::SendCtrlShortcut(uint32_t keycode, bool shift) {
  if (ctx_ == nullptr) return false;
  // Pick up pause or disconnect events that arrived since the last call.
  api_->dispatch(ctx_);
  DrainEvents();
  if (!keyboard_ready_ || keyboard_ == nullptr) return false;

  const uint32_t sequence = ++sequence_;
  api_->device_start_emulating(keyboard_, sequence);
  api_->device_keyboard_key(keyboard_, KEY_LEFTCTRL, true);
  if (shift) api_->device_keyboard_key(keyboard_, KEY_LEFTSHIFT, true);
  api_->device_keyboard_key(keyboard_, keycode, true);
  api_->device_keyboard_key(keyboard_, keycode, false);
  // All key events go out in one frame. Modifiers are released in the same
  // frame, so a failure cannot leave one pressed.
  if (shift) api_->device_keyboard_key(keyboard_, KEY_LEFTSHIFT, false);
  api_->device_keyboard_key(keyboard_, KEY_LEFTCTRL, false);
  api_->device_frame(keyboard_, api_->now(ctx_));
  api_->device_stop_emulating(keyboard_);
  // Writes the queued requests to the socket and sees a disconnect right away.
  api_->dispatch(ctx_);
  DrainEvents();
  return !disconnected_;
}

void EisKeyboardSender::Close() {
  if (keyboard_ != nullptr) {
    api_->device_unref(keyboard_);
    keyboard_ = nullptr;
  }
  keyboard_ready_ = false;
  if (ctx_ != nullptr) {
    api_->disconnect(ctx_);
    api_->unref(ctx_);
    ctx_ = nullptr;
  }
}

void EisKeyboardSender::DrainEvents() {
  if (ctx_ == nullptr) return;
  while (ei_event* event = api_->get_event(ctx_)) {
    HandleEvent(event);
    api_->event_unref(event);
  }
}

void EisKeyboardSender::HandleEvent(ei_event* event) {
  switch (api_->event_get_type(event)) {
    case EI_EVENT_DISCONNECT:
      disconnected_ = true;
      keyboard_ready_ = false;
      break;
    case EI_EVENT_SEAT_ADDED: {
      // Bind the keyboard capability on the first seat that offers one.
      ei_seat* seat = api_->event_get_seat(event);
      if (!bound_ && api_->seat_has_capability(seat, EI_DEVICE_CAP_KEYBOARD)) {
        // The variadic list is terminated by a real null pointer (sentinel).
        api_->seat_bind_capabilities(seat, EI_DEVICE_CAP_KEYBOARD,
                                     static_cast<void*>(nullptr));
        bound_ = true;
      }
      break;
    }
    case EI_EVENT_DEVICE_ADDED: {
      ei_device* device = api_->event_get_device(event);
      if (keyboard_ == nullptr &&
          api_->device_has_capability(device, EI_DEVICE_CAP_KEYBOARD)) {
        keyboard_ = api_->device_ref(device);
      }
      break;
    }
    case EI_EVENT_DEVICE_RESUMED:
      if (keyboard_ != nullptr && api_->event_get_device(event) == keyboard_) {
        keyboard_ready_ = true;
      }
      break;
    case EI_EVENT_DEVICE_PAUSED:
      if (keyboard_ != nullptr && api_->event_get_device(event) == keyboard_) {
        keyboard_ready_ = false;
      }
      break;
    case EI_EVENT_DEVICE_REMOVED:
      if (keyboard_ != nullptr && api_->event_get_device(event) == keyboard_) {
        keyboard_ready_ = false;
        api_->device_unref(keyboard_);
        keyboard_ = nullptr;
      }
      break;
    default:
      break;
  }
}

#else  // !WHISPASTE_HAVE_LIBEI

// Built without libei headers: the portal path reports unavailable and this
// class is never constructed in a working way.
EisKeyboardSender::EisKeyboardSender(int fd) { close(fd); }
EisKeyboardSender::~EisKeyboardSender() = default;
bool EisKeyboardSender::IsLibeiAvailable() { return false; }
bool EisKeyboardSender::WaitUntilReady(int) { return false; }
bool EisKeyboardSender::SendCtrlShortcut(uint32_t, bool) { return false; }
void EisKeyboardSender::Close() {}
void EisKeyboardSender::DrainEvents() {}
void EisKeyboardSender::HandleEvent(struct ei_event*) {}

#endif  // WHISPASTE_HAVE_LIBEI
