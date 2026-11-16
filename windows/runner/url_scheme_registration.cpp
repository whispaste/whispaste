#include "url_scheme_registration.h"

#include <windows.h>

#include <appmodel.h>

#include <cwchar>
#include <string>

namespace {

constexpr wchar_t kSchemeKey[] = L"Software\\Classes\\whispaste";
constexpr wchar_t kCommandKey[] =
    L"Software\\Classes\\whispaste\\shell\\open\\command";

bool HasPackageIdentity() {
  UINT32 length = 0;
  return ::GetCurrentPackageFullName(&length, nullptr) !=
         APPMODEL_ERROR_NO_PACKAGE;
}

std::wstring ReadString(const wchar_t* key, const wchar_t* name) {
  DWORD size = 0;
  if (::RegGetValueW(HKEY_CURRENT_USER, key, name, RRF_RT_REG_SZ, nullptr,
                     nullptr, &size) != ERROR_SUCCESS ||
      size == 0) {
    return L"";
  }
  std::wstring value(size / sizeof(wchar_t), L'\0');
  if (::RegGetValueW(HKEY_CURRENT_USER, key, name, RRF_RT_REG_SZ, nullptr,
                     value.data(), &size) != ERROR_SUCCESS) {
    return L"";
  }
  value.resize(::wcsnlen(value.c_str(), value.size()));
  return value;
}

bool WriteString(const wchar_t* key, const wchar_t* name,
                 const std::wstring& value) {
  return ::RegSetKeyValueW(
             HKEY_CURRENT_USER, key, name, REG_SZ, value.c_str(),
             static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) ==
         ERROR_SUCCESS;
}

}  // namespace

void EnsureUrlSchemeRegistered() {
  if (HasPackageIdentity()) return;

  wchar_t path[MAX_PATH * 4];
  const DWORD length = ::GetModuleFileNameW(nullptr, path, ARRAYSIZE(path));
  if (length == 0 || length >= ARRAYSIZE(path)) return;

  const std::wstring command = L"\"" + std::wstring(path, length) + L"\" \"%1\"";
  if (ReadString(kCommandKey, nullptr) == command) return;

  // Best effort: without the key the confirmation page still says the
  // window can be closed, and the app asks on window focus.
  WriteString(kSchemeKey, nullptr, L"URL:WhisPaste");
  WriteString(kSchemeKey, L"URL Protocol", L"");
  WriteString(kCommandKey, nullptr, command);
}
