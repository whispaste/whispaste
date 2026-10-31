#include "portal_remote_desktop.h"

#include <unistd.h>

#include <string>
#include <utility>

#include "eis_keyboard_sender.h"

namespace {

constexpr char kPortalName[] = "org.freedesktop.portal.Desktop";
constexpr char kPortalPath[] = "/org/freedesktop/portal/desktop";
constexpr char kRemoteDesktopIface[] = "org.freedesktop.portal.RemoteDesktop";
constexpr char kRequestIface[] = "org.freedesktop.portal.Request";
constexpr char kSessionIface[] = "org.freedesktop.portal.Session";
// RemoteDesktop device types (KEYBOARD = 1) and persist_mode (2: until
// revoked, so the restore token keeps working across app starts).
constexpr uint32_t kDeviceKeyboard = 1;
constexpr uint32_t kPersistUntilRevoked = 2;
// The consent dialog waits for a human, so this is generous.
constexpr guint kConnectTimeoutSeconds = 180;
constexpr int kVersionTimeoutMs = 2000;
constexpr int kEisReadyTimeoutMs = 3000;

uint32_t NextCounter() {
  static uint32_t counter = 0;
  return ++counter;
}

// The unique bus name without ':' and with '.' as '_', as the portal builds
// request handle paths from it.
std::string SenderToken(GDBusConnection* bus) {
  const char* unique = g_dbus_connection_get_unique_name(bus);
  std::string name = unique ? unique : "";
  if (!name.empty() && name[0] == ':') name.erase(0, 1);
  for (char& c : name) {
    if (c == '.') c = '_';
  }
  return name;
}

// RemoteDesktop interface version, or 0 when the portal does not answer.
uint32_t RemoteDesktopVersion(GDBusConnection* bus) {
  GError* error = nullptr;
  GVariant* reply = g_dbus_connection_call_sync(
      bus, kPortalName, kPortalPath, "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", kRemoteDesktopIface, "version"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, kVersionTimeoutMs,
      nullptr, &error);
  if (reply == nullptr) {
    g_clear_error(&error);
    return 0;
  }
  GVariant* value = nullptr;
  g_variant_get(reply, "(v)", &value);
  uint32_t version = 0;
  if (value != nullptr && g_variant_is_of_type(value, G_VARIANT_TYPE_UINT32)) {
    version = g_variant_get_uint32(value);
  }
  if (value != nullptr) g_variant_unref(value);
  g_variant_unref(reply);
  return version;
}

// Lookups in a Response's a{sv} results. Missing keys give the fallback.
std::string StringResult(GVariant* results, const char* key) {
  if (results == nullptr) return {};
  gchar* text = nullptr;
  std::string out;
  if (g_variant_lookup(results, key, "s", &text)) {
    out = text;
    g_free(text);
  }
  return out;
}

uint32_t UintResult(GVariant* results, const char* key) {
  if (results == nullptr) return 0;
  guint32 value = 0;
  if (g_variant_lookup(results, key, "u", &value)) return value;
  return 0;
}

GVariant* EmptyOptions() {
  return g_variant_new_array(G_VARIANT_TYPE("{sv}"), nullptr, 0);
}

// a{sv} with handle_token, the common options of every portal request.
GVariantBuilder* BeginOptions(GVariantBuilder* builder, const std::string& token) {
  g_variant_builder_init(builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(builder, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  return builder;
}

}  // namespace

// One Connect() attempt: a chain of portal requests. Lives on the heap until
// it is finished and no GDBus call still refers to it (see FinishFlow).
struct PortalRemoteDesktop::Flow {
  using Handler = std::function<void(Flow*, uint32_t code, GVariant* results)>;

  PortalRemoteDesktop* owner = nullptr;
  GDBusConnection* bus = nullptr;  // owned by the owner
  PortalRemoteDesktop::ConnectCallback done;
  std::string restore_token_in;
  std::string restore_token_out;
  std::string session_handle;
  Handler on_response;
  guint subscription = 0;
  guint timeout = 0;
  GCancellable* cancellable = nullptr;
  bool call_pending = false;
  bool finished = false;

  ~Flow() {
    if (cancellable != nullptr) g_object_unref(cancellable);
  }

  void Finish(ConnectResult result) { owner->FinishFlow(this, std::move(result)); }

  // Subscribes to the Response of one request (before the call, so a fast
  // answer is not lost), then calls [method] with the args [make_args] builds.
  void Request(const char* method,
               const std::function<GVariant*(const std::string& token)>& make_args,
               Handler handler);

  void StepCreateSession();
  void StepSelectDevices();
  void StepStart();
  void StepConnectEis();

  static void OnResponseSignal(GDBusConnection* connection,
                               const gchar* sender_name,
                               const gchar* object_path,
                               const gchar* interface_name,
                               const gchar* signal_name, GVariant* params,
                               gpointer user_data);
  static void OnRequestReturned(GObject* source, GAsyncResult* res,
                                gpointer user_data);
  static void OnConnectEisReturned(GObject* source, GAsyncResult* res,
                                   gpointer user_data);
  static gboolean OnTimeout(gpointer user_data);
};

void PortalRemoteDesktop::Flow::Request(
    const char* method,
    const std::function<GVariant*(const std::string& token)>& make_args,
    Handler handler) {
  const std::string token = "whispaste" + std::to_string(NextCounter());
  const std::string handle = std::string(kPortalPath) + "/request/" +
                             SenderToken(bus) + "/" + token;
  on_response = std::move(handler);
  subscription = g_dbus_connection_signal_subscribe(
      bus, kPortalName, kRequestIface, "Response", handle.c_str(), nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, &Flow::OnResponseSignal, this, nullptr);
  call_pending = true;
  g_dbus_connection_call(bus, kPortalName, kPortalPath, kRemoteDesktopIface,
                         method, make_args(token), G_VARIANT_TYPE("(o)"),
                         G_DBUS_CALL_FLAGS_NONE, -1, cancellable,
                         &Flow::OnRequestReturned, this);
}

// static
void PortalRemoteDesktop::Flow::OnResponseSignal(
    GDBusConnection* /*connection*/, const gchar* /*sender_name*/,
    const gchar* /*object_path*/, const gchar* /*interface_name*/,
    const gchar* /*signal_name*/, GVariant* params, gpointer user_data) {
  Flow* flow = static_cast<Flow*>(user_data);
  if (flow->subscription != 0) {
    g_dbus_connection_signal_unsubscribe(flow->bus, flow->subscription);
    flow->subscription = 0;
  }
  guint32 code = 2;
  GVariant* results = nullptr;
  g_variant_get(params, "(u@a{sv})", &code, &results);
  if (!flow->finished && flow->on_response) {
    // The handler may finish the flow, so nothing of it is touched afterwards.
    Handler handler = std::move(flow->on_response);
    flow->on_response = nullptr;
    handler(flow, code, results);
  }
  if (results != nullptr) g_variant_unref(results);
}

// static
void PortalRemoteDesktop::Flow::OnRequestReturned(GObject* source,
                                                  GAsyncResult* res,
                                                  gpointer user_data) {
  Flow* flow = static_cast<Flow*>(user_data);
  flow->call_pending = false;
  GError* error = nullptr;
  GVariant* reply =
      g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), res, &error);
  if (flow->finished) {
    // Finish() ran while the call was out and could not free the flow then.
    if (reply != nullptr) g_variant_unref(reply);
    g_clear_error(&error);
    delete flow;
    return;
  }
  if (reply == nullptr) {
    g_message("portal input: request failed: %s", error->message);
    g_clear_error(&error);
    flow->Finish({ConnectOutcome::kFailed, "", "request call failed"});
    return;
  }
  // The reply names the request handle; it is the one we subscribed to.
  g_variant_unref(reply);
}

