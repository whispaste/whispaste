#include "clipboard_monitor_host.h"

#include <gdiplus.h>
#include <objbase.h>

#include <chrono>

#include "gdiplus_helper.h"

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.clipboard_history";

// Same shape as the GetInt() helper duplicated per-host across this
// directory (desktop_paste_host.cpp, floating_button_host.cpp,
// floating_overlay_host.cpp) -- kept local rather than shared since each
// file already does the same. Unlike those, this preserves full 64-bit
// range (needed for the fingerprint hash, which does not fit int32).
int64_t GetInt64(const EncodableMap& map, const std::string& key,
                  int64_t fallback = 0) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* i = std::get_if<int32_t>(&it->second)) return *i;
  if (auto* l = std::get_if<int64_t>(&it->second)) return *l;
  return fallback;
}

int64_t NowMs() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(system_clock::now().time_since_epoch())
      .count();
}

// WideCharToMultiByte wrapper -- CF_UNICODETEXT is UTF-16, but the
// fingerprint (must match Dart's utf8.encode bit-for-bit) and the
// "text" argument sent to Dart (a Flutter String is UTF-8 on the wire) both
// need UTF-8 bytes.
std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return {};
  int size = ::WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                   static_cast<int>(wide.size()), nullptr, 0,
                                   nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(size, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                        result.data(), size, nullptr, nullptr);
  return result;
}

// Standard MSDN pattern for locating an installed GDI+ encoder by MIME
// type. GdiPlusHelper (gdiplus_helper.h) doesn't have this -- it's a
// drawing-primitives helper for the floating button/overlay windows, not an
// encode-to-bytes one, so this stays local to the one caller that needs it.
bool GetPngEncoderClsid(CLSID* clsid) {
  UINT num = 0, size = 0;
  Gdiplus::GetImageEncodersSize(&num, &size);
  if (size == 0) return false;
  std::vector<BYTE> buffer(size);
  auto* codec_info = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  Gdiplus::GetImageEncoders(num, size, codec_info);
  for (UINT i = 0; i < num; ++i) {
    if (wcscmp(codec_info[i].MimeType, L"image/png") == 0) {
      *clsid = codec_info[i].Clsid;
      return true;
    }
  }
  return false;
}

}  // namespace

ClipboardMonitorHost::ClipboardMonitorHost(flutter::FlutterEngine* engine,
                                           HWND owner)
    : engine_(engine), owner_(owner) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine_->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });

  // Needed for the PNG encode path (ReadClipboardImagePng) -- ref-counted,
  // shared with FloatingButtonWindow/FloatingOverlayWindow.
  GdiPlusHelper::AddRef();

  if (owner_ && ::IsWindow(owner_)) {
    listener_registered_ = ::AddClipboardFormatListener(owner_) != FALSE;
  }
}

ClipboardMonitorHost::~ClipboardMonitorHost() { Destroy(); }

void ClipboardMonitorHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;

  if (listener_registered_ && owner_ && ::IsWindow(owner_)) {
    ::RemoveClipboardFormatListener(owner_);
  }
  listener_registered_ = false;

  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }

  GdiPlusHelper::Release();
}

void ClipboardMonitorHost::HandleClipboardUpdate() {
  if (destroyed_) return;
  ProcessClipboardChange();
}

