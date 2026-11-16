#include "app_identity_host.h"

#include <flutter/encodable_value.h>
#include <appmodel.h>
#include <gdiplus.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
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

// Exe name → AUMID of packaged (Store) apps, captured while the process ran.
std::map<std::wstring, std::wstring>& RememberedAumids() {
  static std::map<std::wstring, std::wstring> aumids;
  return aumids;
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

// AppUserModelId of the packaged app that owns [process], or empty for an
// ordinary desktop process.
std::wstring AumidOfProcess(HANDLE process) {
  UINT32 length = 0;
  if (::GetApplicationUserModelId(process, &length, nullptr) !=
          ERROR_INSUFFICIENT_BUFFER ||
      length == 0 || length > 1024) {
    return std::wstring();
  }
  std::wstring aumid(length, L'\0');
  if (::GetApplicationUserModelId(process, &length, aumid.data()) !=
      ERROR_SUCCESS) {
    return std::wstring();
  }
  aumid.resize(wcslen(aumid.c_str()));
  return aumid;
}

// AUMID of the first application of the package that [exe_path] belongs to,
// derived from the package folder name (the folder below WindowsApps is the
// PackageFullName) for apps that are not running. Empty for anything else.
std::wstring AumidFromPackagePath(const std::wstring& exe_path) {
  const std::wstring marker = L"\\windowsapps\\";
  std::wstring lower = exe_path;
  std::transform(lower.begin(), lower.end(), lower.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(::towlower(c)); });
  const size_t at = lower.find(marker);
  if (at == std::wstring::npos) return std::wstring();
  const size_t start = at + marker.size();
  const size_t end = exe_path.find(L'\\', start);
  if (end == std::wstring::npos) return std::wstring();
  const std::wstring full_name = exe_path.substr(start, end - start);

  UINT32 family_length = 0;
  if (::PackageFamilyNameFromFullName(full_name.c_str(), &family_length,
                                      nullptr) != ERROR_INSUFFICIENT_BUFFER ||
      family_length == 0 || family_length > 256) {
    return std::wstring();
  }
  std::wstring family(family_length, L'\0');
  if (::PackageFamilyNameFromFullName(full_name.c_str(), &family_length,
                                      family.data()) != ERROR_SUCCESS) {
    return std::wstring();
  }
  family.resize(wcslen(family.c_str()));

  PACKAGE_INFO_REFERENCE info = nullptr;
  if (::OpenPackageInfoByFullName(full_name.c_str(), 0, &info) !=
          ERROR_SUCCESS ||
      !info) {
    return std::wstring();
  }
  std::wstring aumid;
  UINT32 bytes = 0, count = 0;
  if (::GetPackageApplicationIds(info, &bytes, nullptr, &count) ==
          ERROR_INSUFFICIENT_BUFFER &&
      bytes > 0 && bytes < 64 * 1024) {
    std::vector<BYTE> buffer(bytes);
    if (::GetPackageApplicationIds(info, &bytes, buffer.data(), &count) ==
            ERROR_SUCCESS &&
        count > 0) {
      // An array of pointers to the (relative) application ids, which live in
      // the same buffer.
      const auto* ids = reinterpret_cast<const PCWSTR*>(buffer.data());
      if (ids[0] && ids[0][0] != L'\0') aumid = family + L"!" + ids[0];
    }
  }
  ::ClosePackageInfo(info);
  return aumid;
}

// Full path of a running process named [name], or empty. A packaged app's
// AUMID is remembered on the way (the process is open anyway).
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
      const std::wstring aumid = AumidOfProcess(process);
      if (!aumid.empty()) RememberedAumids()[name] = aumid;
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

