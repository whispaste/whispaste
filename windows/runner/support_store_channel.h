#ifndef RUNNER_SUPPORT_STORE_CHANNEL_H_
#define RUNNER_SUPPORT_STORE_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// Method channel "com.whispaste.support_store": one-off sponsoring as
// Microsoft Store consumable add-ons (Windows.Services.Store). Dart side:
// lib/services/support/windows_support_store_bridge.dart.
//
// Methods:
//   isAvailable              → bool (packaged process with a store context)
//   loadProducts {productIds} → [{productId, title, formattedPrice}] in the
//                              requested order; unknown ids are skipped
//   purchase {productId}     → "succeeded" | "cancelled" | "networkError" |
//                              "serverError" | "unavailable"
//   hasVerifiedAppPurchase   → bool (StoreAppLicense.IsActive && !IsTrial)
// Store failures on loadProducts / hasVerifiedAppPurchase reply with
// "store_error"; purchase never errors, it always answers a status name.
//
// Store operations complete on a thread-pool thread. Result conversion runs
// there, and every reply (and any follow-up Store call that needs the UI
// thread, such as the purchase dialog) is marshalled back to the platform
// thread through a window message. Flutter results must be sent from the
// platform thread.
class SupportStoreChannel {
 public:
  // |window| owns the Store purchase dialog and receives the reply messages.
  SupportStoreChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~SupportStoreChannel();

  SupportStoreChannel(const SupportStoreChannel&) = delete;
  SupportStoreChannel& operator=(const SupportStoreChannel&) = delete;

  // Runs a closure posted by this channel. Returns true when |message| was
  // such a closure (the caller then stops processing it).
  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND window_;
};

#endif  // RUNNER_SUPPORT_STORE_CHANNEL_H_
