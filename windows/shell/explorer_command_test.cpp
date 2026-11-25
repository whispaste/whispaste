// Standalone MSVC regression test; compile with ole32 shlwapi shell32 uuid.
#include "explorer_command.cpp"
#include <shellapi.h>
#include <cassert>
#include <iostream>

int wmain() {
  assert(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)));
  module = GetModuleHandleW(nullptr);
  for (const std::wstring path : {L"C:\\audio file.mpeg", L"C:\\日本語\\a.ts",
                                 L"C:\\trailing\\", L"a\\\"b"}) {
    const auto command = L"app.exe " + Quote(path);
    int count = 0;
    auto args = CommandLineToArgvW(command.c_str(), &count);
    assert(args && count == 2 && path == args[1]);
    LocalFree(args);
  }
  for (const auto* path : {L"a.MPEG", L"a.mpg", L"a.mpe", L"a.vob", L"a.ts",
                          L"a.mts", L"a.m2ts", L"a.wav", L"a.mp3"}) {
    assert(Supported(path));
  }
  assert(!Supported(L"a.txt"));
  assert(DllCanUnloadNow() == S_OK);
  IClassFactory* factory = nullptr;
  assert(SUCCEEDED(DllGetClassObject(kCommand, IID_PPV_ARGS(&factory))));
  assert(DllCanUnloadNow() == S_FALSE);
  IExplorerCommand* command = nullptr;
  assert(SUCCEEDED(factory->CreateInstance(nullptr, IID_PPV_ARGS(&command))));
  factory->Release();
  EXPCMDSTATE state = ECS_ENABLED;
  assert(SUCCEEDED(command->GetState(nullptr, TRUE, &state)) && state == ECS_HIDDEN);
  wchar_t temp[MAX_PATH], filename[MAX_PATH];
  GetTempPathW(MAX_PATH, temp);
  GetTempFileNameW(temp, L"wpt", 0, filename);
  const std::wstring audio = std::wstring(filename) + L".MPEG";
  assert(MoveFileW(filename, audio.c_str()));
  IShellItem* item = nullptr;
  assert(SUCCEEDED(SHCreateItemFromParsingName(audio.c_str(), nullptr, IID_PPV_ARGS(&item))));
  IShellItemArray* items = nullptr;
  assert(SUCCEEDED(SHCreateShellItemArrayFromShellItem(item, IID_PPV_ARGS(&items))));
  item->Release();
  assert(SUCCEEDED(command->GetState(items, TRUE, &state)) && state == ECS_ENABLED);
  std::vector<std::wstring> paths;
  assert(SUCCEEDED(Paths(items, paths)) && paths.size() == 1 && paths[0] == audio);
  items->Release();
  DeleteFileW(audio.c_str());
  PWSTR title = nullptr;
  assert(SUCCEEDED(command->GetTitle(nullptr, &title)) && wcsstr(title, L"WhisPaste"));
  CoTaskMemFree(title);
  command->Release();
  assert(DllCanUnloadNow() == S_OK);
  CoUninitialize();
  std::cout << "Explorer COM, selection, extension and argument tests passed\n";
}
