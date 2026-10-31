#include "app_identity_host.h"

#include <flutter/encodable_value.h>
#include <gdiplus.h>
#include <shellapi.h>
#include <shlobj.h>
#include <tlhelp32.h>

#include <algorithm>
#include <map>
#include <vector>

#include "gdiplus_helper.h"
#include "utils.h"

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.app_identity";

// Exe name (lower case, without `.exe`) → full path, from this session's
// captures. UI thread only, like every channel call.
std::map<std::wstring, std::wstring>& RememberedPaths() {
  static std::map<std::wstring, std::wstring> paths;
  return paths;
}

std::wstring Wide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int length = ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1,
                                           nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring out(length - 1, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, out.data(), length);
  return out;
}

std::wstring LowerExeName(std::wstring name) {
  if (name.size() > 4 && _wcsicmp(name.c_str() + name.size() - 4, L".exe") == 0) {
    name.resize(name.size() - 4);
  }
  std::transform(name.begin(), name.end(), name.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(::towlower(c)); });
  return name;
}

// Full path of a running process named [name], or empty.
std::wstring RunningProcessPath(const std::wstring& name) {
  HANDLE snapshot = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return std::wstring();
  std::wstring found;
  PROCESSENTRY32W entry = {};
  entry.dwSize = sizeof(entry);
  for (BOOL ok = ::Process32FirstW(snapshot, &entry); ok && found.empty();
       ok = ::Process32NextW(snapshot, &entry)) {
    if (LowerExeName(entry.szExeFile) != name) continue;
    HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                                   entry.th32ProcessID);
    if (!process) continue;
    wchar_t path[32768];
    DWORD size = static_cast<DWORD>(sizeof(path) / sizeof(path[0]));
    if (::QueryFullProcessImageNameW(process, 0, path, &size)) {
      found.assign(path, size);
    }
    ::CloseHandle(process);
  }
  ::CloseHandle(snapshot);
  return found;
}

// The App Paths registration of [name].exe (current user, then machine).
std::wstring AppPathsPath(const std::wstring& name) {
  const std::wstring key =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\" + name +
      L".exe";
  for (HKEY root : {HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE}) {
    wchar_t value[MAX_PATH * 2];
    DWORD size = sizeof(value);
    if (::RegGetValueW(root, key.c_str(), nullptr, RRF_RT_REG_SZ, nullptr,
                       value, &size) == ERROR_SUCCESS) {
      std::wstring path(value);
      // Some installers quote the path.
      if (path.size() > 1 && path.front() == L'"') {
        path = path.substr(1, path.find(L'"', 1) - 1);
      }
      if (::GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES) {
        return path;
      }
    }
  }
  return std::wstring();
}

std::wstring ExePathFor(const std::wstring& name) {
  const auto& remembered = RememberedPaths();
  const auto it = remembered.find(name);
  if (it != remembered.end() &&
      ::GetFileAttributesW(it->second.c_str()) != INVALID_FILE_ATTRIBUTES) {
    return it->second;
  }
  std::wstring path = RunningProcessPath(name);
  if (path.empty()) path = AppPathsPath(name);
  return path;
}

// The exe's FileDescription in its first listed language, or empty.
std::string FileDescription(const std::wstring& path) {
  DWORD handle = 0;
  const DWORD size = ::GetFileVersionInfoSizeW(path.c_str(), &handle);
  if (size == 0) return std::string();
  std::vector<BYTE> data(size);
  if (!::GetFileVersionInfoW(path.c_str(), 0, size, data.data())) {
    return std::string();
  }
  struct Translation {
    WORD language;
    WORD code_page;
  };
  Translation* translations = nullptr;
  UINT length = 0;
  if (!::VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                        reinterpret_cast<void**>(&translations), &length) ||
      length < sizeof(Translation)) {
    return std::string();
  }
  wchar_t query[64];
  swprintf_s(query, L"\\StringFileInfo\\%04x%04x\\FileDescription",
             translations[0].language, translations[0].code_page);
  wchar_t* description = nullptr;
  if (!::VerQueryValueW(data.data(), query,
                        reinterpret_cast<void**>(&description), &length) ||
      length == 0 || description == nullptr) {
    return std::string();
  }
  return Utf8FromUtf16(description);
}

bool PngEncoderClsid(CLSID* clsid) {
  UINT num = 0, size = 0;
  Gdiplus::GetImageEncodersSize(&num, &size);
  if (size == 0) return false;
  std::vector<BYTE> buffer(size);
  auto* codecs = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  Gdiplus::GetImageEncoders(num, size, codecs);
  for (UINT i = 0; i < num; ++i) {
    if (wcscmp(codecs[i].MimeType, L"image/png") == 0) {
      *clsid = codecs[i].Clsid;
      return true;
    }
  }
  return false;
}

