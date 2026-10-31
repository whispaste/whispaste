#include "desktop_paste_host.h"

#include "clipboard_hint.h"
#include "x11_window.h"
#include "modifier_release.h"
#include "portal_remote_desktop.h"

#include <fcntl.h>
#include <gdk/gdkkeysyms.h>
#include <gdk/gdkx.h>
#include <gtk/gtk.h>
#include <linux/uinput.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <optional>
#include <thread>

#ifdef WHISPASTE_HAVE_XSS
#include <dlfcn.h>
#include <X11/Xlib.h>
#include <X11/extensions/scrnsaver.h>
#endif

namespace {

constexpr char kChannelName[] = "com.whispaste.desktop_paste";

// Poll step of the paste wait, and how long a target brought back gets on top
// of the delay before the paste is refused.
constexpr guint kPastePollMs = 10;
constexpr int kActivationTimeoutMs = 500;

int GetInt(FlValue* map, const char* key, int fallback = 0) {
  if (!map || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return fallback;
  FlValue* v = fl_value_lookup_string(map, key);
  if (!v) return fallback;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) {
    return static_cast<int>(fl_value_get_int(v));
  }
  return fallback;
}

bool GetBool(FlValue* map, const char* key) {
  if (!map || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return false;
  FlValue* v = fl_value_lookup_string(map, key);
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(v);
}

std::string GetString(FlValue* map, const char* key) {
  if (!map || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return {};
  FlValue* v = fl_value_lookup_string(map, key);
  if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) return {};
  return fl_value_get_string(v);
}

FlValue* MakeResultMap(const std::string& status, const std::string& detail) {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "status", fl_value_new_string(status.c_str()));
  if (!detail.empty()) {
    fl_value_set_string_take(map, "detail",
                              fl_value_new_string(detail.c_str()));
  }
  return map;
}

// Restores the user's previous clipboard text with the same hint as the
// transcript path. If the hinted write fails, a plain write keeps the restore
// working. GS-084: that plain write puts the previous text into clipboard
// history (GPaste, CopyQ, ...). The fallback stays on purpose, because losing
// the user's clipboard is worse than one history entry; the warning is logged.
void RestorePreviousClipboard(GtkClipboard* clipboard, const gchar* previous) {
  if (!SetClipboardTextHidden(clipboard, previous)) {
    g_warning("history-excluded restore failed; plain restore used");
    gtk_clipboard_set_text(clipboard, previous, -1);
  }
}

// Emits one EV_KEY event plus its SYN_REPORT on an already-created uinput fd.
bool EmitKey(int fd, int keycode, int value) {
  struct input_event ev = {};
  ev.type = EV_KEY;
  ev.code = static_cast<__u16>(keycode);
  ev.value = value;
  if (write(fd, &ev, sizeof(ev)) != sizeof(ev)) return false;

  struct input_event syn = {};
  syn.type = EV_SYN;
  syn.code = SYN_REPORT;
  syn.value = 0;
  return write(fd, &syn, sizeof(syn)) == sizeof(syn);
}

// Upper bound for waiting on the hotkey's modifiers before the synthetic
// shortcut; after it the shortcut goes out anyway (and is logged).
constexpr int kMaxModifierWaitMs = 1000;

bool IsWaylandSessionEnv() {
  const gchar* type = g_getenv("XDG_SESSION_TYPE");
  if (type != nullptr && g_ascii_strcasecmp(type, "wayland") == 0) return true;
  const gchar* display = g_getenv("WAYLAND_DISPLAY");
  return display != nullptr && display[0] != '\0';
}

// X11 session: the server's merged key state. Under XWayland this only
// reflects keys while an X client has focus, so it is used on X11 only.
std::optional<bool> X11ModifierHeld() {
  if (IsWaylandSessionEnv()) return std::nullopt;
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr || !GDK_IS_X11_DISPLAY(display)) return std::nullopt;
  Display* xdisplay = gdk_x11_display_get_xdisplay(display);
  char keys[32] = {};
  XQueryKeymap(xdisplay, keys);
  const KeySym syms[] = {XK_Shift_L, XK_Shift_R, XK_Control_L, XK_Control_R,
                         XK_Alt_L,   XK_Alt_R,   XK_Super_L,   XK_Super_R,
                         XK_Meta_L,  XK_Meta_R,  XK_ISO_Level3_Shift};
  for (KeySym sym : syms) {
    const KeyCode code = XKeysymToKeycode(xdisplay, sym);
    if (code != 0 && (keys[code / 8] & (1 << (code % 8))) != 0) return true;
  }
  return false;
}

