#ifndef RUNNER_STORE_REVIEW_CHANNEL_H_
#define RUNNER_STORE_REVIEW_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>

#include <winrt/Windows.Services.Store.h>

// Method channel "com.whispaste.store_review": the native Microsoft Store
// rating request (StoreContext.RequestRateAndReviewAppAsync). Dart side:
// lib/services/store_review_request_service.dart.
//
// Method "requestReview" answers one status name:
//   "succeeded" | "canceled"  the Store rating dialog was shown
//   "networkError" | "serverError"  the Store could not show it
//   "unavailable"  the process has no package identity (not Store-installed)
// A Store exception replies with the "store_error" error.
//
// The Store context needs the runner window as owner and runs on the
// platform thread. Completion arrives on a thread-pool thread. Its result is
// queued in a Mailbox owned by shared_ptr, so the completion never touches
// the channel object itself. The Mailbox is detached when the channel dies,
// so a reply can never reach a destroyed window or channel, and queued
// replies are dropped instead of leaking.
class StoreReviewChannel {
 public:
  StoreReviewChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~StoreReviewChannel();

  StoreReviewChannel(const StoreReviewChannel&) = delete;
  StoreReviewChannel& operator=(const StoreReviewChannel&) = delete;

  // Runs the queued replies when |message| is this channel's wake-up message.
  // Returns true when the message was consumed (the caller then stops).
  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  using Result = flutter::MethodResult<flutter::EncodableValue>;
  struct Mailbox;

  void RequestReview(std::shared_ptr<Result> reply);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND window_;
  std::shared_ptr<Mailbox> mailbox_;
  // Created on the platform thread on first use, owned by the runner window.
  std::optional<winrt::Windows::Services::Store::StoreContext> context_;
};

#endif  // RUNNER_STORE_REVIEW_CHANNEL_H_