// Straight 32-bit BGRA pixels of [icon], top-down. Icons without an alpha
// channel take their transparency from the mask.
bool IconPixels(HICON icon, int* width, int* height, std::vector<BYTE>* bgra) {
  ICONINFO info = {};
  if (!::GetIconInfo(icon, &info)) return false;
  bool ok = false;
  BITMAP bm = {};
  if (info.hbmColor && ::GetObject(info.hbmColor, sizeof(bm), &bm)) {
    *width = bm.bmWidth;
    *height = bm.bmHeight;
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = bm.bmWidth;
    bi.bmiHeader.biHeight = -bm.bmHeight;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    bgra->assign(static_cast<size_t>(bm.bmWidth) * bm.bmHeight * 4, 0);
    HDC dc = ::GetDC(nullptr);
    ok = ::GetDIBits(dc, info.hbmColor, 0, bm.bmHeight, bgra->data(), &bi,
                     DIB_RGB_COLORS) != 0;
    bool has_alpha = false;
    for (size_t i = 3; ok && i < bgra->size(); i += 4) {
      if ((*bgra)[i] != 0) {
        has_alpha = true;
        break;
      }
    }
    if (ok && !has_alpha && info.hbmMask) {
      std::vector<BYTE> mask(bgra->size(), 0);
      if (::GetDIBits(dc, info.hbmMask, 0, bm.bmHeight, mask.data(), &bi,
                      DIB_RGB_COLORS)) {
        for (size_t i = 0; i < bgra->size(); i += 4) {
          (*bgra)[i + 3] = mask[i] ? 0 : 255;
        }
      } else {
        for (size_t i = 3; i < bgra->size(); i += 4) (*bgra)[i] = 255;
      }
    }
    ::ReleaseDC(nullptr, dc);
  }
  if (info.hbmColor) ::DeleteObject(info.hbmColor);
  if (info.hbmMask) ::DeleteObject(info.hbmMask);
  return ok;
}

// The exe's icon at [size] pixels as PNG, or empty.
std::vector<uint8_t> IconPng(const std::wstring& path, int size) {
  std::vector<uint8_t> png;
  HICON icon = nullptr;
  if (FAILED(::SHDefExtractIconW(path.c_str(), 0, 0, &icon, nullptr,
                                 static_cast<UINT>(size))) ||
      !icon) {
    return png;
  }
  int width = 0, height = 0;
  std::vector<BYTE> pixels;
  const bool read = IconPixels(icon, &width, &height, &pixels);
  ::DestroyIcon(icon);
  if (!read || !GdiPlusHelper::AddRef()) return png;
  {
    Gdiplus::Bitmap bitmap(width, height, width * 4, PixelFormat32bppARGB,
                           pixels.data());
    CLSID clsid;
    IStream* stream = nullptr;
    if (bitmap.GetLastStatus() == Gdiplus::Ok && PngEncoderClsid(&clsid) &&
        SUCCEEDED(::CreateStreamOnHGlobal(nullptr, TRUE, &stream)) && stream) {
      if (bitmap.Save(stream, &clsid, nullptr) == Gdiplus::Ok) {
        // The stream length is the exact PNG size; GlobalSize rounds up.
        ULARGE_INTEGER length = {};
        LARGE_INTEGER origin = {};
        HGLOBAL global = nullptr;
        if (SUCCEEDED(stream->Seek(origin, STREAM_SEEK_END, &length)) &&
            length.QuadPart > 0 &&
            SUCCEEDED(::GetHGlobalFromStream(stream, &global)) && global) {
          if (const void* locked = ::GlobalLock(global)) {
            const auto* bytes = static_cast<const uint8_t*>(locked);
            png.assign(bytes, bytes + length.QuadPart);
            ::GlobalUnlock(global);
          }
        }
      }
      stream->Release();
    }
  }
  GdiPlusHelper::Release();
  return png;
}

EncodableValue ResolveApp(const std::string& id, int size) {
  EncodableMap result;
  const std::wstring name = LowerExeName(Wide(id));
  if (name.empty()) return EncodableValue(result);
  const std::wstring path = ExePathFor(name);
  if (path.empty()) return EncodableValue(result);
  const std::string description = FileDescription(path);
  if (!description.empty()) {
    result[EncodableValue("name")] = EncodableValue(description);
  }
  std::vector<uint8_t> png = IconPng(path, size);
  if (!png.empty()) {
    result[EncodableValue("icon")] = EncodableValue(std::move(png));
  }
  return EncodableValue(result);
}

}  // namespace

void RememberTargetExePath(const std::string& name, const std::wstring& path) {
  if (name.empty() || path.empty()) return;
  RememberedPaths()[LowerExeName(Wide(name))] = path;
}

AppIdentityHost::AppIdentityHost(flutter::FlutterEngine* engine)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
}

AppIdentityHost::~AppIdentityHost() { Destroy(); }

void AppIdentityHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;
  if (channel_) channel_->SetMethodCallHandler(nullptr);
}

void AppIdentityHost::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (destroyed_) {
    result->Error("DESTROYED", "AppIdentityHost is destroyed");
    return;
  }
  if (call.method_name() == "resolveApp") {
    const auto* args = call.arguments();
    const EncodableMap* map = args ? std::get_if<EncodableMap>(args) : nullptr;
    std::string id;
    int size = 64;
    if (map) {
      auto it = map->find(EncodableValue("id"));
      if (it != map->end()) {
        if (auto* s = std::get_if<std::string>(&it->second)) id = *s;
      }
      it = map->find(EncodableValue("size"));
      if (it != map->end()) {
        if (auto* n = std::get_if<int32_t>(&it->second)) size = *n;
      }
    }
    if (size < 16 || size > 256) size = 64;
    result->Success(ResolveApp(id, size));
    return;
  }
  result->NotImplemented();
}