// Wayland: the kernel's key state of every keyboard the user may read
// (group "input"). Unknown when none is readable; then nothing waits.
std::optional<bool> EvdevModifierHeld() {
  const int codes[] = {KEY_LEFTSHIFT, KEY_RIGHTSHIFT, KEY_LEFTCTRL,
                       KEY_RIGHTCTRL, KEY_LEFTALT,    KEY_RIGHTALT,
                       KEY_LEFTMETA,  KEY_RIGHTMETA};
  bool readable = false;
  for (int i = 0; i < 64; i++) {
    char path[32];
    std::snprintf(path, sizeof(path), "/dev/input/event%d", i);
    const int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) continue;
    unsigned char state[KEY_MAX / 8 + 1] = {};
    const bool ok = ioctl(fd, EVIOCGKEY(sizeof(state)), state) >= 0;
    close(fd);
    if (!ok) continue;
    readable = true;
    for (int code : codes) {
      if ((state[code / 8] & (1 << (code % 8))) != 0) return true;
    }
  }
  if (!readable) return std::nullopt;
  return false;
}

std::optional<bool> AnyModifierHeld() {
  if (auto x11 = X11ModifierHeld()) return x11;
  return EvdevModifierHeld();
}

// Blocks until the hotkey's modifiers are up (see modifier_release.h).
void AwaitModifierRelease() {
  const auto result = WaitForModifierRelease(
      AnyModifierHeld, std::chrono::milliseconds(kMaxModifierWaitMs),
      [](std::chrono::milliseconds d) { std::this_thread::sleep_for(d); });
  if (result == ModifierWait::kTimedOut) {
    g_warning("modifier still held after %d ms; shortcut sent anyway",
              kMaxModifierWaitMs);
  }
}

}  // namespace

DesktopPasteHost::DesktopPasteHost(FlBinaryMessenger* main_messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(main_messenger, kChannelName,
                                    FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this,
                                             nullptr);
  receipt_ = std::make_unique<ClipboardReceipt>(
      gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
  snapshot_ = std::make_unique<ClipboardSnapshot>(
      gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
}

DesktopPasteHost::~DesktopPasteHost() { Destroy(); }

void DesktopPasteHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;

  // Pending answers go out while the channel still exists.
  if (paste_timer_ != 0) {
    g_source_remove(paste_timer_);
    paste_timer_ = 0;
  }
  FinishPaste(MakeResultMap("post_failed", "DesktopPasteHost is destroyed"));
  receipt_->Cancel();

  if (channel_) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                               nullptr);
    g_object_unref(channel_);
    channel_ = nullptr;
  }

  // Ends the portal session; a pending portalInputConnect is answered with
  // "cancelled" through its callback.
  if (portal_) portal_->Disconnect();

  if (uinput_fd_ >= 0) {
    ioctl(uinput_fd_, UI_DEV_DESTROY);
    close(uinput_fd_);
    uinput_fd_ = -1;
  }
}

// static
void DesktopPasteHost::OnMethodCall(FlMethodChannel* /*channel*/,
                                     FlMethodCall* method_call,
                                     gpointer user_data) {
  static_cast<DesktopPasteHost*>(user_data)->HandleMethodCall(method_call);
}

