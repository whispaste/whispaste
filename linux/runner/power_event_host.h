// Owns the public MethodChannel com.whispaste.power (WP-39, 9.5).
//
// Forwards system sleep and resume to Dart as `willSleep` / `didWake`. The
// source is logind's PrepareForSleep signal on the system bus, which systemd
// emits on every suspend and resume. Without logind the subscription cannot
// be made and the host stays silent; nothing else depends on it.

#ifndef FLUTTER_POWER_EVENT_HOST_H_
#define FLUTTER_POWER_EVENT_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>

class PowerEventHost {
 public:
  explicit PowerEventHost(FlBinaryMessenger* messenger);
  ~PowerEventHost();

  PowerEventHost(const PowerEventHost&) = delete;
  PowerEventHost& operator=(const PowerEventHost&) = delete;

 private:
  static void OnPrepareForSleep(GDBusConnection* connection,
                                const gchar* sender_name,
                                const gchar* object_path,
                                const gchar* interface_name,
                                const gchar* signal_name,
                                GVariant* parameters,
                                gpointer user_data);

  void Emit(const char* method);

  FlMethodChannel* channel_ = nullptr;
  GDBusConnection* bus_ = nullptr;
  guint subscription_id_ = 0;
};

#endif  // FLUTTER_POWER_EVENT_HOST_H_
