#include "keyboard_monitor_host.h"

#include "autorepeat_filter.h"

#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>
#include <glib-unix.h>

#include <cstring>

namespace {

constexpr char kChannelName[] = "com.whispaste.keyboard_monitor";

// A release followed by a press of the same keycode within this window is
// X11 autorepeat (non-detectable mode emits release/press pairs back to back),
// not the user letting go. Real re-presses are far slower than this.
constexpr guint kAutorepeatFilterMs = 30;

constexpr char kPortalBusName[] = "org.freedesktop.portal.Desktop";
constexpr char kPortalObjectPath[] = "/org/freedesktop/portal/desktop";
constexpr char kGlobalShortcutsIface[] = "org.freedesktop.portal.GlobalShortcuts";
constexpr char kRequestIface[] = "org.freedesktop.portal.Request";
constexpr char kShortcutId[] = "whispaste-push-to-talk";

// D-Bus calls must never stall the hotkey path for long; the portal answers in
// milliseconds when it exists at all.
constexpr int kDbusTimeoutMs = 3000;

bool IsWaylandSession() {
  const gchar* type = g_getenv("XDG_SESSION_TYPE");
  if (type != nullptr && g_ascii_strcasecmp(type, "wayland") == 0) return true;
  const gchar* display = g_getenv("WAYLAND_DISPLAY");
  return display != nullptr && display[0] != '\0';
}

std::string GetString(FlValue* map, const char* key) {
  if (!map || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return {};
  FlValue* v = fl_value_lookup_string(map, key);
  if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) return {};
  return fl_value_get_string(v);
}

bool IsCancelled(GError* error) {
  return error != nullptr &&
         g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED);
}

// Answers a pending `start` call. Must run for every probe — including a
// cancelled one — or Dart's hotkey registration would await it forever.
void RespondStart(FlMethodCall* method_call, bool x11, bool portal) {
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "x11", fl_value_new_bool(x11));
  fl_value_set_string_take(result, "portal", fl_value_new_bool(portal));
  fl_method_call_respond_success(method_call, result, nullptr);
}

}  // namespace

KeyboardMonitorHost::KeyboardMonitorHost(FlBinaryMessenger* main_messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(main_messenger, kChannelName,
                                   FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this,
                                            nullptr);
  cancellable_ = g_cancellable_new();
}

KeyboardMonitorHost::~KeyboardMonitorHost() { Destroy(); }

void KeyboardMonitorHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;

  Stop();
  CloseX11();
  if (cancellable_) {
    g_cancellable_cancel(cancellable_);
    g_clear_object(&cancellable_);
  }
  g_clear_object(&bus_);

  if (channel_) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
    g_object_unref(channel_);
    channel_ = nullptr;
  }
}

// static
void KeyboardMonitorHost::OnMethodCall(FlMethodChannel* /*channel*/,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  static_cast<KeyboardMonitorHost*>(user_data)->HandleMethodCall(method_call);
}

void KeyboardMonitorHost::HandleMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);

  if (destroyed_) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }

  if (strcmp(method, "start") == 0) {
    // Replies itself — possibly asynchronously, after the portal probe.
    Start(method_call,
          GetString(fl_method_call_get_args(method_call), "trigger"));
    return;
  }

  if (strcmp(method, "armRelease") == 0) {
    ArmRelease();
  } else if (strcmp(method, "stop") == 0) {
    Stop();
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }
  fl_method_call_respond_success(method_call, nullptr, nullptr);
}

void KeyboardMonitorHost::Start(FlMethodCall* method_call,
                                const std::string& trigger) {
  Stop();
  trigger_ = trigger;

  // X11 grabs + raw events only cover the whole desktop in an X11 session;
  // under XWayland they would silently miss every native Wayland window.
  if (IsWaylandSession()) {
    ProbePortal(method_call);
    return;
  }

  x11_active_ = EnsureXi2();
  RespondStart(method_call, x11_active_, false);
}

void KeyboardMonitorHost::Stop() {
  generation_++;
  if (cancellable_) {
    g_cancellable_cancel(cancellable_);
    g_object_unref(cancellable_);
    cancellable_ = destroyed_ ? nullptr : g_cancellable_new();
  }
  CancelPendingRelease();
  watched_keycode_ = 0;
  x11_active_ = false;
  ClosePortalSession();
}

