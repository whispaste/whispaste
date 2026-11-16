#include "media_pause_host.h"

// <unknwn.h> must precede the C++/WinRT headers so `as<>` works.
#include <unknwn.h>

#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>

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
