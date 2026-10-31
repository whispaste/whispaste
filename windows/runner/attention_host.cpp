#include "attention_host.h"

#include <flutter/encodable_value.h>

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.attention";

}  // namespace

AttentionHost::AttentionHost(flutter::FlutterEngine* engine, HWND owner)
    : engine_(engine), owner_(owner) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine_->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
}

AttentionHost::~AttentionHost() { Destroy(); }

void AttentionHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

void AttentionHost::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (destroyed_) {
    result->Error("DESTROYED", "AttentionHost is destroyed");
    return;
  }

  const auto& method = call.method_name();

  if (method == "requestUserAttention") {
    const auto* args = call.arguments();
    const EncodableMap* map = args ? std::get_if<EncodableMap>(args) : nullptr;
    bool critical = true;
    if (map) {
      auto it = map->find(EncodableValue("level"));
      if (it != map->end()) {
        if (auto* s = std::get_if<std::string>(&it->second)) {
          critical = (*s != "informational");
        }
      }
    }
    const bool ok = RequestAttention(critical);
    // Return a non-null token so the Dart side has a "cancel handle". The
    // value itself is unused on Windows — we identify the flash by owner_.
    result->Success(EncodableValue(ok ? 1 : 0));
    return;
  }

  if (method == "cancelUserAttentionRequest") {
    CancelAttention();
    result->Success();
    return;
  }

  result->NotImplemented();
}

bool AttentionHost::RequestAttention(bool critical) {
  if (!owner_ || !::IsWindow(owner_)) return false;

  FLASHWINFO fw = {};
  fw.cbSize = sizeof(FLASHWINFO);
  fw.hwnd = owner_;
  // FLASHW_TRAY: flash the taskbar button.
  // FLASHW_TIMERNOFG: keep flashing until the window is brought to the
  //   foreground — matches the persistent macOS critical-request behaviour.
  fw.dwFlags = critical ? (FLASHW_TRAY | FLASHW_TIMERNOFG)
                        : (FLASHW_TRAY | FLASHW_TIMER);
  // 0 = use default cursor blink rate; critical flashes indefinitely
  // because of FLASHW_TIMERNOFG, informational stops after uCount.
  fw.uCount = critical ? 0 : 3;
  fw.dwTimeout = 0;
  return ::FlashWindowEx(&fw) != FALSE;
}

void AttentionHost::CancelAttention() {
  if (!owner_ || !::IsWindow(owner_)) return;
  FLASHWINFO fw = {};
  fw.cbSize = sizeof(FLASHWINFO);
  fw.hwnd = owner_;
  fw.dwFlags = FLASHW_STOP;
  ::FlashWindowEx(&fw);
}