void ClipboardMonitorHost::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (destroyed_) {
    result->Error("DESTROYED", "ClipboardMonitorHost is destroyed");
    return;
  }

  if (call.method_name() == "markSelfWrite") {
    const auto* args_map =
        call.arguments() ? std::get_if<EncodableMap>(call.arguments())
                          : nullptr;
    if (args_map) {
      HandleMarkSelfWrite(*args_map);
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

void ClipboardMonitorHost::HandleMarkSelfWrite(const EncodableMap& args) {
  const int64_t length = GetInt64(args, "length");
  const uint64_t hash = static_cast<uint64_t>(GetInt64(args, "hash"));
  MarkSelfWrite(Fingerprint{static_cast<size_t>(length), hash});
}

void ClipboardMonitorHost::ProcessClipboardChange() {
  const bool concealed = IsPrivacyExcluded();

  const std::wstring wide_text = ReadClipboardText();
  if (!wide_text.empty()) {
    const std::string utf8_text = WideToUtf8(wide_text);
    const Fingerprint fp = FingerprintOfUtf8(utf8_text);
    if (ShouldSuppress(fp)) return;
    EmitTextEntry(utf8_text, concealed);
    return;
  }

  // WhisPaste never writes images to the clipboard itself (matches the
  // Swift host's comment), so there is no self-write fingerprint to check
  // for images.
  const std::vector<uint8_t> png = ReadClipboardImagePng();
  if (!png.empty()) {
    EmitImageEntry(png, concealed);
  }
}

std::wstring ClipboardMonitorHost::ReadClipboardText() const {
  if (!::IsClipboardFormatAvailable(CF_UNICODETEXT)) return L"";
  if (!::OpenClipboard(owner_)) return L"";

  std::wstring result;
  HANDLE data = ::GetClipboardData(CF_UNICODETEXT);
  if (data) {
    const wchar_t* locked = static_cast<const wchar_t*>(::GlobalLock(data));
    if (locked) {
      result.assign(locked);
      ::GlobalUnlock(data);
    }
  }
  ::CloseClipboard();
  return result;
}

std::vector<uint8_t> ClipboardMonitorHost::ReadClipboardImagePng() const {
  if (!::IsClipboardFormatAvailable(CF_BITMAP)) return {};
  if (!::OpenClipboard(owner_)) return {};

  std::vector<uint8_t> png;
  HBITMAP hbitmap = static_cast<HBITMAP>(::GetClipboardData(CF_BITMAP));
  if (hbitmap) {
    Gdiplus::Bitmap bitmap(hbitmap, nullptr);
    CLSID png_clsid;
    if (bitmap.GetLastStatus() == Gdiplus::Ok && GetPngEncoderClsid(&png_clsid)) {
      IStream* stream = nullptr;
      if (SUCCEEDED(::CreateStreamOnHGlobal(nullptr, TRUE, &stream)) && stream) {
        if (bitmap.Save(stream, &png_clsid, nullptr) == Gdiplus::Ok) {
          HGLOBAL hglobal = nullptr;
          if (SUCCEEDED(::GetHGlobalFromStream(stream, &hglobal)) && hglobal) {
            const SIZE_T size = ::GlobalSize(hglobal);
            const void* locked = ::GlobalLock(hglobal);
            if (locked && size > 0) {
              const auto* bytes = static_cast<const uint8_t*>(locked);
              png.assign(bytes, bytes + size);
              ::GlobalUnlock(hglobal);
            }
          }
        }
        stream->Release();
      }
    }
  }
  ::CloseClipboard();
  return png;
}

bool ClipboardMonitorHost::IsPrivacyExcluded() const {
  // Registered once per process (RegisterClipboardFormatW returns the same
  // id for a given name on every call, so a static local is just a cache,
  // not a one-time side effect that could be missed on a second instance).
  static const UINT kExcludeFormat = ::RegisterClipboardFormatW(
      L"ExcludeClipboardContentFromMonitorProcessing");
  static const UINT kCanIncludeFormat =
      ::RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");

  // Presence-only signal -- used by KeePass/KeePassXC/1Password/NordPass/
  // Sticky Password and private-browsing modes (Edge/Firefox InPrivate).
  if (::IsClipboardFormatAvailable(kExcludeFormat)) return true;

  // Payload signal: a serialized DWORD, 0 = exclude, 1 = explicitly
  // include. Presence alone is NOT exclusion (an app can use this format to
  // opt IN as well as out), unlike the format above.
  if (::IsClipboardFormatAvailable(kCanIncludeFormat) &&
      ::OpenClipboard(owner_)) {
    bool exclude = false;
    HANDLE data = ::GetClipboardData(kCanIncludeFormat);
    if (data) {
      const void* locked = ::GlobalLock(data);
      if (locked && ::GlobalSize(data) >= sizeof(DWORD)) {
        exclude = (*static_cast<const DWORD*>(locked) == 0);
      }
      if (locked) ::GlobalUnlock(data);
    }
    ::CloseClipboard();
    return exclude;
  }

  return false;
}

void ClipboardMonitorHost::EmitTextEntry(const std::string& utf8_text,
                                         bool concealed) {
  if (!channel_) return;
  EncodableMap args;
  args[EncodableValue("kind")] = EncodableValue(std::string("text"));
  args[EncodableValue("capturedAtMs")] = EncodableValue(NowMs());
  args[EncodableValue("transient")] = EncodableValue(false);
  args[EncodableValue("concealed")] = EncodableValue(concealed);
  args[EncodableValue("autoGenerated")] = EncodableValue(false);
  args[EncodableValue("text")] = EncodableValue(utf8_text);
  channel_->InvokeMethod("clipEntryDetected",
                         std::make_unique<EncodableValue>(args));
}

void ClipboardMonitorHost::EmitImageEntry(const std::vector<uint8_t>& png,
                                          bool concealed) {
  if (!channel_) return;
  EncodableMap args;
  args[EncodableValue("kind")] = EncodableValue(std::string("image"));
  args[EncodableValue("capturedAtMs")] = EncodableValue(NowMs());
  args[EncodableValue("transient")] = EncodableValue(false);
  args[EncodableValue("concealed")] = EncodableValue(concealed);
  args[EncodableValue("autoGenerated")] = EncodableValue(false);
  args[EncodableValue("imageBytes")] = EncodableValue(png);
  channel_->InvokeMethod("clipEntryDetected",
                         std::make_unique<EncodableValue>(args));
}

void ClipboardMonitorHost::MarkSelfWrite(const Fingerprint& fp) {
  const ULONGLONG now = ::GetTickCount64();
  // Opportunistic prune of expired entries -- keeps the map bounded even if
  // a marked write is aborted and its corresponding WM_CLIPBOARDUPDATE
  // never arrives to consume it via ShouldSuppress.
  for (auto it = pending_self_writes_.begin();
       it != pending_self_writes_.end();) {
    it = (it->second <= now) ? pending_self_writes_.erase(it) : std::next(it);
  }
  pending_self_writes_[fp] =
      now + static_cast<ULONGLONG>(kSuppressionExpirySeconds * 1000);
}

bool ClipboardMonitorHost::ShouldSuppress(const Fingerprint& fp) {
  auto it = pending_self_writes_.find(fp);
  if (it == pending_self_writes_.end()) return false;
  const ULONGLONG expiry = it->second;
  pending_self_writes_.erase(it);
  return ::GetTickCount64() < expiry;
}

ClipboardMonitorHost::Fingerprint ClipboardMonitorHost::FingerprintOfUtf8(
    const std::string& utf8) {
  // FNV-1a, 64-bit -- bit-for-bit identical to Dart's _fnv1a64
  // (clipboard_fingerprint.dart) and Swift's fnv1a64
  // (ClipboardMonitorHost.swift). uint64_t arithmetic overflow wraps modulo
  // 2^64 per the C++ standard, matching Dart's explicit `& mask`.
  uint64_t hash = 0xcbf29ce484222325ULL;
  constexpr uint64_t kPrime = 0x100000001b3ULL;
  for (unsigned char byte : utf8) {
    hash ^= byte;
    hash *= kPrime;
  }
  return Fingerprint{utf8.size(), hash};
}