// static
gboolean PortalRemoteDesktop::Flow::OnTimeout(gpointer user_data) {
  Flow* flow = static_cast<Flow*>(user_data);
  flow->timeout = 0;
  flow->Finish({ConnectOutcome::kFailed, "", "consent timed out"});
  return G_SOURCE_REMOVE;
}

void PortalRemoteDesktop::Flow::StepCreateSession() {
  const std::string session_token =
      "whispaste_session" + std::to_string(NextCounter());
  Request(
      "CreateSession",
      [session_token](const std::string& token) {
        GVariantBuilder builder;
        BeginOptions(&builder, token);
        g_variant_builder_add(&builder, "{sv}", "session_handle_token",
                              g_variant_new_string(session_token.c_str()));
        return g_variant_new("(@a{sv})", g_variant_builder_end(&builder));
      },
      [](Flow* flow, uint32_t code, GVariant* results) {
        if (code != 0) {
          flow->Finish({code == 1 ? ConnectOutcome::kCancelled : ConnectOutcome::kFailed, "",
                        "CreateSession response " + std::to_string(code)});
          return;
        }
        flow->session_handle = StringResult(results, "session_handle");
        if (flow->session_handle.empty()) {
          flow->Finish({ConnectOutcome::kFailed, "", "no session handle"});
          return;
        }
        flow->StepSelectDevices();
      });
}

