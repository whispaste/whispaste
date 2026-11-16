// Owns the public MethodChannel com.whispaste.app_identity.
//
// Answers `resolveApp` with the readable name and icon of a target app, so
// the recording rows show "Terminal" with its icon instead of the raw
// WM_CLASS or app_id. The app is found through its desktop entry in the XDG
// data folders (Flatpak and Snap exports included): by file name (Wayland
// app_id), then StartupWMClass or the Exec binary (X11 WM_CLASS). Name is the
// entry's localized Name, the icon comes from the icon theme as PNG.
// Dart caches every answer, so each app is looked up once.

#ifndef FLUTTER_APP_IDENTITY_HOST_H_
#define FLUTTER_APP_IDENTITY_HOST_H_

#include <flutter_linux/flutter_linux.h>

class AppIdentityHost {
 public:
  explicit AppIdentityHost(FlBinaryMessenger* messenger);
  ~AppIdentityHost();

  AppIdentityHost(const AppIdentityHost&) = delete;
  AppIdentityHost& operator=(const AppIdentityHost&) = delete;

 private:
  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data);

  FlMethodChannel* channel_ = nullptr;
};

#endif  // FLUTTER_APP_IDENTITY_HOST_H_
