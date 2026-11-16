#include "inserted_span_host.h"

#include <flutter/standard_method_codec.h>

#include <atomic>
#include <exception>
#include <functional>
#include <string>
#include <thread>
#include <utility>

#include "inserted_span_reader.h"

using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {

constexpr char kChannelName[] = "com.whispaste.inserted_span";
// Private message that carries a std::function to the platform thread.
constexpr UINT kPostedWorkMessage = WM_APP + 0x54;

using Result = flutter::MethodResult<EncodableValue>;
using SharedResult = std::shared_ptr<Result>;

// At most this many reads run at once; a hung target must not pile up threads.
constexpr int kMaxInFlight = 2;
std::atomic<int> g_in_flight{0};

EncodableValue BusyMap() {
  EncodableMap map;
  map[EncodableValue("readable")] = EncodableValue(false);
  map[EncodableValue("text")] = EncodableValue();
  map[EncodableValue("matchesExpected")] = EncodableValue(false);
  map[EncodableValue("reason")] = EncodableValue("busy");
  map[EncodableValue("pattern")] = EncodableValue();
  return EncodableValue(std::move(map));
}

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int size = ::MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                         static_cast<int>(text.size()),
                                         nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring wide(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(),
                        static_cast<int>(text.size()), wide.data(), size);
  return wide;
}

std::string WideToUtf8(const std::wstring& text) {
  if (text.empty()) return std::string();
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, text.data(),
                                         static_cast<int>(text.size()),
                                         nullptr, 0, nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string out(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        out.data(), size, nullptr, nullptr);
  return out;
}

const EncodableValue* Lookup(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

int GetInt(const EncodableMap& map, const char* key, int fallback) {
  const EncodableValue* v = Lookup(map, key);
  if (!v) return fallback;
  if (auto* i = std::get_if<int32_t>(v)) return *i;
  if (auto* l = std::get_if<int64_t>(v)) return static_cast<int>(*l);
  return fallback;
}

EncodableValue ToMap(const inserted_span::Outcome& o) {
  EncodableMap map;
  map[EncodableValue("readable")] = EncodableValue(o.readable);
  map[EncodableValue("text")] =
      o.readable ? EncodableValue(WideToUtf8(o.text)) : EncodableValue();
  map[EncodableValue("matchesExpected")] = EncodableValue(o.matches_expected);
  map[EncodableValue("reason")] = EncodableValue(o.reason);
  map[EncodableValue("pattern")] =
      o.pattern.empty() ? EncodableValue() : EncodableValue(o.pattern);
  return EncodableValue(std::move(map));
}

// The worker captures only the HWND by value, so a host destroyed mid-read
// never leaves the thread holding a dangling pointer.
void PostToPlatformThread(HWND owner, std::function<void()> work) {
  auto* boxed = new std::function<void()>(std::move(work));
  if (!::PostMessage(owner, kPostedWorkMessage, 0,
                     reinterpret_cast<LPARAM>(boxed))) {
    delete boxed;
    OutputDebugStringW(L"[InsertedSpan] Reply dropped: window gone\n");
  }
}

}  // namespace

InsertedSpanHost::InsertedSpanHost(flutter::FlutterEngine* engine, HWND owner)
    : owner_(owner),
      channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const bool known = call.method_name() == "readInsertedSpan";
    if (!known) {
      result->NotImplemented();
      return;
    }
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    const EncodableValue* expected_value =
        args ? Lookup(*args, "expectedText") : nullptr;
    const auto* expected =
        expected_value ? std::get_if<std::string>(expected_value) : nullptr;
    if (!expected) {
      result->Error("INVALID_ARGS", "Missing expectedText");
      return;
    }
    const int slack = GetInt(*args, "slackChars", 0);
    const int after = GetInt(*args, "afterChars", 0);
    const HWND owner = owner_;
    if (g_in_flight.fetch_add(1) >= kMaxInFlight) {
      g_in_flight.fetch_sub(1);
      result->Success(BusyMap());
      return;
    }
    SharedResult shared(std::move(result));
    try {
      std::thread([owner, expected = Utf8ToWide(*expected), slack, after,
                   shared] {
        const inserted_span::Outcome outcome =
            inserted_span::Read(expected, slack, after);
        g_in_flight.fetch_sub(1);
        PostToPlatformThread(owner, [shared, outcome] {
          shared->Success(ToMap(outcome));
        });
      }).detach();
    } catch (const std::exception&) {
      g_in_flight.fetch_sub(1);
      shared->Error("THREAD_FAILED", "Could not start the read-back worker");
    }
  });
}

InsertedSpanHost::~InsertedSpanHost() { Destroy(); }

void InsertedSpanHost::Destroy() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  channel_.reset();
}

bool InsertedSpanHost::HandleWindowMessage(UINT message, WPARAM,
                                           LPARAM lparam) {
  if (message != kPostedWorkMessage) return false;
  std::unique_ptr<std::function<void()>> work(
      reinterpret_cast<std::function<void()>*>(lparam));
  (*work)();
  return true;
}
