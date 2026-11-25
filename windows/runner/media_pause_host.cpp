#include "media_pause_host.h"

// <unknwn.h> must precede the C++/WinRT headers so `as<>` works.
#include <unknwn.h>

#include <audiopolicy.h>
#include <endpointvolume.h>
#include <flutter/standard_method_codec.h>
#include <mmdeviceapi.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/base.h>

#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

using flutter::EncodableValue;
using winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSession;
using winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionManager;
using winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionPlaybackStatus;

using Result = flutter::MethodResult<EncodableValue>;
using SharedResult = std::shared_ptr<Result>;

// Private window message carrying a heap-allocated std::function<void()> that
// runs on the platform thread. Distinct from the other runner hosts' messages.
constexpr UINT kPostedWorkMessage = WM_APP + 0x5A;
constexpr char kChannelName[] = "com.whispaste.media_pause";

void PostToPlatformThread(HWND window, std::function<void()> work) {
  auto* boxed = new std::function<void()>(std::move(work));
  if (!::PostMessage(window, kPostedWorkMessage, 0,
                     reinterpret_cast<LPARAM>(boxed))) {
    // Window gone (shutdown): drop the reply, the engine is gone with it.
    delete boxed;
  }
}


std::string Utf8(const wchar_t* wide) {
  if (wide == nullptr) return std::string();
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0,
                                         nullptr, nullptr);
  if (size <= 1) return std::string();
  std::string out(static_cast<size_t>(size - 1), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), size, nullptr,
                        nullptr);
  return out;
}

// One audio session of the default playback device that is not WhisPaste's
// own and not the system sounds.
struct ForeignSession {
  std::string id;  // session instance identifier (includes the process)
  winrt::com_ptr<ISimpleAudioVolume> volume;
  bool audible = false;
};

// Sessions of the default render endpoint (ducking, #1511). Throws
// winrt::hresult_error when there is no endpoint.
std::vector<ForeignSession> ForeignSessions() {
  auto enumerator = winrt::create_instance<IMMDeviceEnumerator>(
      __uuidof(MMDeviceEnumerator));
  winrt::com_ptr<IMMDevice> device;
  winrt::check_hresult(
      enumerator->GetDefaultAudioEndpoint(eRender, eConsole, device.put()));
  winrt::com_ptr<IAudioSessionManager2> manager;
  winrt::check_hresult(device->Activate(__uuidof(IAudioSessionManager2),
                                        CLSCTX_ALL, nullptr,
                                        manager.put_void()));
  winrt::com_ptr<IAudioSessionEnumerator> sessions;
  winrt::check_hresult(manager->GetSessionEnumerator(sessions.put()));
  int count = 0;
  winrt::check_hresult(sessions->GetCount(&count));
  const DWORD own = ::GetCurrentProcessId();
  std::vector<ForeignSession> out;
  for (int i = 0; i < count; ++i) {
    winrt::com_ptr<IAudioSessionControl> control;
    if (FAILED(sessions->GetSession(i, control.put()))) continue;
    auto control2 = control.try_as<IAudioSessionControl2>();
    if (!control2 || control2->IsSystemSoundsSession() == S_OK) continue;
    DWORD pid = 0;
    if (FAILED(control2->GetProcessId(&pid)) || pid == own || pid == 0) {
      continue;
    }
    LPWSTR raw_id = nullptr;
    if (FAILED(control2->GetSessionInstanceIdentifier(&raw_id))) continue;
    ForeignSession session;
    session.id = Utf8(raw_id);
    ::CoTaskMemFree(raw_id);
    session.volume = control.try_as<ISimpleAudioVolume>();
    if (!session.volume || session.id.empty()) continue;
    AudioSessionState state = AudioSessionStateInactive;
    BOOL muted = FALSE;
    float peak = 0.0f;
    auto meter = control.try_as<IAudioMeterInformation>();
    // Audible: an active stream that is not muted and actually sends sound.
    // An open but silent stream (a paused browser tab) is left alone.
    session.audible = SUCCEEDED(control->GetState(&state)) &&
                      state == AudioSessionStateActive &&
                      SUCCEEDED(session.volume->GetMute(&muted)) && !muted &&
                      meter && SUCCEEDED(meter->GetPeakValue(&peak)) &&
                      peak > 0.0f;
    out.push_back(std::move(session));
  }
  return out;
}

EncodableValue PlayingVolumes() {
  flutter::EncodableList list;
  for (auto const& session : ForeignSessions()) {
    if (!session.audible) continue;
    float level = 0.0f;
    if (FAILED(session.volume->GetMasterVolume(&level))) continue;
    list.push_back(EncodableValue(flutter::EncodableMap{
        {EncodableValue("id"), EncodableValue(session.id)},
        {EncodableValue("levels"),
         EncodableValue(flutter::EncodableList{
             EncodableValue(static_cast<double>(level))})},
    }));
  }
  return EncodableValue(list);
}