void DesktopPasteHost::HandleMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (destroyed_) {
    response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("DESTROYED", "DesktopPasteHost is destroyed",
                                     nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (strcmp(method, "captureTarget") == 0) {
    // Records the focused X11 window for the block list (getTargetBundleId).
    // Paste itself still goes to whatever holds focus. Always reports success
    // so callers don't treat this platform as "no target ever available".
    CaptureTargetWindow();
    response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));

  } else if (strcmp(method, "getTargetBundleId") == 0) {
    g_autoptr(FlValue) result = TargetBundleId();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "pasteClipboard") == 0) {
    // Answered once the wait is over, without blocking the main thread.
    // "via": "portal" routes through the RemoteDesktop keyboard; any other
    // value (or none) keeps the uinput path.
    StartPaste(method_call, GetInt(args, "delayMs", 0),
               GetString(args, "via") == "portal", GetBool(args, "shift"));
    return;

  } else if (strcmp(method, "copySelection") == 0) {
    const int delay_ms = GetInt(args, "delayMs", 0);
    g_autoptr(FlValue) result = CopySelection(
        delay_ms, GetString(args, "via") == "portal", GetBool(args, "shift"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "typeText") == 0) {
    const std::string text = GetString(args, "text");
    const int delay_ms = GetInt(args, "delayMs", 0);
    g_autoptr(FlValue) result =
        TypeText(text, delay_ms, GetString(args, "via") == "portal",
                 GetBool(args, "shift"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "portalInputAvailable") == 0) {
    // RemoteDesktop >= v2 on the session bus and libei loadable.
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(PortalRemoteDesktop::IsAvailable())));

  } else if (strcmp(method, "portalInputConnect") == 0) {
    // Answered later, from the portal callback: the consent dialog waits for
    // the user. The response is sent in StartPortalConnect's callback.
    StartPortalConnect(method_call, GetString(args, "restoreToken"));
    return;

  } else if (strcmp(method, "portalInputDisconnect") == 0) {
    if (portal_) portal_->Disconnect();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "writeClipboardText") == 0) {
    // One write with the Klipper hint (PAR-012). True means Dart writes
    // nothing more; false (GTK refused the ownership) means Dart does the
    // single plain write, so the text is never written twice (GS-113, GS-128).
    const std::string text = GetString(args, "text");
    const bool hidden = SetClipboardTextHidden(
        gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), text);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(hidden)));

  } else if (strcmp(method, "writeClipboardTextWithReceipt") == 0) {
    const bool armed = receipt_->Write(GetString(args, "text"));
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(armed)));

  } else if (strcmp(method, "waitForClipboardRead") == 0) {
    // Answered on the read, the takeover or a newer wait (GR-015).
    FlMethodCall* call = FL_METHOD_CALL(g_object_ref(method_call));
    receipt_->Wait([call](const char* status) {
      g_autoptr(FlValue) result = MakeResultMap(status, "");
      fl_method_call_respond_success(call, result, nullptr);
      g_object_unref(call);
    });
    return;

  } else if (strcmp(method, "restoreClipboardTextIfOwner") == 0) {
    g_autoptr(FlValue) result =
        MakeResultMap(receipt_->RestoreIfOwner(GetString(args, "text")), "");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "snapshotClipboard") == 0) {
    // Answered once every target is fetched or the budget ran out.
    FlMethodCall* call = FL_METHOD_CALL(g_object_ref(method_call));
    snapshot_->Take([call](const ClipboardSnapshot::Result& snapshot) {
      g_autoptr(FlValue) result = fl_value_new_map();
      fl_value_set_string_take(result, "status",
                               fl_value_new_string(snapshot.status.c_str()));
      fl_value_set_string_take(result, "formats",
                               fl_value_new_int(snapshot.formats));
      fl_value_set_string_take(result, "bytes",
                               fl_value_new_int(snapshot.bytes));
      if (snapshot.has_text) {
        fl_value_set_string_take(
            result, "text",
            fl_value_new_string_sized(snapshot.text.data(),
                                      snapshot.text.size()));
      }
      fl_method_call_respond_success(call, result, nullptr);
      g_object_unref(call);
    });
    return;

  } else if (strcmp(method, "restoreClipboardSnapshotIfOwner") == 0) {
    const char* status = "failed";
    std::string outcome;
    if (snapshot_->HasData()) {
      outcome = receipt_->RestoreIfOwnerWith(
          [this] { return snapshot_->Restore(); });
      status = outcome.c_str();
    }
    snapshot_->Discard();
    g_autoptr(FlValue) result = MakeResultMap(status, "");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "discardClipboardSnapshot") == 0) {
    snapshot_->Discard();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "inputIdleSnapshot") == 0) {
    // Null when the idle source is unavailable (Wayland, no XScreenSaver):
    // Dart then counts the input as typed.
    g_autoptr(FlValue) result = InputIdleSnapshot();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "diagnosticPaste") == 0) {
    const std::string demo_text = GetString(args, "demoText");
    g_autoptr(FlValue) result = DiagnosticPaste(demo_text);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "checkCapability") == 0) {
    g_autoptr(FlValue) result = CheckCapability();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "destroy") == 0) {
    Destroy();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// Every letter key. The active layout decides which key types "v" or "c", and
// uinput drops events for keys it was never told about, so all of them are
// registered up front (see LetterKeycode).
constexpr int kLetterKeys[] = {
    KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J,
    KEY_K, KEY_L, KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T,
    KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z};

// Evdev code of the key that types the letter [keyval] on the active layout,
// or [fallback] when the keymap has no such key. GDK hardware keycodes are
// evdev codes plus 8 on X11 and Wayland, so the offset is removed here. The
// unshifted entry (group 0, level 0) is preferred.
int DesktopPasteHost::LetterKeycode(guint keyval, int fallback) {
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr) return fallback;
  GdkKeymap* keymap = gdk_keymap_get_for_display(display);
  GdkKeymapKey* keys = nullptr;
  gint count = 0;
  int result = fallback;
  if (gdk_keymap_get_entries_for_keyval(keymap, keyval, &keys, &count) &&
      keys != nullptr && count > 0) {
    gint pick = 0;
    for (gint i = 0; i < count; ++i) {
      if (keys[i].group == 0 && keys[i].level == 0) {
        pick = i;
        break;
      }
    }
    if (keys[pick].keycode >= 8) {
      result = static_cast<int>(keys[pick].keycode) - 8;
    }
  }
  g_free(keys);
  return result;
}