void PortalRemoteDesktop::Flow::StepSelectDevices() {
  const std::string session = session_handle;
  const std::string restore = restore_token_in;
  Request(
      "SelectDevices",
      [session, restore](const std::string& token) {
        GVariantBuilder builder;
        BeginOptions(&builder, token);
        g_variant_builder_add(&builder, "{sv}", "types",
                              g_variant_new_uint32(kDeviceKeyboard));
        g_variant_builder_add(&builder, "{sv}", "persist_mode",
                              g_variant_new_uint32(kPersistUntilRevoked));
        if (!restore.empty()) {
          g_variant_builder_add(&builder, "{sv}", "restore_token",
                                g_variant_new_string(restore.c_str()));
        }
        return g_variant_new("(o@a{sv})", session.c_str(),
                             g_variant_builder_end(&builder));
      },
      [](Flow* flow, uint32_t code, GVariant* /*results*/) {
        if (code != 0) {
          flow->Finish({code == 1 ? ConnectOutcome::kCancelled : ConnectOutcome::kFailed, "",
                        "SelectDevices response " + std::to_string(code)});
          return;
        }
        flow->StepStart();
      });
}

void PortalRemoteDesktop::Flow::StepStart() {
  const std::string session = session_handle;
  Request(
      "Start",
      [session](const std::string& token) {
        GVariantBuilder builder;
        BeginOptions(&builder, token);
        // An empty parent window: the dialog is not attached to a toplevel.
        return g_variant_new("(os@a{sv})", session.c_str(), "",
                             g_variant_builder_end(&builder));
      },
      [](Flow* flow, uint32_t code, GVariant* results) {
        if (code != 0) {
          // 1: the user closed the dialog, 2: the portal refused.
          flow->Finish({code == 1 ? ConnectOutcome::kCancelled : ConnectOutcome::kFailed, "",
                        "Start response " + std::to_string(code)});
          return;
        }
        const std::string token = StringResult(results, "restore_token");
        flow->restore_token_out =
            token.empty() ? flow->restore_token_in : token;
        if ((UintResult(results, "devices") & kDeviceKeyboard) == 0 &&
            UintResult(results, "devices") != 0) {
          flow->Finish({ConnectOutcome::kFailed, "", "keyboard not granted"});
          return;
        }
        flow->StepConnectEis();
      });
}