// Sets each listed session to its level; a session that ended is skipped.
// The float -> double -> float round trip is exact, so a restore puts back
// the very value read before.
void SetVolumes(const EncodableValue* arguments) {
  const auto* targets =
      arguments ? std::get_if<flutter::EncodableList>(arguments) : nullptr;
  if (targets == nullptr || targets->empty()) return;
  auto sessions = ForeignSessions();
  for (auto const& entry : *targets) {
    const auto* map = std::get_if<flutter::EncodableMap>(&entry);
    if (map == nullptr) continue;
    auto id_it = map->find(EncodableValue("id"));
    auto levels_it = map->find(EncodableValue("levels"));
    if (id_it == map->end() || levels_it == map->end()) continue;
    const auto* id = std::get_if<std::string>(&id_it->second);
    const auto* levels = std::get_if<flutter::EncodableList>(&levels_it->second);
    if (id == nullptr || levels == nullptr || levels->empty()) continue;
    const auto* level = std::get_if<double>(&levels->front());
    if (level == nullptr) continue;
    for (auto const& session : sessions) {
      if (session.id != *id) continue;
      float value = static_cast<float>(*level);
      if (value < 0.0f) value = 0.0f;
      if (value > 1.0f) value = 1.0f;
      session.volume->SetMasterVolume(value, nullptr);
    }
  }
}

}  // namespace

// Sessions this host paused; guarded because pause and resume run on worker
// threads. Only these are ever resumed.
struct MediaPauseHost::State {
  std::mutex mutex;
  std::vector<GlobalSystemMediaTransportControlsSession> paused;
};

MediaPauseHost::MediaPauseHost(flutter::BinaryMessenger* messenger, HWND window)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())),
      state_(std::make_shared<State>()),
      window_(window) {
  channel_->SetMethodCallHandler(
      [state = state_, window](
          const flutter::MethodCall<EncodableValue>& call,
          std::unique_ptr<Result> raw_result) {
        SharedResult result(std::move(raw_result));
        const std::string method = call.method_name();
        if (method == "duckAvailable" || method == "playingVolumes" ||
            method == "setVolumes") {
          std::unique_ptr<EncodableValue> args;
          if (call.arguments()) {
            args = std::make_unique<EncodableValue>(*call.arguments());
          }
          std::thread([window, result, method,
                       args = std::shared_ptr<EncodableValue>(
                           std::move(args))] {
            EncodableValue reply;
            try {
              winrt::init_apartment(winrt::apartment_type::multi_threaded);
              if (method == "duckAvailable") {
                ForeignSessions();
                reply = EncodableValue(true);
              } else if (method == "playingVolumes") {
                reply = PlayingVolumes();
              } else {
                SetVolumes(args.get());
              }
            } catch (const winrt::hresult_error&) {
              if (method == "duckAvailable") {
                reply = EncodableValue(false);
              } else if (method == "setVolumes") {
                // Keep the journal so the next start restores (#1511).
                PostToPlatformThread(window, [result] {
                  result->Error("unavailable", "no playback device");
                });
                return;
              } else {
                reply = EncodableValue(flutter::EncodableList{});
              }
            }
            PostToPlatformThread(window, [result, reply] {
              result->Success(reply);
            });
          }).detach();
          return;
        }
        if (method != "isAvailable" && method != "pauseIfPlaying" &&
            method != "resumePaused") {
          result->NotImplemented();
          return;
        }
        // SMTC calls block; keep them off the platform thread.
        std::thread([state, window, result, method] {
          EncodableValue reply;
          try {
            winrt::init_apartment(winrt::apartment_type::multi_threaded);
            auto manager =
                GlobalSystemMediaTransportControlsSessionManager::
                    RequestAsync()
                        .get();
            if (method == "isAvailable") {
              reply = EncodableValue(static_cast<bool>(manager));
            } else if (method == "pauseIfPlaying") {
              bool any = false;
              std::lock_guard<std::mutex> lock(state->mutex);
              for (auto const& session : manager.GetSessions()) {
                auto info = session.GetPlaybackInfo();
                if (info.PlaybackStatus() ==
                    GlobalSystemMediaTransportControlsSessionPlaybackStatus::
                        Playing) {
                  if (session.TryPauseAsync().get()) {
                    state->paused.push_back(session);
                    any = true;
                  }
                }
              }
              reply = EncodableValue(std::string(any ? "paused" : "nothing"));
            } else {
              std::vector<GlobalSystemMediaTransportControlsSession> mine;
              {
                std::lock_guard<std::mutex> lock(state->mutex);
                mine.swap(state->paused);
              }
              for (auto const& session : mine) {
                try {
                  // Resume only if the session is still paused: if the user
                  // started or stopped it meanwhile, leave it alone (#1254).
                  if (session.GetPlaybackInfo().PlaybackStatus() !=
                      GlobalSystemMediaTransportControlsSessionPlaybackStatus::
                          Paused) {
                    continue;
                  }
                  session.TryPlayAsync().get();
                } catch (const winrt::hresult_error&) {
                  // The player is gone; nothing to resume.
                }
              }
              reply = EncodableValue();
            }
          } catch (const winrt::hresult_error&) {
            reply = (method == "isAvailable")
                        ? EncodableValue(false)
                        : (method == "pauseIfPlaying"
                               ? EncodableValue(std::string("unavailable"))
                               : EncodableValue());
          }
          PostToPlatformThread(window, [result, reply] {
            result->Success(reply);
          });
        }).detach();
      });
}

MediaPauseHost::~MediaPauseHost() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
}

bool MediaPauseHost::HandleWindowMessage(UINT message, WPARAM, LPARAM lparam) {
  if (message != kPostedWorkMessage) return false;
  std::unique_ptr<std::function<void()>> work(
      reinterpret_cast<std::function<void()>*>(lparam));
  (*work)();
  return true;
}
