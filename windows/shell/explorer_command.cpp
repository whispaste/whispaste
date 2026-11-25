// Explorer's packaged COM command. No Flutter runtime is loaded into Explorer.
#include <windows.h>
#include <shobjidl.h>
#include <shlwapi.h>
#include <atomic>
#include <new>
#include <string>
#include <vector>

namespace {
// Shared with MSIX and NSIS registration.
const CLSID kCommand = {0x65bdcc9f, 0xc60e, 0x4687,
                       {0xb1, 0x8b, 0x40, 0x9a, 0x24, 0x6e, 0x97, 0x15}};
HMODULE module = nullptr;
std::atomic<long> objects{0};

std::wstring Executable() {
  wchar_t path[32768];
  const DWORD length = GetModuleFileNameW(module, path, ARRAYSIZE(path));
  if (!length || length >= ARRAYSIZE(path)) return {};
  std::wstring result(path, length);
  return result.substr(0, result.find_last_of(L"\\/") + 1) + L"whispaste.exe";
}

bool Supported(const std::wstring& path) {
  const wchar_t* extension = PathFindExtensionW(path.c_str());
  const wchar_t* extensions[] = {L".wav", L".mp3", L".flac", L".m4a", L".aac",
    L".ogg", L".opus", L".mp4", L".mov", L".mkv", L".webm", L".mpeg",
    L".mpg", L".mpe", L".vob", L".ts", L".mts", L".m2ts"};
  for (const auto* candidate : extensions) {
    if (_wcsicmp(extension, candidate) == 0) return true;
  }
  return false;
}

HRESULT Paths(IShellItemArray* items, std::vector<std::wstring>& paths) {
  if (!items) return E_INVALIDARG;
  DWORD count = 0;
  HRESULT hr = items->GetCount(&count);
  if (FAILED(hr) || !count) return E_INVALIDARG;
  for (DWORD i = 0; i < count; ++i) {
    IShellItem* item = nullptr;
    hr = items->GetItemAt(i, &item);
    if (FAILED(hr)) return hr;
    PWSTR name = nullptr;
    SFGAOF attributes = 0;
    hr = item->GetAttributes(SFGAO_FOLDER | SFGAO_FILESYSTEM, &attributes);
    if (SUCCEEDED(hr) && (attributes & SFGAO_FILESYSTEM) && !(attributes & SFGAO_FOLDER)) {
      hr = item->GetDisplayName(SIGDN_FILESYSPATH, &name);
    } else {
      hr = E_INVALIDARG;
    }
    item->Release();
    if (FAILED(hr)) return hr;
    std::wstring path(name);
    CoTaskMemFree(name);
    if (!Supported(path)) return E_INVALIDARG;
    paths.push_back(std::move(path));
  }
  return S_OK;
}

// CommandLineToArgvW/CRT quoting, including trailing backslashes.
std::wstring Quote(const std::wstring& value) {
  std::wstring result = L"\"";
  size_t slashes = 0;
  for (wchar_t c : value) {
    if (c == L'\\') { ++slashes; continue; }
    result.append(c == L'"' ? slashes * 2 + 1 : slashes, L'\\');
    slashes = 0;
    result += c;
  }
  result.append(slashes * 2, L'\\');
  return result + L"\"";
}
HRESULT Launch(const std::wstring& exe, std::wstring command) {
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, FALSE,
                      0, nullptr, nullptr, &startup, &process)) {
    return HRESULT_FROM_WIN32(GetLastError());
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return S_OK;
}