void PortalRemoteDesktop::Flow::StepConnectEis() {
  call_pending = true;
  g_dbus_connection_call_with_unix_fd_list(
      bus, kPortalName, kPortalPath, kRemoteDesktopIface, "ConnectToEIS",
      g_variant_new("(o@a{sv})", session_handle.c_str(), EmptyOptions()),
      G_VARIANT_TYPE("(h)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, cancellable,
      &Flow::OnConnectEisReturned, this);
}

// static
void PortalRemoteDesktop::Flow::OnConnectEisReturned(GObject* source,
                                                     GAsyncResult* res,
                                                     gpointer user_data) {
  Flow* flow = static_cast<Flow*>(user_data);
  flow->call_pending = false;
  GUnixFDList* fd_list = nullptr;
  GError* error = nullptr;
  GVariant* reply = g_dbus_connection_call_with_unix_fd_list_finish(
      G_DBUS_CONNECTION(source), &fd_list, res, &error);
  if (flow->finished) {
    if (reply != nullptr) g_variant_unref(reply);
    if (fd_list != nullptr) g_object_unref(fd_list);
    g_clear_error(&error);
    delete flow;
    return;
  }
  if (reply == nullptr) {
    g_message("portal input: ConnectToEIS failed: %s", error->message);
    g_clear_error(&error);
    if (fd_list != nullptr) g_object_unref(fd_list);
    flow->Finish({ConnectOutcome::kFailed, "", "ConnectToEIS call failed"});
    return;
  }
  gint32 index = -1;
  g_variant_get(reply, "(h)", &index);
  g_variant_unref(reply);
  int eis_fd = -1;
  if (fd_list != nullptr && index >= 0) {
    // The list owns its fds; the sender needs one of its own.
    const int listed = g_unix_fd_list_get(fd_list, index, nullptr);
    if (listed >= 0) eis_fd = dup(listed);
  }
  if (fd_list != nullptr) g_object_unref(fd_list);
  if (eis_fd < 0) {
    flow->Finish({ConnectOutcome::kFailed, "", "no EIS socket returned"});
    return;
  }

  PortalRemoteDesktop* owner = flow->owner;
  owner->sender_ = std::make_unique<EisKeyboardSender>(eis_fd);
  if (!owner->sender_->WaitUntilReady(kEisReadyTimeoutMs)) {
    owner->sender_.reset();
    flow->Finish({ConnectOutcome::kFailed, "", "keyboard device not ready"});
    return;
  }
  owner->session_handle_ = flow->session_handle;
  flow->Finish({ConnectOutcome::kConnected, flow->restore_token_out, ""});
}

PortalRemoteDesktop::PortalRemoteDesktop() = default;

PortalRemoteDesktop::~PortalRemoteDesktop() {
  Disconnect();
  if (bus_ != nullptr) g_object_unref(bus_);
}

GDBusConnection* PortalRemoteDesktop::Bus() {
  if (bus_ == nullptr) {
    bus_ = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  }
  return bus_;
}

// static
bool PortalRemoteDesktop::IsAvailable() {
  if (!EisKeyboardSender::IsLibeiAvailable()) return false;
  GDBusConnection* bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (bus == nullptr) return false;
  const bool ok = RemoteDesktopVersion(bus) >= 2;
  g_object_unref(bus);
  return ok;
}

void PortalRemoteDesktop::Connect(const std::string& restore_token,
                                  ConnectCallback done) {
  if (flow_ != nullptr) {
    done({ConnectOutcome::kFailed, "", "connect already in progress"});
    return;
  }
  if (!EisKeyboardSender::IsLibeiAvailable()) {
    done({ConnectOutcome::kUnavailable, "", "libei is not available"});
    return;
  }
  GDBusConnection* bus = Bus();
  if (bus == nullptr) {
    done({ConnectOutcome::kUnavailable, "", "no session bus"});
    return;
  }
  if (RemoteDesktopVersion(bus) < 2) {
    done({ConnectOutcome::kUnavailable, "",
          "RemoteDesktop portal version 2 is not available"});
    return;
  }
  // A new connect replaces the old session.
  Disconnect();

  auto* flow = new Flow();
  flow->owner = this;
  flow->bus = bus;
  flow->done = std::move(done);
  flow->restore_token_in = restore_token;
  flow->cancellable = g_cancellable_new();
  flow_ = flow;
  flow->timeout = g_timeout_add_seconds(kConnectTimeoutSeconds,
                                        &Flow::OnTimeout, flow);
  flow->StepCreateSession();
}

void PortalRemoteDesktop::FinishFlow(Flow* flow, ConnectResult result) {
  if (flow->finished) return;
  flow->finished = true;
  if (flow->subscription != 0) {
    g_dbus_connection_signal_unsubscribe(flow->bus, flow->subscription);
    flow->subscription = 0;
  }
  if (flow->timeout != 0) {
    g_source_remove(flow->timeout);
    flow->timeout = 0;
  }
  flow->on_response = nullptr;
  if (result.status != ConnectOutcome::kConnected) {
    g_message("portal input: connect ended: %s", result.detail.c_str());
    // A session that was created but not connected is closed again.
    if (!flow->session_handle.empty()) {
      g_dbus_connection_call(flow->bus, kPortalName, flow->session_handle.c_str(),
                             kSessionIface, "Close", nullptr, nullptr,
                             G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr,
                             nullptr);
    }
  }
  if (flow_ == flow) flow_ = nullptr;
  if (flow->call_pending) {
    // A GDBus call still refers to the flow: cancel it, and its callback frees
    // the flow. The callback is not run for a cancelled request here.
    g_cancellable_cancel(flow->cancellable);
  }
  ConnectCallback done = std::move(flow->done);
  if (!flow->call_pending) delete flow;
  if (done) done(result);
}

void PortalRemoteDesktop::Disconnect() {
  if (flow_ != nullptr) {
    FinishFlow(flow_, {ConnectOutcome::kCancelled, "", "disconnected"});
  }
  sender_.reset();
  if (!session_handle_.empty() && bus_ != nullptr) {
    g_dbus_connection_call(bus_, kPortalName, session_handle_.c_str(),
                           kSessionIface, "Close", nullptr, nullptr,
                           G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr,
                           nullptr);
  }
  session_handle_.clear();
}

bool PortalRemoteDesktop::connected() const {
  return sender_ != nullptr && sender_->ready();
}

bool PortalRemoteDesktop::SendCtrlShortcut(uint32_t keycode, bool shift) {
  return sender_ != nullptr && sender_->SendCtrlShortcut(keycode, shift);
}
