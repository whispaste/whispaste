#include "store_review_channel.h"

// <unknwn.h> must precede the C++/WinRT headers so `as<>` works with the
// classic COM interface IInitializeWithWindow.
#include <unknwn.h>

#include <appmodel.h>
#include <flutter/standard_method_codec.h>
#include <shobjidl_core.h>
#include <winrt/Windows.Foundation.h>

#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <utility>

namespace {

using flutter::EncodableValue;
using winrt::Windows::Foundation::AsyncStatus;
using winrt::Windows::Services::Store::StoreContext;
using winrt::Windows::Services::Store::StoreRateAndReviewStatus;

// Private window message for work posted to the platform thread. Distinct from
// SupportStoreChannel's message.
constexpr UINT kPostedWorkMessage = WM_APP + 0x53;

constexpr char kChannelName[] = "com.whispaste.store_review";

// Store APIs need a package identity. An unpackaged build has none, and the
// Store call would fail with an opaque HRESULT instead of a clear answer.
bool HasPackageIdentity() {
  UINT32 length = 0;
  return ::GetCurrentPackageFullName(&length, nullptr) !=
         APPMODEL_ERROR_NO_PACKAGE;
}

std::string HresultMessage(const winrt::hresult_error& error) {
  return winrt::to_string(error.message()) + " (0x" +
         std::to_string(static_cast<uint32_t>(error.code())) + ")";
}

std::string StatusName(StoreRateAndReviewStatus status) {
  // Names from the SDK enum: Succeeded, CanceledByUser, NetworkError, Error.
  // Compared one by one: the WinRT enum values are not usable as switch case
  // labels with MSVC.
  if (status == StoreRateAndReviewStatus::Succeeded) return "succeeded";
  if (status == StoreRateAndReviewStatus::CanceledByUser) return "canceled";
  if (status == StoreRateAndReviewStatus::NetworkError) return "networkError";
  return "serverError";
}

}  // namespace

// Work queued for the platform thread. Owned by shared_ptr: the Store
// completion and the channel both hold it, and it outlives either one as
// long as someone still needs it.
struct StoreReviewChannel::Mailbox {
  std::mutex mutex;
  HWND window = nullptr;  // null once the channel is gone
  std::deque<std::function<void()>> work;

  // Called from any thread. Drops the work when the channel is already gone
  // or the message cannot be posted.
  void Post(std::function<void()> item) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!window) return;
    work.push_back(std::move(item));
    if (!::PostMessage(window, kPostedWorkMessage, 0, 0)) {
      work.pop_back();
    }
  }

  // Called on the platform thread. Runs outside the lock, so replies can
  // safely post again.
  void Drain() {
    std::deque<std::function<void()>> ready;
    {
      std::lock_guard<std::mutex> lock(mutex);
      ready.swap(work);
    }
    for (const auto& item : ready) item();
  }

  // Called from the channel destructor on the platform thread. Pending
  // replies are dropped without being sent, because the engine is shutting
  // down.
  void Detach() {
    std::lock_guard<std::mutex> lock(mutex);
    window = nullptr;
    work.clear();
  }
};

StoreReviewChannel::StoreReviewChannel(flutter::BinaryMessenger* messenger,
                                       HWND window)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())),
      window_(window),
      mailbox_(std::make_shared<Mailbox>()) {
  mailbox_->window = window;
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "requestReview") {
          RequestReview(std::shared_ptr<Result>(std::move(result)));
          return;
        }
        result->NotImplemented();
      });
}

StoreReviewChannel::~StoreReviewChannel() { mailbox_->Detach(); }

void StoreReviewChannel::RequestReview(std::shared_ptr<Result> reply) {
  if (!HasPackageIdentity()) {
    reply->Success(EncodableValue("unavailable"));
    return;
  }
  try {
    if (!context_) {
      StoreContext created = StoreContext::GetDefault();
      created.as<IInitializeWithWindow>()->Initialize(window_);
      context_ = created;
    }
    std::shared_ptr<Mailbox> mailbox = mailbox_;
    context_->RequestRateAndReviewAppAsync().Completed(
        [mailbox, reply](const auto& sender, AsyncStatus status) {
          std::string name;
          std::string error;
          bool failed = false;
          try {
            if (status != AsyncStatus::Completed) {
              throw winrt::hresult_error(sender.ErrorCode());
            }
            name = StatusName(sender.GetResults().Status());
          } catch (const winrt::hresult_error& e) {
            failed = true;
            error = HresultMessage(e);
          } catch (...) {
            failed = true;
            error = "Unexpected Store failure.";
          }
          mailbox->Post([reply, name, failed, error] {
            if (failed) {
              reply->Error("store_error", error);
            } else {
              reply->Success(EncodableValue(name));
            }
          });
        });
  } catch (const winrt::hresult_error& e) {
    reply->Error("store_error", HresultMessage(e));
  }
}

bool StoreReviewChannel::HandleWindowMessage(UINT message, WPARAM,
                                             LPARAM) {
  if (message != kPostedWorkMessage) return false;
  mailbox_->Drain();
  return true;
}