void DesktopPasteHost::StartPortalConnect(FlMethodCall* method_call,
                                          const std::string& restore_token) {
  if (pending_connect_ != nullptr) {
    RespondConnect(method_call, "failed", "");
    return;
  }
  if (!portal_) portal_ = std::make_unique<PortalRemoteDesktop>();
  pending_connect_ = FL_METHOD_CALL(g_object_ref(method_call));
  portal_->Connect(
      restore_token, [this](const PortalRemoteDesktop::ConnectResult& result) {
        FlMethodCall* call = pending_connect_;
        pending_connect_ = nullptr;
        if (call == nullptr) return;
        const char* status = "failed";
        switch (result.status) {
          case PortalRemoteDesktop::ConnectOutcome::kConnected:
            status = "connected";
            break;
          case PortalRemoteDesktop::ConnectOutcome::kCancelled:
            status = "cancelled";
            break;
          case PortalRemoteDesktop::ConnectOutcome::kUnavailable:
            status = "unavailable";
            break;
          case PortalRemoteDesktop::ConnectOutcome::kFailed:
            break;
        }
        RespondConnect(call, status, result.restore_token);
        g_object_unref(call);
      });
}

// static
void DesktopPasteHost::RespondConnect(FlMethodCall* method_call,
                                      const char* status,
                                      const std::string& restore_token) {
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "status", fl_value_new_string(status));
  fl_value_set_string_take(
      map, "restoreToken",
      restore_token.empty() ? fl_value_new_null()
                            : fl_value_new_string(restore_token.c_str()));
  fl_method_call_respond(
      method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(map)),
      nullptr);
}

