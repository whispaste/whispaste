// Runner-owned MethodChannel com.whispaste.app_identity.
//
// Answers `resolveApp` with the readable name (the exe's FileDescription) and
// icon (PNG with alpha) of a target app, so the recording rows show "Windows
// Terminal" with its icon instead of the raw exe name. The history stores
// only the exe name; the full path comes from the capture (remembered here
// for this session), else from a running process of that name, else from
// the App Paths registry. Dart caches every answer, so each app is looked up
// once.

#ifndef APP_IDENTITY_HOST_H_
#define APP_IDENTITY_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>

// Called by the paste host when it captures a target: remembers the full path
// of exe [name] (without `.exe`), so the lookup finds apps that closed since.
void RememberTargetExePath(const std::string& name, const std::wstring& path);

class AppIdentityHost {
 public:
  explicit AppIdentityHost(flutter::FlutterEngine* engine);
  ~AppIdentityHost();

  AppIdentityHost(const AppIdentityHost&) = delete;
  AppIdentityHost& operator=(const AppIdentityHost&) = delete;

  void Destroy();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool destroyed_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // APP_IDENTITY_HOST_H_
