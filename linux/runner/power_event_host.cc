#include "power_event_host.h"

namespace {

constexpr char kChannelName[] = "com.whispaste.power";
constexpr char kLogindService[] = "org.freedesktop.login1";
constexpr char kLogindPath[] = "/org/freedesktop/login1";
constexpr char kLogindManager[] = "org.freedesktop.login1.Manager";

}  // namespace

PowerEventHost::PowerEventHost(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger, kChannelName,
                                   FL_METHOD_CODEC(codec));

  g_autoptr(GError) error = nullptr;
  bus_ = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &error);
  if (!bus_) {
    g_warning("Power events unavailable, no system bus: %s",
              error ? error->message : "unknown error");
    return;
  }
  subscription_id_ = g_dbus_connection_signal_subscribe(
      bus_, kLogindService, kLogindManager, "PrepareForSleep", kLogindPath,
      nullptr, G_DBUS_SIGNAL_FLAGS_NONE, &PowerEventHost::OnPrepareForSleep,
      this, nullptr);
}

PowerEventHost::~PowerEventHost() {
  if (bus_ && subscription_id_ != 0) {
    g_dbus_connection_signal_unsubscribe(bus_, subscription_id_);
  }
  g_clear_object(&bus_);
  g_clear_object(&channel_);
}

void PowerEventHost::OnPrepareForSleep(GDBusConnection* /*connection*/,
                                       const gchar* /*sender_name*/,
                                       const gchar* /*object_path*/,
                                       const gchar* /*interface_name*/,
                                       const gchar* /*signal_name*/,
                                       GVariant* parameters,
                                       gpointer user_data) {
  // PrepareForSleep(b start): TRUE before suspend, FALSE after resume.
  gboolean going_to_sleep = FALSE;
  g_variant_get(parameters, "(b)", &going_to_sleep);
  auto* self = static_cast<PowerEventHost*>(user_data);
  self->Emit(going_to_sleep ? "willSleep" : "didWake");
}

void PowerEventHost::Emit(const char* method) {
  if (!channel_) return;
  fl_method_channel_invoke_method(channel_, method, nullptr, nullptr, nullptr,
                                  nullptr);
}
