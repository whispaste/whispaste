#include "desktop_paste_host.h"

#include <fcntl.h>
#include <gtk/gtk.h>
#include <linux/uinput.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <chrono>
#include <cstring>
#include <thread>

namespace {

constexpr char kChannelName[] = "com.whispaste.desktop_paste";

int GetInt(FlValue* map, const char* key, int fallback = 0) {
  if (!map || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return fallback;
  FlValue* v = fl_value_lookup_string(map, key);
  if (!v) return fallback;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) {
    return static_cast<int>(fl_value_get_int(v));
  }
  return fallback;
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

}  // namespace

DesktopPasteHost::DesktopPasteHost(FlBinaryMessenger* main_messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(main_messenger, kChannelName,
                                    FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this,
                                             nullptr);
}

DesktopPasteHost::~DesktopPasteHost() { Destroy(); }

void DesktopPasteHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;

  if (channel_) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                               nullptr);
    g_object_unref(channel_);
    channel_ = nullptr;
  }

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
    // No-op — see the class comment for why uinput has no target-window
    // concept. Always report success so callers don't treat this platform
    // as "no target ever available".
    response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));

  } else if (strcmp(method, "pasteClipboard") == 0) {
    const int delay_ms = GetInt(args, "delayMs", 0);
    g_autoptr(FlValue) result = PasteClipboard(delay_ms);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "typeText") == 0) {
    const std::string text = GetString(args, "text");
    const int delay_ms = GetInt(args, "delayMs", 0);
    g_autoptr(FlValue) result = TypeText(text, delay_ms);
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

bool DesktopPasteHost::EnsureUinputDevice() {
  if (uinput_fd_ >= 0) return true;

  int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
  if (fd < 0) return false;

  if (ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0 ||
      ioctl(fd, UI_SET_KEYBIT, KEY_LEFTCTRL) < 0 ||
      ioctl(fd, UI_SET_KEYBIT, KEY_V) < 0) {
    close(fd);
    return false;
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

bool DesktopPasteHost::SendPasteShortcut() {
  if (!EnsureUinputDevice()) return false;
  return EmitKey(uinput_fd_, KEY_LEFTCTRL, 1) &&
         EmitKey(uinput_fd_, KEY_V, 1) &&
         EmitKey(uinput_fd_, KEY_V, 0) &&
         EmitKey(uinput_fd_, KEY_LEFTCTRL, 0);
}

FlValue* DesktopPasteHost::CheckCapability() {
  if (!EnsureUinputDevice()) {
    const bool exists = access("/dev/uinput", F_OK) == 0;
    FlValue* map = MakeResultMap(
        exists ? "permission_missing" : "unsupported",
        exists ? "no write access to /dev/uinput — run the WhisPaste udev "
                  "setup step, or add this user to the 'input' group and "
                  "log out/in"
               : "/dev/uinput not present — uinput kernel module unavailable");
    fl_value_set_string_take(map, "canPrompt", fl_value_new_bool(FALSE));
    return map;
  }
  FlValue* map = MakeResultMap("ready", "");
  fl_value_set_string_take(map, "canPrompt", fl_value_new_bool(FALSE));
  return map;
}

FlValue* DesktopPasteHost::PasteClipboard(int delay_ms) {
  if (delay_ms > 0) {
    std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
  }
  if (!SendPasteShortcut()) {
    return MakeResultMap("permission_missing",
                         "uinput unavailable — see checkCapability");
  }
  return MakeResultMap("success", "");
}

// Mirrors the Windows bridge: route through clipboard+paste instead of
// per-character key codes (see class comment), backing up and restoring the
// caller's prior clipboard content around it via GTK's synchronous clipboard
// API.
FlValue* DesktopPasteHost::TypeText(const std::string& text, int delay_ms) {
  if (delay_ms > 0) {
    std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
  }

  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  gchar* previous = gtk_clipboard_wait_for_text(clipboard);

  gtk_clipboard_set_text(clipboard, text.c_str(), -1);

  if (!SendPasteShortcut()) {
    if (previous) {
      gtk_clipboard_set_text(clipboard, previous, -1);
      g_free(previous);
    } else {
      gtk_clipboard_clear(clipboard);
    }
    return MakeResultMap("permission_missing",
                         "uinput unavailable — see checkCapability");
  }

  std::this_thread::sleep_for(std::chrono::milliseconds(80));

  if (previous) {
    gtk_clipboard_set_text(clipboard, previous, -1);
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
