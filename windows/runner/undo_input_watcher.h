#ifndef RUNNER_UNDO_INPUT_WATCHER_H_
#define RUNNER_UNDO_INPUT_WATCHER_H_

#include <windows.h>

#include <atomic>
#include <thread>

// Tells key presses and mouse clicks apart for the keystroke undo (#428,
// #580). GetLastInputInfo only knows one idle time for everything, so the
// click on the undo action itself would read as typing. Low-level hooks keep
// only the *times* of the last key press, the last click and the last click
// outside this process's windows; no key value, character or click position
// is kept. The host starts the watcher when a recording captures its paste
// target (at the latest right before an insert) and stops it a while after
// the last insert, so input is not observed the rest of the time.
//
// The hooks live on their own thread that does nothing but pump messages, so
// no wait on the UI thread can delay a callback past LowLevelHooksTimeout
// (Windows then removes the hook silently and the times freeze). That thread
// beats every tick; a late tick reinstalls the hooks and restarts the
// coverage, and Covers() is false unless the hooks provably ran since before
// the insert (fail-closed, undo_policy.h). Start never waits: the paste path
// must not get slower, so hooks that are not up yet when the paste keys go
// out simply leave that insert uncovered.
class UndoInputWatcher {
 public:
  UndoInputWatcher() = default;
  ~UndoInputWatcher();

  UndoInputWatcher(const UndoInputWatcher&) = delete;
  UndoInputWatcher& operator=(const UndoInputWatcher&) = delete;

  // Starts the hook thread without waiting for the hooks; a no-op while it
  // runs, a restart when it ended (a hook install failed). UI thread only.
  void Start();
  // Ends the hook thread, removes the hooks and forgets all times. UI thread
  // only.
  void Stop();
  // Records the insert the undo would revert; [paste_tick] is the
  // GetTickCount64 value taken right before the paste keys went out. UI
  // thread only.
  void MarkInsert(ULONGLONG paste_tick);

  bool running() const { return thread_.joinable(); }
  // Whether the hooks saw every key and click since the last insert.
  bool Covers() const;

  // Seconds since the insert, the last key press, the last click anywhere
  // and the last click outside this process's windows; 1e9 when there was
  // none.
  double SinceInsertSeconds() const;
  double KeyIdleSeconds() const;
  double MouseIdleSeconds() const;
  double MouseIdleOutsideAppSeconds() const;

 private:
  void Run();
  bool InstallHooks();
  void RemoveHooks();
  static LRESULT CALLBACK KeyProc(int code, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK MouseProc(int code, WPARAM wparam, LPARAM lparam);
  static double Since(ULONGLONG stamp);

  std::thread thread_;
  std::atomic<DWORD> thread_id_{0};
  std::atomic<bool> stop_{false};
  // Set by the hook thread when it returns (hooks failed or stop).
  std::atomic<bool> exited_{false};
  // Hook handles, touched only on the hook thread.
  HHOOK key_hook_ = nullptr;
  HHOOK mouse_hook_ = nullptr;
  // GetTickCount64 values, 0 = never. Written on the hook thread (beat,
  // coverage, input) or the UI thread (insert), read on the UI thread.
  std::atomic<ULONGLONG> last_beat_{0};
  std::atomic<ULONGLONG> covered_since_{0};
  std::atomic<ULONGLONG> insert_{0};
  std::atomic<ULONGLONG> last_key_{0};
  std::atomic<ULONGLONG> last_button_{0};
  std::atomic<ULONGLONG> last_foreign_button_{0};
};

#endif  // RUNNER_UNDO_INPUT_WATCHER_H_