bool DesktopPasteHost::SendShortcut(int keycode, bool shift, bool via_portal) {
  if (!via_portal) return SendCtrlShortcut(keycode, shift);
  if (!portal_ || !portal_->SendCtrlShortcut(static_cast<uint32_t>(keycode), shift)) {
    return false;
  }
  // Our own injected keys count as synthetic input for the undo gate, as on
  // the uinput path.
  last_synthetic_key_ = std::chrono::steady_clock::now();
  has_synthetic_key_ = true;
  return true;
}

bool DesktopPasteHost::EnsureUinputDevice() {
  if (uinput_fd_ >= 0) return true;

  int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
  if (fd < 0) return false;

  if (ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0 ||
      ioctl(fd, UI_SET_KEYBIT, KEY_LEFTCTRL) < 0 ||
      ioctl(fd, UI_SET_KEYBIT, KEY_LEFTSHIFT) < 0 ||
      ioctl(fd, UI_SET_KEYBIT, KEY_V) < 0 ||
      ioctl(fd, UI_SET_KEYBIT, KEY_C) < 0) {
    close(fd);
    return false;
  }
  for (const int key : kLetterKeys) {
    if (ioctl(fd, UI_SET_KEYBIT, key) < 0) {
      close(fd);
      return false;
    }
  }

  struct uinput_setup usetup = {};
  usetup.id.bustype = BUS_USB;
  usetup.id.vendor = 0x1209;   // pid.codes test/hobbyist VID — no real device.
  usetup.id.product = 0x0001;
  strncpy(usetup.name, "whispaste-virtual-kbd", sizeof(usetup.name) - 1);

  if (ioctl(fd, UI_DEV_SETUP, &usetup) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) {
    close(fd);
    return false;
  }

  // The kernel registers the device asynchronously — a paste sent
  // immediately after UI_DEV_CREATE can be dropped before udev/the
  // compositor has picked it up. This only costs time once per process
  // lifetime (the fd is kept open and reused for every subsequent paste).
  std::this_thread::sleep_for(std::chrono::milliseconds(100));

  uinput_fd_ = fd;
  return true;
}

bool DesktopPasteHost::SendPasteShortcut(bool shift) {
  return SendCtrlShortcut(LetterKeycode(GDK_KEY_v, KEY_V), shift);
}

bool DesktopPasteHost::SendCtrlShortcut(int keycode, bool shift) {
  if (!EnsureUinputDevice()) return false;
  last_synthetic_key_ = std::chrono::steady_clock::now();
  has_synthetic_key_ = true;
  bool ok = EmitKey(uinput_fd_, KEY_LEFTCTRL, 1);
  if (ok && shift) ok = EmitKey(uinput_fd_, KEY_LEFTSHIFT, 1);
  ok = ok && EmitKey(uinput_fd_, keycode, 1) && EmitKey(uinput_fd_, keycode, 0);
  // Release the modifiers even after a failed write so none stays held.
  if (shift) ok = EmitKey(uinput_fd_, KEY_LEFTSHIFT, 0) && ok;
  return EmitKey(uinput_fd_, KEY_LEFTCTRL, 0) && ok;
}

// GS-070: the idle source is trusted only on a plain X11 session. Under
// Wayland (or XWayland with WAYLAND_DISPLAY set) XScreenSaver does not see
// native Wayland input, so any Wayland hint fails closed. Pure function so the
// decision stays testable without a GTK display.
bool IdleSnapshotTrusted(bool is_x11_display, const char* wayland_display,
                         const char* session_type) {
  if (!is_x11_display) return false;
  if (wayland_display != nullptr) return false;
  if (session_type != nullptr && std::strcmp(session_type, "wayland") == 0) {
    return false;
  }
  return true;
}

#ifdef WHISPASTE_HAVE_XSS
// libXScrnSaver is loaded with dlopen, not linked. A linked binary cannot
// start on a host without libxss1 (the release tarball declares no such
// dependency), and losing the idle source must not cost the whole app. A null
// result means: no idle source, so the caller takes the clipboard path.
struct XScreenSaverApi {
  XScreenSaverInfo* (*alloc_info)();
  Status (*query_info)(Display*, Drawable, XScreenSaverInfo*);
};