// [known_path] is the path Dart persisted at an earlier capture; it carries
// the lookup across restarts and past the closed app.
std::wstring ExePathFor(const std::wstring& name,
                        const std::wstring& known_path) {
  const auto& remembered = RememberedPaths();
  const auto it = remembered.find(name);
  if (it != remembered.end() &&
      ::GetFileAttributesW(it->second.c_str()) != INVALID_FILE_ATTRIBUTES) {
    return it->second;
  }
  if (!known_path.empty() &&
      ::GetFileAttributesW(known_path.c_str()) != INVALID_FILE_ATTRIBUTES) {
    return known_path;
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

// PNG bytes of [width]x[height] BGRA pixels, or empty. [premultiplied] says
// whether the colour channels are already multiplied by alpha.
std::vector<uint8_t> PngFromPixels(int width, int height,
                                   std::vector<BYTE>* pixels,
                                   bool premultiplied) {
  std::vector<uint8_t> png;
  if (width <= 0 || height <= 0 || !GdiPlusHelper::AddRef()) return png;
  {
    Gdiplus::Bitmap bitmap(
        width, height, width * 4,
        premultiplied ? PixelFormat32bppPARGB : PixelFormat32bppARGB,
        pixels->data());
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

// The exe's icon at [size] pixels as PNG, or empty. Packaged apps have no
// icon in the exe; they come back empty and take the shell route below.
std::vector<uint8_t> IconPng(const std::wstring& path, int size) {
  HICON icon = nullptr;
  if (FAILED(::SHDefExtractIconW(path.c_str(), 0, 0, &icon, nullptr,
                                 static_cast<UINT>(size))) ||
      !icon) {
    return {};
  }
  int width = 0, height = 0;
  std::vector<BYTE> pixels;
  const bool read = IconPixels(icon, &width, &height, &pixels);
  ::DestroyIcon(icon);
  if (!read) return {};
  return PngFromPixels(width, height, &pixels, false);
}

// Straight-from-the-shell identity of a packaged app: its tile icon and
// localised name via `shell:AppsFolder\<AUMID>`. Both stay empty on any
// failure.
struct ShellAppInfo {
  std::vector<uint8_t> png;
  std::string name;
};

ShellAppInfo ShellAppInfoFor(const std::wstring& aumid, int size,
                             bool want_name) {
  ShellAppInfo info;
  if (aumid.empty()) return info;
  IShellItem* item = nullptr;
  const std::wstring parsing = L"shell:AppsFolder\\" + aumid;
  if (FAILED(::SHCreateItemFromParsingName(parsing.c_str(), nullptr,
                                           IID_PPV_ARGS(&item))) ||
      !item) {
    return info;
  }
  if (want_name) {
    PWSTR display = nullptr;
    if (SUCCEEDED(item->GetDisplayName(SIGDN_NORMALDISPLAY, &display)) &&
        display) {
      info.name = Utf8FromUtf16(display);
      ::CoTaskMemFree(display);
    }
  }
  IShellItemImageFactory* factory = nullptr;
  if (SUCCEEDED(item->QueryInterface(IID_PPV_ARGS(&factory))) && factory) {
    HBITMAP bitmap = nullptr;
    const SIZE wanted = {size, size};
    if (SUCCEEDED(factory->GetImage(
            wanted, SIIGBF_ICONONLY | SIIGBF_BIGGERSIZEOK, &bitmap)) &&
        bitmap) {
      BITMAP bm = {};
      if (::GetObject(bitmap, sizeof(bm), &bm) && bm.bmWidth > 0 &&
          bm.bmHeight > 0) {
        BITMAPINFO bi = {};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = bm.bmWidth;
        bi.bmiHeader.biHeight = -bm.bmHeight;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        std::vector<BYTE> pixels(static_cast<size_t>(bm.bmWidth) * bm.bmHeight *
                                     4,
                                 0);
        HDC dc = ::GetDC(nullptr);
        const bool ok = dc && ::GetDIBits(dc, bitmap, 0, bm.bmHeight,
                                          pixels.data(), &bi,
                                          DIB_RGB_COLORS) != 0;
        if (dc) ::ReleaseDC(nullptr, dc);
        if (ok) {
          // Shell thumbnails carry premultiplied alpha.
          info.png = PngFromPixels(bm.bmWidth, bm.bmHeight, &pixels, true);
        }
      }
      ::DeleteObject(bitmap);
    }
    factory->Release();
  }
  item->Release();
  return info;
}

// Fills [out] and returns true when the exe was located. False means "could
// not tell" (app closed, no persisted path): the host answers with an error,
// so Dart does not cache it as "no such app".
bool ResolveApp(const std::string& id, const std::string& known_path, int size,
                EncodableValue* out) {
  EncodableMap result;
  const std::wstring name = LowerExeName(Wide(id));
  if (name.empty()) return false;
  const std::wstring path = ExePathFor(name, Wide(known_path));
  if (path.empty()) return false;
  result[EncodableValue("path")] = EncodableValue(Utf8FromUtf16(path.c_str()));
  const std::string description = FileDescription(path);
  if (!description.empty()) {
    result[EncodableValue("name")] = EncodableValue(description);
  }
  std::vector<uint8_t> png = IconPng(path, size);
  if (png.empty() || description.empty()) {
    // Packaged (Store) apps: no icon in the exe, name in the package. The
    // AUMID comes from the capture, else from the package folder name.
    std::wstring aumid;
    const auto remembered = RememberedAumids().find(name);
    if (remembered != RememberedAumids().end()) aumid = remembered->second;
    if (aumid.empty()) aumid = AumidFromPackagePath(path);
    ShellAppInfo shell =
        ShellAppInfoFor(aumid, size, /*want_name=*/description.empty());
    if (png.empty()) png = std::move(shell.png);
    if (description.empty() && !shell.name.empty()) {
      result[EncodableValue("name")] = EncodableValue(shell.name);
    }
  }
  if (!png.empty()) {
    result[EncodableValue("icon")] = EncodableValue(std::move(png));
  }
  *out = EncodableValue(std::move(result));
  return true;
}

}  // namespace

void RememberTargetExePath(const std::string& name, const std::wstring& path,
                           DWORD process_id) {
  if (name.empty() || path.empty()) return;
  const std::wstring key = LowerExeName(Wide(name));
  RememberedPaths()[key] = path;
  if (process_id == 0) return;
  HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                                 process_id);
  if (!process) return;
  const std::wstring aumid = AumidOfProcess(process);
  ::CloseHandle(process);
  if (!aumid.empty()) RememberedAumids()[key] = aumid;
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
    std::string known_path;
    int size = 64;
    if (map) {
      auto it = map->find(EncodableValue("id"));
      if (it != map->end()) {
        if (auto* s = std::get_if<std::string>(&it->second)) id = *s;
      }
      it = map->find(EncodableValue("path"));
      if (it != map->end()) {
        if (auto* s = std::get_if<std::string>(&it->second)) known_path = *s;
      }
      it = map->find(EncodableValue("size"));
      if (it != map->end()) {
        if (auto* n = std::get_if<int32_t>(&it->second)) size = *n;
      }
    }
    if (size < 16 || size > 256) size = 64;
    EncodableValue reply;
    if (ResolveApp(id, known_path, size, &reply)) {
      result->Success(reply);
    } else {
      result->Error("UNRESOLVED", "App executable not found");
    }
    return;
  }
  result->NotImplemented();
}
