#include "autostart_host.h"

#include <appmodel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Foundation.h>
#include <functional>
#include <string>

namespace {
using flutter::EncodableValue;
using SharedResult = std::shared_ptr<flutter::MethodResult<EncodableValue>>;
using winrt::Windows::ApplicationModel::StartupTask;
using winrt::Windows::ApplicationModel::StartupTaskState;
using winrt::Windows::Foundation::AsyncStatus;
constexpr char kChannelName[] = "com.whispaste.autostart";
constexpr UINT kPostedWorkMessage = WM_APP + 0x5B;

void Post(HWND window, std::function<void()> work) {
  auto* boxed = new std::function<void()>(std::move(work));
  if (!::PostMessage(window, kPostedWorkMessage, 0,
                     reinterpret_cast<LPARAM>(boxed))) delete boxed;
}

bool Enabled(StartupTaskState state) {
  return state == StartupTaskState::Enabled ||
         state == StartupTaskState::EnabledByPolicy;
}

// Older Store builds wrote a versioned WindowsApps path to Run. Remove only
// that package's entry; an unpackaged installation may coexist under the name.
void RemoveLegacyPackagedRunEntry() {
  const auto packagePath = L"\\WindowsApps\\" +
      std::wstring(winrt::Windows::ApplicationModel::Package::Current().Id().Name()) +
      L"_";
  HKEY key = nullptr;
  const auto opened = ::RegOpenKeyExW(HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
      KEY_QUERY_VALUE | KEY_SET_VALUE, &key);
  if (opened == ERROR_FILE_NOT_FOUND) return;
  if (opened != ERROR_SUCCESS) winrt::throw_hresult(HRESULT_FROM_WIN32(opened));
  wchar_t value[32768] = {};
  DWORD bytes = sizeof(value);
  const auto read = ::RegGetValueW(key, nullptr, L"WhisPaste", RRF_RT_REG_SZ,
                                  nullptr, value, &bytes);
  LONG removed = ERROR_SUCCESS;
  if (read == ERROR_SUCCESS &&
      std::wstring(value).find(packagePath) != std::wstring::npos) {
    removed = ::RegDeleteValueW(key, L"WhisPaste");
  }
  ::RegCloseKey(key);
  if (removed != ERROR_SUCCESS && removed != ERROR_FILE_NOT_FOUND)
    winrt::throw_hresult(HRESULT_FROM_WIN32(removed));
}

template <typename Operation, typename Done>
void Complete(HWND window, SharedResult reply, Operation operation, Done done) {
  operation.Completed([window, reply, done](const auto& sender, AsyncStatus status) {
    try {
      if (status != AsyncStatus::Completed)
        throw winrt::hresult_error(sender.ErrorCode());
      auto value = sender.GetResults();
      Post(window, [reply, done, value]() {
        try { done(value); }
        catch (const winrt::hresult_error& error) {
          reply->Error("autostart_error", winrt::to_string(error.message()));
        }
      });
    } catch (const winrt::hresult_error& error) {
      auto message = winrt::to_string(error.message());
      Post(window, [reply, message]() { reply->Error("autostart_error", message); });
    }
  });
}

void HandleMethodCall(HWND window, const flutter::MethodCall<EncodableValue>& call,
                      const SharedResult& reply) {
  const auto method = call.method_name();
  try {
    if (method == "isPackaged") {
      UINT32 length = 0;
      const LONG status = ::GetCurrentPackageFullName(&length, nullptr);
      if (status != ERROR_INSUFFICIENT_BUFFER && status != APPMODEL_ERROR_NO_PACKAGE) {
        reply->Error("autostart_error", "Cannot determine package identity");
      } else {
        reply->Success(EncodableValue(status == ERROR_INSUFFICIENT_BUFFER));
      }
      return;
    }
    if (method != "isEnabled" && method != "enable" && method != "disable") {
      reply->NotImplemented();
      return;
    }
    Complete(window, reply, StartupTask::GetAsync(L"WhisPasteStartup"),
             [window, reply, method](const StartupTask& task) {
      RemoveLegacyPackagedRunEntry();
      if (method == "enable") {
        Complete(window, reply, task.RequestEnableAsync(),
                 [reply](StartupTaskState state) {
          if (!Enabled(state)) {
            reply->Error("autostart_blocked",
                         "Windows blocked autostart. Check Settings > Apps > Startup.");
          } else {
            reply->Success(EncodableValue(true));
          }
        });
      } else {
        if (method == "disable") task.Disable();
        reply->Success(EncodableValue(Enabled(task.State())));
      }
    });
  } catch (const winrt::hresult_error& error) {
    reply->Error("autostart_error", winrt::to_string(error.message()));
  }
}
}  // namespace

AutostartHost::AutostartHost(flutter::BinaryMessenger* messenger,
                             HWND window)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())),
      window_(window) {
  channel_->SetMethodCallHandler([window = window_](const auto& call,
                                                  auto result) {
    HandleMethodCall(window, call, SharedResult(std::move(result)));
  });
}

AutostartHost::~AutostartHost() {
  channel_->SetMethodCallHandler(nullptr);
}

bool AutostartHost::HandleWindowMessage(UINT message, WPARAM, LPARAM lparam) {
  if (message != kPostedWorkMessage) return false;
  std::unique_ptr<std::function<void()>> work(
      reinterpret_cast<std::function<void()>*>(lparam));
  (*work)();
  return true;
}