const XScreenSaverApi* LoadXScreenSaver() {
  static const XScreenSaverApi* const api =
      []() -> const XScreenSaverApi* {
    void* lib = dlopen("libXss.so.1", RTLD_LAZY | RTLD_LOCAL);
    if (lib == nullptr) return nullptr;
    static XScreenSaverApi loaded = {};
    loaded.alloc_info = reinterpret_cast<decltype(loaded.alloc_info)>(
        dlsym(lib, "XScreenSaverAllocInfo"));
    loaded.query_info = reinterpret_cast<decltype(loaded.query_info)>(
        dlsym(lib, "XScreenSaverQueryInfo"));
    if (loaded.alloc_info == nullptr || loaded.query_info == nullptr) {
      return nullptr;
    }
    return &loaded;
  }();
  return api;
}
#endif

// Idle ages in seconds for the undo gate (DEV-185, GS-056, DEV-232). On X11
// the XScreenSaver idle time counts every input, injected ones included, so
// keyIdle and mouseIdle are the same conservative value. Dart then treats
// any input since the insert as typing (fail-safe).
void DesktopPasteHost::CaptureTargetWindow() {
  target_window_ = 0;
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr || !GDK_IS_X11_DISPLAY(display)) return;
  target_window_ = X11ActiveWindow(display);
}

FlValue* DesktopPasteHost::TargetBundleId() {
  GdkDisplay* display = gdk_display_get_default();
  if (target_window_ == 0 || display == nullptr ||
      !GDK_IS_X11_DISPLAY(display)) {
    return nullptr;
  }
  // The target may have closed since CaptureTargetWindow (XP-7-18).
  const std::string name = X11WindowResName(display, target_window_);
  if (name.empty()) return nullptr;
  return fl_value_new_string(name.c_str());
}

FlValue* DesktopPasteHost::InputIdleSnapshot() {
#ifdef WHISPASTE_HAVE_XSS
  const XScreenSaverApi* xss = LoadXScreenSaver();
  GdkDisplay* display = gdk_display_get_default();
  const bool x11 = display != nullptr && GDK_IS_X11_DISPLAY(display);
  if (xss != nullptr &&
      IdleSnapshotTrusted(x11, std::getenv("WAYLAND_DISPLAY"),
                          std::getenv("XDG_SESSION_TYPE"))) {
    Display* xdisplay = gdk_x11_display_get_xdisplay(display);
    XScreenSaverInfo* info = xss->alloc_info();
    if (info != nullptr &&
        xss->query_info(xdisplay, DefaultRootWindow(xdisplay), info)) {
      const double idle = info->idle / 1000.0;
      XFree(info);
      double synthetic = 1e9;
      if (has_synthetic_key_) {
        synthetic = std::chrono::duration<double>(
                        std::chrono::steady_clock::now() - last_synthetic_key_)
                        .count();
      }
      FlValue* map = fl_value_new_map();
      fl_value_set_string_take(map, "keyIdle", fl_value_new_float(idle));
      fl_value_set_string_take(map, "mouseIdle", fl_value_new_float(idle));
      fl_value_set_string_take(map, "syntheticIdle",
                               fl_value_new_float(synthetic));
      return map;
    }
    if (info != nullptr) XFree(info);
  }
#endif
  return nullptr;
}

FlValue* DesktopPasteHost::CheckCapability() {
  if (!EnsureUinputDevice()) {
    const bool exists = access("/dev/uinput", F_OK) == 0;
    FlValue* map = MakeResultMap(
        exists ? "permission_missing" : "unsupported",
        exists ? "no write access to /dev/uinput — install "
                  "packaging/linux/71-whispaste-uinput.rules to "
                  "/etc/udev/rules.d/, or add this user to the 'input' "
                  "group and log out/in"
               : "/dev/uinput not present — uinput kernel module unavailable");
    fl_value_set_string_take(map, "canPrompt", fl_value_new_bool(FALSE));
    return map;
  }
  FlValue* map = MakeResultMap("ready", "");
  fl_value_set_string_take(map, "canPrompt", fl_value_new_bool(FALSE));
  return map;
}

