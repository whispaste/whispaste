#include "undo_input_watcher.h"

#include "undo_policy.h"

#include <system_error>

namespace {
constexpr double kNever = 1e9;
// The hook thread wakes at least this often and beats.
constexpr DWORD kTickMs = 50;
// A beat older than this means a hook callback may have waited too long
// (Windows' LowLevelHooksTimeout defaults to a few hundred milliseconds), so
// the hooks are reinstalled and the times since the insert are no proof.
constexpr ULONGLONG kMaxGapMs = 200;
// The hooks are static callbacks; only one watcher exists (owned by the
// DesktopPasteHost), set while its hook thread runs.
std::atomic<UndoInputWatcher*> g_watcher{nullptr};
}  // namespace

UndoInputWatcher::~UndoInputWatcher() { Stop(); }

void UndoInputWatcher::Start() {
  if (running()) {
    if (!exited_.load()) return;
    // The hook thread ended (an install failed): join it and start over.
    Stop();
  }
  stop_ = false;
  exited_ = false;
  g_watcher = this;
  try {
    thread_ = std::thread([this] {
      thread_id_ = ::GetCurrentThreadId();
      Run();
      exited_ = true;
    });
  } catch (const std::system_error&) {
    // No thread: nothing is covered and the undo copies the original text.
    UndoInputWatcher* self = this;
    g_watcher.compare_exchange_strong(self, nullptr);
  }
}

void UndoInputWatcher::Stop() {
  if (thread_.joinable()) {
    stop_ = true;
    const DWORD id = thread_id_.load();
    // The thread also sees stop_ within one tick if the post fails.
    if (id != 0) ::PostThreadMessageW(id, WM_QUIT, 0, 0);
    thread_.join();
  }
  thread_id_ = 0;
  exited_ = false;
  UndoInputWatcher* self = this;
  g_watcher.compare_exchange_strong(self, nullptr);
  last_beat_ = 0;
  covered_since_ = 0;
  insert_ = 0;
  last_key_ = 0;
  last_button_ = 0;
  last_foreign_button_ = 0;
}

void UndoInputWatcher::MarkInsert(ULONGLONG paste_tick) {
  insert_ = paste_tick;
}

bool UndoInputWatcher::Covers() const {
  return WatcherCovers(::GetTickCount64(), last_beat_.load(),
                       covered_since_.load(), insert_.load(), kMaxGapMs);
}

bool UndoInputWatcher::InstallHooks() {
  const HINSTANCE module = ::GetModuleHandleW(nullptr);
  key_hook_ = ::SetWindowsHookExW(WH_KEYBOARD_LL, &UndoInputWatcher::KeyProc,
                                  module, 0);
  mouse_hook_ = ::SetWindowsHookExW(WH_MOUSE_LL, &UndoInputWatcher::MouseProc,
                                    module, 0);
  if (key_hook_ == nullptr || mouse_hook_ == nullptr) {
    RemoveHooks();
    return false;
  }
  return true;
}

void UndoInputWatcher::RemoveHooks() {
  if (key_hook_ != nullptr) ::UnhookWindowsHookEx(key_hook_);
  if (mouse_hook_ != nullptr) ::UnhookWindowsHookEx(mouse_hook_);
  key_hook_ = nullptr;
  mouse_hook_ = nullptr;
}

// Hook thread: installs the hooks, then only pumps messages (the hook
// callbacks run inside the pump) and beats every tick. Nothing here sleeps
// or blocks beyond the bounded message wait.
void UndoInputWatcher::Run() {
  ::SetThreadPriority(::GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
  MSG msg;
  // Creates the message queue before the hooks need it.
  ::PeekMessageW(&msg, nullptr, WM_USER, WM_USER, PM_NOREMOVE);
  if (InstallHooks()) {
    const ULONGLONG now = ::GetTickCount64();
    covered_since_ = now;
    last_beat_ = now;
  }
  if (key_hook_ == nullptr) return;

  while (!stop_.load()) {
    ::MsgWaitForMultipleObjects(0, nullptr, FALSE, kTickMs, QS_ALLINPUT);
    while (::PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) {
        stop_ = true;
        break;
      }
      ::TranslateMessage(&msg);
      ::DispatchMessageW(&msg);
    }
    if (stop_.load()) break;
    const ULONGLONG now = ::GetTickCount64();
    if (DecideWatchTick(last_beat_.load(), now, kMaxGapMs) ==
        WatchTick::kReinstall) {
      // A callback may have been late and Windows may have dropped a hook:
      // do not trust the old times, reinstall and cover from now on.
      RemoveHooks();
      if (!InstallHooks()) {
        last_beat_ = 0;
        covered_since_ = 0;
        break;
      }
      covered_since_ = ::GetTickCount64();
    }
    last_beat_ = ::GetTickCount64();
  }
  RemoveHooks();
}

// static
double UndoInputWatcher::Since(ULONGLONG stamp) {
  if (stamp == 0) return kNever;
  return static_cast<double>(::GetTickCount64() - stamp) / 1000.0;
}

double UndoInputWatcher::SinceInsertSeconds() const {
  return Since(insert_.load());
}
double UndoInputWatcher::KeyIdleSeconds() const {
  return Since(last_key_.load());
}
double UndoInputWatcher::MouseIdleSeconds() const {
  return Since(last_button_.load());
}
double UndoInputWatcher::MouseIdleOutsideAppSeconds() const {
  return Since(last_foreign_button_.load());
}

// static
LRESULT CALLBACK UndoInputWatcher::KeyProc(int code, WPARAM wparam,
                                           LPARAM lparam) {
  UndoInputWatcher* watcher = g_watcher.load();
  if (code == HC_ACTION && watcher != nullptr &&
      (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN)) {
    // Our own injected paste keys arrive here too; they are told apart with
    // the synthetic-key time.
    watcher->last_key_ = ::GetTickCount64();
  }
  return ::CallNextHookEx(nullptr, code, wparam, lparam);
}

// static
LRESULT CALLBACK UndoInputWatcher::MouseProc(int code, WPARAM wparam,
                                             LPARAM lparam) {
  UndoInputWatcher* watcher = g_watcher.load();
  if (code == HC_ACTION && watcher != nullptr &&
      (wparam == WM_LBUTTONDOWN || wparam == WM_RBUTTONDOWN ||
       wparam == WM_MBUTTONDOWN || wparam == WM_XBUTTONDOWN ||
       wparam == WM_MOUSEWHEEL)) {
    const ULONGLONG now = ::GetTickCount64();
    watcher->last_button_ = now;
    // Which top-level window sits under the pointer, asked without sending
    // messages (WindowFromPoint would send WM_NCHITTEST, and a hung program
    // could stall the hook until Windows drops it).
    const auto* info = reinterpret_cast<const MSLLHOOKSTRUCT*>(lparam);
    HWND under = ::ChildWindowFromPointEx(
        ::GetDesktopWindow(), info->pt,
        CWP_SKIPINVISIBLE | CWP_SKIPDISABLED | CWP_SKIPTRANSPARENT);
    DWORD pid = 0;
    if (under != nullptr && under != ::GetDesktopWindow()) {
      ::GetWindowThreadProcessId(under, &pid);
    }
    if (pid != ::GetCurrentProcessId()) watcher->last_foreign_button_ = now;
  }
  return ::CallNextHookEx(nullptr, code, wparam, lparam);
}
