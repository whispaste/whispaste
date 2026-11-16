#ifndef RUNNER_UNDO_POLICY_H_
#define RUNNER_UNDO_POLICY_H_

#include <algorithm>
#include <cctype>
#include <string>

// Pure decisions of the Windows host for the keystroke undo (#428, #580).
// Platform-neutral C++17 so they are tested without Windows
// (test/scripts/undo_policy_test.sh).

// Whether the keystroke undo (Ctrl+Z) may go to a window of this executable
// base name (no ".exe", as getTargetBundleId reports it): only programs known
// to be plain text targets. Everything else, terminals, editors with an
// embedded terminal and unknown programs included, takes the clipboard path
// because Ctrl+Z in a console can interrupt the running process. Extend the
// list with real names seen on a lab VM, never with guesses.
inline bool IsUndoSafeExecutable(const std::string& exe_base_name) {
  std::string name = exe_base_name;
  std::transform(name.begin(), name.end(), name.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  static const char* const kSafe[] = {
      // Browsers.
      "chrome", "msedge", "firefox", "brave", "vivaldi", "opera",
      // Plain editors and office.
      "notepad", "notepad++", "wordpad", "winword", "excel", "powerpnt",
      "onenote", "soffice", "obsidian", "logseq", "typora", "marktext",
      // Mail and chat.
      "outlook", "olk", "thunderbird", "slack", "discord", "telegram",
      "signal", "ms-teams", "teams", "element",
  };
  for (const char* known : kSafe) {
    if (name == known) return true;
  }
  return false;
}

// How the wait for the paste target to come to the front goes on
// (#428 activateTarget); [elapsed_ms] is passed in so no real time is needed.
enum class ActivateStep { kWait, kDone, kFailed };
inline ActivateStep DecideActivateStep(unsigned long long active_window,
                                       unsigned long long target_window,
                                       long elapsed_ms, long timeout_ms) {
  if (target_window == 0) return ActivateStep::kFailed;
  if (active_window == target_window) return ActivateStep::kDone;
  if (elapsed_ms >= timeout_ms) return ActivateStep::kFailed;
  return ActivateStep::kWait;
}

// Liveness of the key/click hooks (#580). Windows removes a low-level hook
// without notice when its thread does not answer within LowLevelHooksTimeout,
// and the recorded times then freeze. The hook thread wakes every tick; a gap
// longer than [max_gap_ms] since its last beat means a callback may have been
// late, so the hooks are reinstalled instead of trusted. All times are
// monotonic milliseconds, passed in so no real clock is needed.
enum class WatchTick { kAlive, kReinstall };
inline WatchTick DecideWatchTick(unsigned long long last_beat_ms,
                                 unsigned long long now_ms,
                                 unsigned long long max_gap_ms) {
  if (last_beat_ms == 0 || now_ms < last_beat_ms) return WatchTick::kReinstall;
  return now_ms - last_beat_ms > max_gap_ms ? WatchTick::kReinstall
                                            : WatchTick::kAlive;
}

// Whether the hooks provably saw every key and click since the insert:
// installed (and never reinstalled) before the paste keys went out, and
// beating now. A frozen beat or coverage that started after the paste is no
// proof (fail-closed); 0 means "never". [insert_ms] is taken right before the
// paste keys are sent, and the watcher is started without waiting, so hooks
// that came up during or after the paste leave that insert uncovered. Equal
// stamps count as "after": GetTickCount64 moves in steps of 10 to 16 ms, so
// the same value does not prove the hooks were first.
inline bool WatcherCovers(unsigned long long now_ms,
                          unsigned long long last_beat_ms,
                          unsigned long long covered_since_ms,
                          unsigned long long insert_ms,
                          unsigned long long max_gap_ms) {
  if (last_beat_ms == 0 || covered_since_ms == 0 || insert_ms == 0) {
    return false;
  }
  if (DecideWatchTick(last_beat_ms, now_ms, max_gap_ms) != WatchTick::kAlive) {
    return false;
  }
  return covered_since_ms < insert_ms;
}

// The last check right before Ctrl+Z goes out (sendUndoShortcut): the
// foreground program is still the paste target and a safe text program, the
// hooks still cover the span since the insert, and no key (other than our own
// synthetic ones, within [kSyntheticKeyToleranceS]) and no click outside
// WhisPaste went down since then. Idle values are seconds; same rule as
// userInputSince in lib/services/paste/input_idle.dart.
constexpr double kSyntheticKeyToleranceS = 0.05;
enum class UndoSendCheck {
  kSend,
  kWatcherInactive,
  kForegroundChanged,
  kUnsafeTarget,
  kUserInput,
};
inline UndoSendCheck DecideUndoSend(const std::string& target_exe,
                                    const std::string& foreground_exe,
                                    bool watcher_covers, double since_insert_s,
                                    double key_idle_s, double synthetic_idle_s,
                                    double foreign_click_idle_s) {
  if (!watcher_covers) return UndoSendCheck::kWatcherInactive;
  if (target_exe.empty() || foreground_exe != target_exe) {
    return UndoSendCheck::kForegroundChanged;
  }
  if (!IsUndoSafeExecutable(foreground_exe)) return UndoSendCheck::kUnsafeTarget;
  const bool typed = key_idle_s < since_insert_s &&
                     key_idle_s < synthetic_idle_s - kSyntheticKeyToleranceS;
  const bool clicked = foreign_click_idle_s < since_insert_s;
  return typed || clicked ? UndoSendCheck::kUserInput : UndoSendCheck::kSend;
}

// Status string sendUndoShortcut answers ("sent" only when the keystroke
// went out; the Dart side takes the clipboard path otherwise).
inline const char* UndoSendStatus(UndoSendCheck check) {
  switch (check) {
    case UndoSendCheck::kSend:
      return "sent";
    case UndoSendCheck::kWatcherInactive:
      return "watcher_inactive";
    case UndoSendCheck::kForegroundChanged:
      return "foreground_changed";
    case UndoSendCheck::kUnsafeTarget:
      return "unsafe_target";
    case UndoSendCheck::kUserInput:
      return "user_input";
  }
  return "unknown";
}

#endif  // RUNNER_UNDO_POLICY_H_