void KeyboardMonitorHost::SendToDart(const char* method, FlValue* args) {
  if (destroyed_ || channel_ == nullptr) return;
  fl_method_channel_invoke_method(channel_, method, args, nullptr, nullptr,
                                  nullptr);
}

void KeyboardMonitorHost::SendCapabilities() {
  g_autoptr(FlValue) caps = fl_value_new_map();
  fl_value_set_string_take(caps, "x11", fl_value_new_bool(x11_active_));
  fl_value_set_string_take(caps, "portal", fl_value_new_bool(portal_active_));
  SendToDart("onCapabilities", caps);
}

// ── X11 / XInput2 ───────────────────────────────────────────────────────────

bool KeyboardMonitorHost::EnsureXi2() {
  if (x_display_ != nullptr) return true;

  // A private connection: GDK's display queue must not see (or eat) the raw
  // events, and polling our own fd keeps this independent of GTK's loop.
  Display* display = XOpenDisplay(nullptr);
  if (display == nullptr) return false;

  int event_base = 0;
  int error_base = 0;
  int opcode = 0;
  if (!XQueryExtension(display, "XInputExtension", &opcode, &event_base,
                       &error_base)) {
    XCloseDisplay(display);
    return false;
  }
  // 2.1+ delivers raw events even while another client (the hotkey grab)
  // holds a grab; 2.0 would go silent exactly when it matters.
  int major = 2;
  int minor = 2;
  if (XIQueryVersion(display, &major, &minor) != Success ||
      (major == 2 && minor < 1)) {
    XCloseDisplay(display);
    return false;
  }

  unsigned char mask_bits[XIMaskLen(XI_LASTEVENT)] = {};
  XIEventMask mask;
  mask.deviceid = XIAllMasterDevices;
  mask.mask_len = sizeof(mask_bits);
  mask.mask = mask_bits;
  XISetMask(mask_bits, XI_RawKeyPress);
  XISetMask(mask_bits, XI_RawKeyRelease);
  XISelectEvents(display, DefaultRootWindow(display), &mask, 1);
  XFlush(display);

  x_display_ = display;
  xi_opcode_ = opcode;
  x_watch_id_ = g_unix_fd_add(ConnectionNumber(display), G_IO_IN,
                              OnX11Readable, this);
  return true;
}

void KeyboardMonitorHost::CloseX11() {
  if (x_watch_id_ != 0) {
    g_source_remove(x_watch_id_);
    x_watch_id_ = 0;
  }
  if (x_display_ != nullptr) {
    XCloseDisplay(x_display_);
    x_display_ = nullptr;
  }
}

void KeyboardMonitorHost::ArmRelease() {
  // The portal reports its own release (Deactivated); the X11 path has none
  // without this snapshot.
  if (portal_bound_ || !x11_active_ || x_display_ == nullptr) return;

  char keys[32] = {};
  XQueryKeymap(x_display_, keys);

  XModifierKeymap* modmap = XGetModifierMapping(x_display_);
  auto is_modifier = [modmap](unsigned int keycode) {
    if (modmap == nullptr) return false;
    const int count = 8 * modmap->max_keypermod;
    for (int i = 0; i < count; ++i) {
      if (modmap->modifiermap[i] == keycode) return true;
    }
    return false;
  };

  unsigned int held = 0;
  for (unsigned int keycode = 8; keycode < 256 && held == 0; ++keycode) {
    const bool down = (keys[keycode / 8] >> (keycode % 8)) & 1;
    if (down && !is_modifier(keycode)) held = keycode;
  }
  if (modmap != nullptr) XFreeModifiermap(modmap);

  CancelPendingRelease();
  watched_keycode_ = held;
  if (held == 0) {
    // Released before Dart's arm arrived (a quick tap): report it now rather
    // than leaving the recording stuck in "held".
    SendToDart("onKeyUp");
  }
  // Replies above may have queued events without the fd turning readable.
  DrainX11Events();
}

// static
gboolean KeyboardMonitorHost::OnX11Readable(gint /*fd*/,
                                            GIOCondition /*condition*/,
                                            gpointer user_data) {
  static_cast<KeyboardMonitorHost*>(user_data)->DrainX11Events();
  return G_SOURCE_CONTINUE;
}