class Command final : public IExplorerCommand {
 public:
  Command() { ++objects; }
  ~Command() { --objects; }
  IFACEMETHODIMP QueryInterface(REFIID iid, void** out) override {
    if (!out) return E_POINTER;
    *out = nullptr;
    if (iid == IID_IUnknown || iid == IID_IExplorerCommand) {
      *out = static_cast<IExplorerCommand*>(this); AddRef(); return S_OK;
    }
    return E_NOINTERFACE;
  }
  IFACEMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
  IFACEMETHODIMP_(ULONG) Release() override {
    const auto count = --refs_; if (!count) delete this; return count;
  }
  IFACEMETHODIMP GetTitle(IShellItemArray*, PWSTR* title) override {
    const wchar_t* text = L"Transcribe with WhisPaste";
    switch (PRIMARYLANGID(GetUserDefaultUILanguage())) {
      case LANG_GERMAN: text = L"Mit WhisPaste transkribieren"; break;
      case LANG_SPANISH: text = L"Transcribir con WhisPaste"; break;
      case LANG_PORTUGUESE: text = L"Transcrever com WhisPaste"; break;
      case LANG_RUSSIAN: text = L"Транскрибировать с WhisPaste"; break;
      case LANG_HEBREW: text = L"תמלול עם WhisPaste"; break;
    }
    return SHStrDupW(text, title);
  }
  IFACEMETHODIMP GetIcon(IShellItemArray*, PWSTR* icon) override {
    return SHStrDupW((Executable() + L",0").c_str(), icon);
  }
  IFACEMETHODIMP GetToolTip(IShellItemArray*, PWSTR* tip) override {
    if (!tip) return E_POINTER; *tip = nullptr; return E_NOTIMPL;
  }
  IFACEMETHODIMP GetCanonicalName(GUID* name) override {
    if (!name) return E_POINTER; *name = kCommand; return S_OK;
  }
  IFACEMETHODIMP GetState(IShellItemArray* items, BOOL, EXPCMDSTATE* state) override {
    if (!state) return E_POINTER;
    std::vector<std::wstring> paths;
    *state = SUCCEEDED(Paths(items, paths)) ? ECS_ENABLED : ECS_HIDDEN;
    return S_OK;
  }
  IFACEMETHODIMP Invoke(IShellItemArray* items, IBindCtx*) override {
    std::vector<std::wstring> paths;
    HRESULT hr = Paths(items, paths);
    if (FAILED(hr)) return hr;
    const auto exe = Executable();
    if (exe.empty()) return E_FAIL;
    const auto prefix = Quote(exe) + L" --import-files";
    auto command = prefix;
    for (const auto& path : paths) {
      const auto arg = L" " + Quote(path);
      if (prefix.size() + arg.size() >= 32767) return E_INVALIDARG;
      if (command.size() + arg.size() >= 32767) {
        hr = Launch(exe, command); if (FAILED(hr)) return hr;
        command = prefix;
      }
      command += arg;
    }
    return Launch(exe, command);
  }
  IFACEMETHODIMP GetFlags(EXPCMDFLAGS* flags) override {
    if (!flags) return E_POINTER; *flags = ECF_DEFAULT; return S_OK;
  }
  IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** out) override {
    if (!out) return E_POINTER; *out = nullptr; return E_NOTIMPL;
  }
 private:
  std::atomic<ULONG> refs_{1};
};

class Factory final : public IClassFactory {
 public:
  Factory() { ++objects; }
  ~Factory() { --objects; }
  IFACEMETHODIMP QueryInterface(REFIID iid, void** out) override {
    if (!out) return E_POINTER;
    *out = nullptr;
    if (iid == IID_IUnknown || iid == IID_IClassFactory) {
      *out = static_cast<IClassFactory*>(this); AddRef(); return S_OK;
    }
    return E_NOINTERFACE;
  }
  IFACEMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
  IFACEMETHODIMP_(ULONG) Release() override {
    const auto count = --refs_; if (!count) delete this; return count;
  }
  IFACEMETHODIMP CreateInstance(IUnknown* outer, REFIID iid, void** out) override {
    if (!out) return E_POINTER;
    *out = nullptr;
    if (outer) return CLASS_E_NOAGGREGATION;
    auto* command = new (std::nothrow) Command();
    if (!command) return E_OUTOFMEMORY;
    const HRESULT hr = command->QueryInterface(iid, out);
    command->Release(); return hr;
  }
  IFACEMETHODIMP LockServer(BOOL lock) override {
    if (lock) ++objects; else --objects; return S_OK;
  }
 private:
  std::atomic<ULONG> refs_{1};
};
}  // namespace

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    module = instance;
    DisableThreadLibraryCalls(instance);
  }
  return TRUE;
}
STDAPI DllCanUnloadNow() {
  return objects == 0 ? S_OK : S_FALSE;
}
STDAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void** out) {
  if (!out) return E_POINTER;
  *out = nullptr;
  if (clsid != kCommand) return CLASS_E_CLASSNOTAVAILABLE;
  auto* factory = new (std::nothrow) Factory();
  if (!factory) return E_OUTOFMEMORY;
  const HRESULT hr = factory->QueryInterface(iid, out);
  factory->Release(); return hr;
}
