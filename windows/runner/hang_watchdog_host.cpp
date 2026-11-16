#include "hang_watchdog_host.h"

#include <chrono>
#include <cstdio>
#include <cwchar>
#include <string>
#include <variant>

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.hang_watchdog";
constexpr wchar_t kMarkerFile[] = L"\\hang_watchdog_marker";
constexpr wchar_t kLastRestartFile[] = L"\\hang_watchdog_last_restart";
constexpr wchar_t kWaitArg[] = L"--hang-restart-wait=";

// GetTickCount64 includes sleep time, so a suspend shows up as a late tick
// (wake grace in hang_watchdog::Core).
int64_t TickMs() { return static_cast<int64_t>(::GetTickCount64()); }

int64_t WallMs() {
  FILETIME ft;
  ::GetSystemTimeAsFileTime(&ft);
  ULARGE_INTEGER v;
  v.LowPart = ft.dwLowDateTime;
  v.HighPart = ft.dwHighDateTime;
  // 100-ns ticks since 1601 -> ms since 1970.
  return static_cast<int64_t>(v.QuadPart / 10000ULL) - 11644473600000LL;
}

std::wstring Utf16FromUtf8(const std::string& s) {
  if (s.empty()) return {};
  const int n = ::MultiByteToWideChar(CP_UTF8, 0, s.data(),
                                      static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(n, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                        out.data(), n);
  return out;
}

int64_t ReadInt64(const std::wstring& path) {
  FILE* f = nullptr;
  if (_wfopen_s(&f, path.c_str(), L"r") != 0 || f == nullptr) return 0;
  long long value = 0;
  if (fscanf_s(f, "%lld", &value) != 1) value = 0;
  fclose(f);
  return static_cast<int64_t>(value);
}

// True only when the whole text reached `path`.
bool WriteFileSynced(const std::wstring& path, const std::string& text) {
  const std::wstring tmp = path + L".tmp";
  HANDLE h = ::CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, nullptr,
                           CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const BOOL ok = ::WriteFile(h, text.data(), static_cast<DWORD>(text.size()),
                              &written, nullptr);
  ::FlushFileBuffers(h);
  ::CloseHandle(h);
  if (ok && written == text.size() &&
      ::MoveFileExW(tmp.c_str(), path.c_str(),
                    MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    return true;
  }
  ::DeleteFileW(tmp.c_str());
  return false;
}

bool SpawnSuccessor() {
  wchar_t exe[MAX_PATH * 4];
  const DWORD len = ::GetModuleFileNameW(nullptr, exe, MAX_PATH * 4);
  if (len == 0 || len >= MAX_PATH * 4) return false;
  std::wstring cmd = L"\"" + std::wstring(exe) + L"\" " + kWaitArg +
                     std::to_wstring(::GetCurrentProcessId());
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};
  if (!::CreateProcessW(exe, cmd.data(), nullptr, nullptr, FALSE,
                        DETACHED_PROCESS, nullptr, nullptr, &si, &pi)) {
    return false;
  }
  ::CloseHandle(pi.hThread);
  ::CloseHandle(pi.hProcess);
  return true;
}

}  // namespace

void WaitForHangRestartPredecessor(const wchar_t* command_line) {
  if (command_line == nullptr) return;
  const wchar_t* arg = std::wcsstr(command_line, kWaitArg);
  if (arg == nullptr) return;
  const DWORD pid = static_cast<DWORD>(
      std::wcstoul(arg + std::wcslen(kWaitArg), nullptr, 10));
  if (pid == 0) return;
  HANDLE h = ::OpenProcess(SYNCHRONIZE, FALSE, pid);
  if (h == nullptr) return;  // already gone
  ::WaitForSingleObject(h, 15000);
  ::CloseHandle(h);
}

HangWatchdogHost::HangWatchdogHost(flutter::FlutterEngine* engine)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        const std::string& method = call.method_name();
        if (method == "beat") {
          std::lock_guard<std::mutex> lock(mutex_);
          core_.Beat(TickMs());
        } else if (method == "arm") {
          std::wstring dir;
          int64_t threshold = 0;
          if (const auto* map = std::get_if<EncodableMap>(call.arguments())) {
            auto d = map->find(EncodableValue("markerDir"));
            if (d != map->end()) {
              if (const auto* s = std::get_if<std::string>(&d->second)) {
                dir = Utf16FromUtf8(*s);
              }
            }
            auto t = map->find(EncodableValue("thresholdMs"));
            if (t != map->end()) {
              if (const auto* n = std::get_if<int32_t>(&t->second)) {
                threshold = *n;
              } else if (const auto* l = std::get_if<int64_t>(&t->second)) {
                threshold = *l;
              }
            }
          }
          std::lock_guard<std::mutex> lock(mutex_);
          marker_dir_ = dir;
          core_.Arm(TickMs(), threshold);
        } else if (method == "disarm") {
          std::lock_guard<std::mutex> lock(mutex_);
          core_.Disarm();
        } else {
          result->NotImplemented();
          return;
        }
        result->Success();
      });
  thread_ = std::thread([this] { Loop(); });
}

HangWatchdogHost::~HangWatchdogHost() { Destroy(); }

void HangWatchdogHost::Destroy() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stop_) return;
    stop_ = true;
    core_.Disarm();
  }
  cv_.notify_all();
  if (thread_.joinable()) thread_.join();
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  channel_.reset();
}

void HangWatchdogHost::Loop() {
  std::unique_lock<std::mutex> lock(mutex_);
  while (!stop_) {
    cv_.wait_for(lock, std::chrono::milliseconds(hang_watchdog::kTickMs));
    // Set by Destroy() while we waited on cv_.
    // cppcheck-suppress knownConditionTrueFalse
    if (stop_) break;
    const int64_t now = TickMs();
    if (core_.Tick(now) == hang_watchdog::Verdict::kHang) {
      const int64_t stalled = core_.StalledMs(now);
      const std::wstring dir = marker_dir_;
      lock.unlock();
      OnHang(stalled, dir);
      lock.lock();
    }
  }
}

void HangWatchdogHost::OnHang(int64_t stalled_ms,
                              const std::wstring& marker_dir) {
  const int64_t wall = WallMs();
  const std::wstring last_path = marker_dir + kLastRestartFile;
  const bool may_restart =
      !marker_dir.empty() &&
      hang_watchdog::Core::MayRestart(wall, ReadInt64(last_path));
  wchar_t line[160];
  swprintf_s(line, L"[hang-watchdog] main thread silent for %lld ms, %s\n",
             static_cast<long long>(stalled_ms),
             may_restart ? L"restarting" : L"restart cooldown, diagnosis only");
  ::OutputDebugStringW(line);
  if (marker_dir.empty()) return;
  bool restarting = may_restart;
  if (restarting) {
    // No restart unless the cooldown stamp is on disk: otherwise a full or
    // read-only data directory would restart the app in a loop.
    restarting = WriteFileSynced(last_path, std::to_string(wall)) &&
                 SpawnSuccessor();
  }
  WriteFileSynced(marker_dir + kMarkerFile,
                  "stalled_ms=" + std::to_string(stalled_ms) +
                      "\nrestarted=" + (restarting ? "1" : "0") +
                      "\nat_ms=" + std::to_string(wall) + "\n");
  if (restarting) ::TerminateProcess(::GetCurrentProcess(), 70);
}
