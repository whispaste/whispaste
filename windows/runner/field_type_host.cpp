#include "field_type_host.h"

#include <flutter/standard_method_codec.h>

#include <atomic>
#include <exception>
#include <functional>
#include <string>
#include <thread>
#include <utility>

#include "field_type_reader.h"

using flutter::EncodableValue;

namespace {

constexpr char kChannelName[] = "com.whispaste.field_type";
constexpr char kUnknown[] = "unknown";
// Private message that carries a std::function to the platform thread.
constexpr UINT kPostedWorkMessage = WM_APP + 0x56;

using Result = flutter::MethodResult<EncodableValue>;
using SharedResult = std::shared_ptr<Result>;

// At most this many reads run at once; a hung target must not pile up threads.
constexpr int kMaxInFlight = 2;
std::atomic<int> g_in_flight{0};

// The worker captures only the HWND by value, so a host destroyed mid-read
// never leaves the thread holding a dangling pointer.
void PostToPlatformThread(HWND owner, std::function<void()> work) {
  auto* boxed = new std::function<void()>(std::move(work));
  if (!::PostMessage(owner, kPostedWorkMessage, 0,
                     reinterpret_cast<LPARAM>(boxed))) {
    delete boxed;
    OutputDebugStringW(L"[FieldType] Reply dropped: window gone\n");
  }
}

}  // namespace

FieldTypeHost::FieldTypeHost(flutter::FlutterEngine* engine, HWND owner)
    : owner_(owner),
      channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const bool known = call.method_name() == "focusedFieldType";
    if (!known) {
      result->NotImplemented();
      return;
    }
    if (g_in_flight.fetch_add(1) >= kMaxInFlight) {
      g_in_flight.fetch_sub(1);
      result->Success(EncodableValue(kUnknown));
      return;
    }
    const HWND owner = owner_;
    SharedResult shared(std::move(result));
    try {
      std::thread([owner, shared] {
        const std::string type = field_type::Read();
        g_in_flight.fetch_sub(1);
        PostToPlatformThread(owner, [shared, type] {
          shared->Success(EncodableValue(type));
        });
      }).detach();
    } catch (const std::exception&) {
      g_in_flight.fetch_sub(1);
      shared->Success(EncodableValue(kUnknown));
    }
  });
}

FieldTypeHost::~FieldTypeHost() { Destroy(); }

void FieldTypeHost::Destroy() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  channel_.reset();
}

bool FieldTypeHost::HandleWindowMessage(UINT message, WPARAM, LPARAM lparam) {
  if (message != kPostedWorkMessage) return false;
  std::unique_ptr<std::function<void()>> work(
      reinterpret_cast<std::function<void()>*>(lparam));
  (*work)();
  return true;
}