// PAR-032: the shortcut only goes out while the captured X11 target has
// focus. A target that lost it is brought back first; a closed one, or one
// the window manager does not bring back, is refused like on macOS.
void DesktopPasteHost::StartPaste(FlMethodCall* call, int delay_ms,
                                  bool via_portal, bool shift) {
  if (paste_call_ != nullptr) {
    // Dart runs one paste at a time; a second call means the first answer
    // was lost, so it gets one now.
    if (paste_timer_ != 0) {
      g_source_remove(paste_timer_);
      paste_timer_ = 0;
    }
    FinishPaste(MakeResultMap("post_failed", "superseded by a newer paste"));
  }
  paste_call_ = FL_METHOD_CALL(g_object_ref(call));
  paste_delay_ms_ = std::max(0, delay_ms);
  paste_via_portal_ = via_portal;
  paste_shift_ = shift;
  paste_started_ = std::chrono::steady_clock::now();
  paste_wait_ = PasteWait::kDelay;

  GdkDisplay* display = gdk_display_get_default();
  if (target_window_ != 0 && display != nullptr &&
      GDK_IS_X11_DISPLAY(display)) {
    if (X11ActiveWindow(display) == target_window_) {
      paste_wait_ = PasteWait::kModifiers;
    } else if (X11WindowExists(display, target_window_)) {
      X11RequestActivation(display, target_window_);
      paste_wait_ = PasteWait::kActivation;
    } else {
      FinishPaste(
          MakeResultMap("target_changed", "the captured window was closed"));
      return;
    }
  }
  if (PasteTick()) return;
  paste_timer_ = g_timeout_add(kPastePollMs, OnPasteTick, this);
}

// static
gboolean DesktopPasteHost::OnPasteTick(gpointer user_data) {
  auto* self = static_cast<DesktopPasteHost*>(user_data);
  if (!self->PasteTick()) return G_SOURCE_CONTINUE;
  self->paste_timer_ = 0;
  return G_SOURCE_REMOVE;
}

bool DesktopPasteHost::PasteTick() {
  const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                           std::chrono::steady_clock::now() - paste_started_)
                           .count();
  GdkDisplay* display = gdk_display_get_default();
  switch (paste_wait_) {
    case PasteWait::kDelay:
      if (elapsed < paste_delay_ms_) return false;
      break;
    case PasteWait::kModifiers:
      // The target has focus: only the modifier wait below.
      break;
    case PasteWait::kActivation:
      if (elapsed < paste_delay_ms_) return false;
      if (X11ActiveWindow(display) != target_window_) {
        if (elapsed < paste_delay_ms_ + kActivationTimeoutMs) return false;
        FinishPaste(MakeResultMap(
            "target_changed",
            "the captured window did not come back to the front"));
        return true;
      }
      break;
  }
  // A held hotkey Alt/Super would merge into the shortcut (Ctrl+Shift+Alt+V).
  if (AnyModifierHeld().value_or(false)) {
    if (elapsed < paste_delay_ms_ + kMaxModifierWaitMs) return false;
    g_warning("modifier still held after %d ms; shortcut sent anyway",
              kMaxModifierWaitMs);
  }
  if (!SendShortcut(LetterKeycode(GDK_KEY_v, KEY_V), paste_shift_,
                    paste_via_portal_)) {
    FinishPaste(MakeResultMap("permission_missing",
                              paste_via_portal_
                                  ? "portal input not connected"
                                  : "uinput unavailable — see checkCapability"));
    return true;
  }
  // The main loop has not run since the shortcut, so the target's read is
  // still ahead.
  receipt_->MarkKeystrokePosted();
  FinishPaste(MakeResultMap("success", ""));
  return true;
}