void KeyboardMonitorHost::DrainX11Events() {
  if (x_display_ == nullptr) return;
  while (XPending(x_display_) > 0) {
    XEvent event;
    XNextEvent(x_display_, &event);
    XGenericEventCookie* cookie = &event.xcookie;
    if (cookie->type != GenericEvent || cookie->extension != xi_opcode_ ||
        !XGetEventData(x_display_, cookie)) {
      continue;
    }
    if (cookie->evtype == XI_RawKeyRelease ||
        cookie->evtype == XI_RawKeyPress) {
      const auto* raw = static_cast<XIRawEvent*>(cookie->data);
      switch (ClassifyRawKeyEvent(watched_keycode_,
                                  static_cast<unsigned int>(raw->detail),
                                  cookie->evtype == XI_RawKeyRelease)) {
        case RawKeyAction::kScheduleRelease:
          ScheduleRelease();
          break;
        case RawKeyAction::kCancelPendingRelease:
          // Autorepeat: the release just seen was the first half of a pair.
          CancelPendingRelease();
          break;
        case RawKeyAction::kIgnore:
          break;
      }
    }
    XFreeEventData(x_display_, cookie);
  }
}

void KeyboardMonitorHost::ScheduleRelease() {
  CancelPendingRelease();
  release_timer_id_ =
      g_timeout_add(kAutorepeatFilterMs, OnReleaseConfirmed, this);
}

void KeyboardMonitorHost::CancelPendingRelease() {
  if (release_timer_id_ != 0) {
    g_source_remove(release_timer_id_);
    release_timer_id_ = 0;
  }
}

// static
gboolean KeyboardMonitorHost::OnReleaseConfirmed(gpointer user_data) {
  auto* self = static_cast<KeyboardMonitorHost*>(user_data);
  self->release_timer_id_ = 0;
  self->watched_keycode_ = 0;
  self->SendToDart("onKeyUp");
  return G_SOURCE_REMOVE;
}

// ── GlobalShortcuts portal ──────────────────────────────────────────────────

void KeyboardMonitorHost::ProbePortal(FlMethodCall* method_call) {
  auto* ctx = new AsyncCall{this, generation_,
                            FL_METHOD_CALL(g_object_ref(method_call))};
  if (bus_ == nullptr) {
    g_autoptr(GError) error = nullptr;
    bus_ = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
    if (bus_ == nullptr) {
      g_warning("KeyboardMonitorHost: no session bus: %s",
                error ? error->message : "?");
      FinishProbe(ctx, false);
      return;
    }
  }
  // Unsandboxed apps must tell the portal who they are before any other
  // portal call (xdg-desktop-portal >= 1.19); older portals lack the
  // interface, which is fine — the reply is ignored either way.
  g_dbus_connection_call(
      bus_, kPortalBusName, kPortalObjectPath,
      "org.freedesktop.host.portal.Registry", "Register",
      g_variant_new("(sa{sv})", APPLICATION_ID, nullptr), nullptr,
      G_DBUS_CALL_FLAGS_NONE, kDbusTimeoutMs, cancellable_, OnRegisterDone,
      ctx);
}

// static
void KeyboardMonitorHost::OnRegisterDone(GObject* source, GAsyncResult* result,
                                         gpointer user_data) {
  auto* ctx = static_cast<AsyncCall*>(user_data);
  g_autoptr(GError) error = nullptr;
  GVariant* reply =
      g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error);
  if (reply != nullptr) g_variant_unref(reply);
  if (IsCancelled(error)) {
    // Superseded by stop/start or shutdown — the host may be gone, so answer
    // without touching it.
    RespondStart(ctx->method_call, false, false);
    g_object_unref(ctx->method_call);
    delete ctx;
    return;
  }
  KeyboardMonitorHost* self = ctx->host;
  g_dbus_connection_call(
      self->bus_, kPortalBusName, kPortalObjectPath,
      "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", kGlobalShortcutsIface, "version"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, kDbusTimeoutMs,
      self->cancellable_, OnVersionDone, ctx);
}

// static
void KeyboardMonitorHost::OnVersionDone(GObject* source, GAsyncResult* result,
                                        gpointer user_data) {
  auto* ctx = static_cast<AsyncCall*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply =
      g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error);
  if (IsCancelled(error)) {
    // Superseded by stop/start or shutdown — the host may be gone, so answer
    // without touching it.
    RespondStart(ctx->method_call, false, false);
    g_object_unref(ctx->method_call);
    delete ctx;
    return;
  }
  if (reply == nullptr) {
    g_message("KeyboardMonitorHost: GlobalShortcuts portal unavailable: %s",
              error ? error->message : "?");
  }
  ctx->host->FinishProbe(ctx, reply != nullptr);
}

void KeyboardMonitorHost::FinishProbe(AsyncCall* ctx, bool portal_available) {
  const bool current = !destroyed_ && ctx->generation == generation_;
  if (current) portal_active_ = portal_available;

  RespondStart(ctx->method_call, false, current && portal_available);
  g_object_unref(ctx->method_call);
  delete ctx;

  if (current && portal_available) CreatePortalSession();
}

std::string KeyboardMonitorHost::NextToken() {
  return "whispaste_" + std::to_string(++token_counter_);
}

std::string KeyboardMonitorHost::RequestPath(const std::string& token) const {
  // Documented by xdg-desktop-portal: the sender's unique name without the
  // leading ':' and with '.' replaced by '_'.
  std::string sender = g_dbus_connection_get_unique_name(bus_);
  if (!sender.empty() && sender[0] == ':') sender.erase(0, 1);
  for (char& c : sender) {
    if (c == '.') c = '_';
  }
  return std::string(kPortalObjectPath) + "/request/" + sender + "/" + token;
}

void KeyboardMonitorHost::CallPortalRequest(const char* method,
                                            GVariant* params,
                                            const std::string& token,
                                            ResponseHandler handler) {
  ClearPendingRequest();
  // Subscribe before calling, so a fast Response cannot be missed.
  request_handler_ = handler;
  request_sub_id_ = g_dbus_connection_signal_subscribe(
      bus_, kPortalBusName, kRequestIface, "Response",
      RequestPath(token).c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      OnRequestResponse, this, nullptr);
  auto* ctx = new AsyncCall{this, generation_, nullptr};
  g_dbus_connection_call(bus_, kPortalBusName, kPortalObjectPath,
                         kGlobalShortcutsIface, method, params,
                         G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE,
                         kDbusTimeoutMs, cancellable_, OnPortalCallDone, ctx);
}

// static
void KeyboardMonitorHost::OnPortalCallDone(GObject* source,
                                           GAsyncResult* result,
                                           gpointer user_data) {
  auto* ctx = static_cast<AsyncCall*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply =
      g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error);
  KeyboardMonitorHost* self = ctx->host;
  const guint generation = ctx->generation;
  delete ctx;
  if (IsCancelled(error) || generation != self->generation_) return;
  if (reply == nullptr) {
    self->PortalFailed(error ? error->message : "call failed");
  }
}

// static
void KeyboardMonitorHost::OnRequestResponse(
    GDBusConnection* /*connection*/, const gchar* /*sender*/,
    const gchar* /*object_path*/, const gchar* /*interface_name*/,
    const gchar* /*signal_name*/, GVariant* parameters, gpointer user_data) {
  auto* self = static_cast<KeyboardMonitorHost*>(user_data);
  ResponseHandler handler = self->request_handler_;
  self->ClearPendingRequest();
  if (handler == nullptr ||
      !g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ua{sv})"))) {
    return;
  }
  guint32 response = 2;
  g_autoptr(GVariant) results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &response, &results);
  (self->*handler)(response, results);
}

void KeyboardMonitorHost::ClearPendingRequest() {
  if (request_sub_id_ != 0 && bus_ != nullptr) {
    g_dbus_connection_signal_unsubscribe(bus_, request_sub_id_);
  }
  request_sub_id_ = 0;
  request_handler_ = nullptr;
}

void KeyboardMonitorHost::CreatePortalSession() {
  activated_sub_id_ = g_dbus_connection_signal_subscribe(
      bus_, kPortalBusName, kGlobalShortcutsIface, "Activated",
      kPortalObjectPath, nullptr, G_DBUS_SIGNAL_FLAGS_NONE, OnPortalSignal,
      this, nullptr);
  deactivated_sub_id_ = g_dbus_connection_signal_subscribe(
      bus_, kPortalBusName, kGlobalShortcutsIface, "Deactivated",
      kPortalObjectPath, nullptr, G_DBUS_SIGNAL_FLAGS_NONE, OnPortalSignal,
      this, nullptr);

  const std::string token = NextToken();
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  g_variant_builder_add(&options, "{sv}", "session_handle_token",
                        g_variant_new_string(NextToken().c_str()));
  CallPortalRequest("CreateSession", g_variant_new("(a{sv})", &options),
                    token, &KeyboardMonitorHost::OnSessionCreated);
}