void DesktopPasteHost::FinishPaste(FlValue* result) {
  g_autoptr(FlValue) owned = result;
  if (paste_call_ == nullptr) return;
  fl_method_call_respond_success(paste_call_, owned, nullptr);
  g_object_unref(paste_call_);
  paste_call_ = nullptr;
}

// Mirrors PasteClipboard with Ctrl+C: the focused app copies its current
// selection ("edit selection by voice"). Dart snapshots/restores the
// clipboard around this call and detects "no selection" by the clipboard
// staying unchanged.
FlValue* DesktopPasteHost::CopySelection(int delay_ms, bool via_portal,
                                         bool shift) {
  if (delay_ms > 0) {
    std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
  }
  // A held hotkey Alt/Super would merge into the shortcut (Ctrl+Shift+Alt+<key>).
  AwaitModifierRelease();
  if (!SendShortcut(LetterKeycode(GDK_KEY_c, KEY_C), shift, via_portal)) {
    return MakeResultMap("permission_missing", via_portal
                             ? "portal input not connected"
                             : "uinput unavailable — see checkCapability");
  }
  return MakeResultMap("success", "");
}

// Mirrors the Windows bridge: route through clipboard+paste instead of
// per-character key codes (see class comment), backing up and restoring the
// caller's prior clipboard content around it via GTK's synchronous clipboard
// API.
FlValue* DesktopPasteHost::TypeText(const std::string& text, int delay_ms,
                                    bool via_portal, bool shift) {
  // Not implemented on the portal path yet: Dart gets "unavailable" and must
  // not treat it as a paste. Nothing is written to the clipboard here.
  if (via_portal) {
    return MakeResultMap("unavailable",
                         "typeText is not implemented for the portal input path");
  }
  if (delay_ms > 0) {
    std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
  }

  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  gchar* previous = gtk_clipboard_wait_for_text(clipboard);

  if (!SetClipboardTextHidden(clipboard, text)) {
    g_warning("history-excluded clipboard write failed; plain write used");
    gtk_clipboard_set_text(clipboard, text.c_str(), -1);
  }

  if (!SendPasteShortcut(shift)) {
    if (previous) {
      RestorePreviousClipboard(clipboard, previous);
      g_free(previous);
    } else {
      gtk_clipboard_clear(clipboard);
    }
    return MakeResultMap("permission_missing",
                         "uinput unavailable — see checkCapability");
  }

  std::this_thread::sleep_for(std::chrono::milliseconds(80));

  // Restore only while the clipboard still holds the text written above. A
  // copy the user made in the meantime stays (ticket, 9.9).
  gchar* current = gtk_clipboard_wait_for_text(clipboard);
  const bool unchanged = current != nullptr && text == current;
  g_free(current);
  if (!unchanged) {
    g_free(previous);
    return MakeResultMap("success", "");
  }

  if (previous) {
    RestorePreviousClipboard(clipboard, previous);
    g_free(previous);
  } else {
    gtk_clipboard_clear(clipboard);
  }
  return MakeResultMap("success", "");
}

// Onboarding "prove Auto-Paste works" probe — mirrors DiagnosticPaste on
// Windows/macOS. Uinput has no "no frontmost window" failure mode (there is
// no window concept at all), so the only outcomes are success/failure/the
// unsupported status checkCapability would also report.
FlValue* DesktopPasteHost::DiagnosticPaste(const std::string& demo_text) {
  if (!EnsureUinputDevice()) {
    return MakeResultMap("unsupported", "uinput unavailable — see checkCapability");
  }

  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  gchar* previous = gtk_clipboard_wait_for_text(clipboard);

  gtk_clipboard_set_text(clipboard, demo_text.c_str(), -1);

  const bool sent = SendPasteShortcut();
  std::this_thread::sleep_for(std::chrono::milliseconds(80));

  if (previous) {
    gtk_clipboard_set_text(clipboard, previous, -1);
    g_free(previous);
  } else {
    gtk_clipboard_clear(clipboard);
  }

  if (!sent) {
    return MakeResultMap("failure", "uinput_write_failed");
  }
  return MakeResultMap("success", "");
}