void KeyboardMonitorHost::OnSessionCreated(guint32 response,
                                           GVariant* results) {
  // Spec says `s`, some portal versions send `o`; g_variant_get_string reads
  // both.
  g_autoptr(GVariant) handle =
      response == 0 && results != nullptr
          ? g_variant_lookup_value(results, "session_handle", nullptr)
          : nullptr;
  if (handle == nullptr ||
      !(g_variant_is_of_type(handle, G_VARIANT_TYPE_STRING) ||
        g_variant_is_of_type(handle, G_VARIANT_TYPE_OBJECT_PATH))) {
    PortalFailed("CreateSession declined");
    return;
  }
  session_handle_ = g_variant_get_string(handle, nullptr);

  GVariantBuilder props;
  g_variant_builder_init(&props, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&props, "{sv}", "description",
                        g_variant_new_string("Push-to-talk dictation"));
  if (!trigger_.empty()) {
    g_variant_builder_add(&props, "{sv}", "preferred_trigger",
                          g_variant_new_string(trigger_.c_str()));
  }
  GVariantBuilder shortcuts;
  g_variant_builder_init(&shortcuts, G_VARIANT_TYPE("a(sa{sv})"));
  g_variant_builder_add(&shortcuts, "(sa{sv})", kShortcutId, &props);

  const std::string token = NextToken();
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  CallPortalRequest("BindShortcuts",
                    g_variant_new("(oa(sa{sv})sa{sv})", session_handle_.c_str(),
                                  &shortcuts, "", &options),
                    token, &KeyboardMonitorHost::OnShortcutsBound);
}

void KeyboardMonitorHost::OnShortcutsBound(guint32 response,
                                           GVariant* /*results*/) {
  if (response != 0) {
    PortalFailed("BindShortcuts declined");
    return;
  }
  portal_bound_ = true;
  g_message("KeyboardMonitorHost: push-to-talk bound via GlobalShortcuts");
}

// static
void KeyboardMonitorHost::OnPortalSignal(
    GDBusConnection* /*connection*/, const gchar* /*sender*/,
    const gchar* /*object_path*/, const gchar* /*interface_name*/,
    const gchar* signal_name, GVariant* parameters, gpointer user_data) {
  auto* self = static_cast<KeyboardMonitorHost*>(user_data);
  if (!self->portal_bound_ ||
      !g_variant_is_of_type(parameters, G_VARIANT_TYPE("(osta{sv})"))) {
    return;
  }
  const gchar* session = nullptr;
  const gchar* shortcut = nullptr;
  g_variant_get(parameters, "(&o&sta{sv})", &session, &shortcut, nullptr,
                nullptr);
  if (self->session_handle_ != session || strcmp(shortcut, kShortcutId) != 0) {
    return;
  }
  self->SendToDart(strcmp(signal_name, "Activated") == 0 ? "onKeyDown"
                                                          : "onKeyUp");
}

void KeyboardMonitorHost::PortalFailed(const char* why) {
  g_message("KeyboardMonitorHost: GlobalShortcuts binding failed (%s)", why);
  ClosePortalSession();
  SendCapabilities();
}

void KeyboardMonitorHost::ClosePortalSession() {
  ClearPendingRequest();
  if (bus_ != nullptr) {
    if (activated_sub_id_ != 0) {
      g_dbus_connection_signal_unsubscribe(bus_, activated_sub_id_);
    }
    if (deactivated_sub_id_ != 0) {
      g_dbus_connection_signal_unsubscribe(bus_, deactivated_sub_id_);
    }
    if (!session_handle_.empty()) {
      // Fire-and-forget: closing releases the binding in the compositor.
      g_dbus_connection_call(bus_, kPortalBusName, session_handle_.c_str(),
                             "org.freedesktop.portal.Session", "Close",
                             nullptr, nullptr, G_DBUS_CALL_FLAGS_NONE,
                             kDbusTimeoutMs, nullptr, nullptr, nullptr);
    }
  }
  activated_sub_id_ = 0;
  deactivated_sub_id_ = 0;
  session_handle_.clear();
  portal_bound_ = false;
  portal_active_ = false;
}
