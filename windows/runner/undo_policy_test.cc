// Test of the Windows undo decisions (undo_policy.h). Platform-neutral C++17;
// run via test/scripts/undo_policy_test.sh.
#include "undo_policy.h"

#include <cstdio>

namespace {
int failures = 0;
void Expect(bool ok, const char* what) {
  if (!ok) {
    std::fprintf(stderr, "FAIL: %s\n", what);
    ++failures;
  }
}
}  // namespace

int main() {
  Expect(IsUndoSafeExecutable("notepad"), "Notepad is a safe target");
  Expect(IsUndoSafeExecutable("Chrome"), "case does not matter");
  Expect(!IsUndoSafeExecutable("WindowsTerminal"), "a terminal is not safe");
  Expect(!IsUndoSafeExecutable("cmd"), "the console host is not safe");
  Expect(!IsUndoSafeExecutable("Code"), "an editor with a terminal is not safe");
  Expect(!IsUndoSafeExecutable("some-new-app"), "unknown takes the clipboard path");
  Expect(!IsUndoSafeExecutable(""), "an empty name is not safe");
  Expect(DecideActivateStep(7, 7, 0, 500) == ActivateStep::kDone, "in front");
  Expect(DecideActivateStep(3, 7, 100, 500) == ActivateStep::kWait, "waiting");
  Expect(DecideActivateStep(3, 7, 500, 500) == ActivateStep::kFailed, "timeout");
  Expect(DecideActivateStep(7, 7, 900, 500) == ActivateStep::kDone, "late win");
  Expect(DecideActivateStep(7, 0, 0, 500) == ActivateStep::kFailed, "no target");
  Expect(DecideActivateStep(0, 7, 100, 500) == ActivateStep::kWait, "no active yet");
  // Liveness with an injected clock (ms): a late tick reinstalls the hooks.
  Expect(DecideWatchTick(1000, 1050, 200) == WatchTick::kAlive, "on time");
  Expect(DecideWatchTick(1000, 1201, 200) == WatchTick::kReinstall, "late tick");
  Expect(DecideWatchTick(0, 1000, 200) == WatchTick::kReinstall, "never beat");
  Expect(DecideWatchTick(2000, 1000, 200) == WatchTick::kReinstall,
         "clock went back");
  Expect(WatcherCovers(5000, 4950, 1000, 3000, 200), "covered since before");
  Expect(!WatcherCovers(5000, 4000, 1000, 3000, 200), "frozen beat is no proof");
  Expect(!WatcherCovers(5000, 4950, 3500, 3000, 200),
         "reinstalled after the insert: input may be missed");
  Expect(!WatcherCovers(5000, 4950, 3010, 3000, 200),
         "hooks up only after the paste keys: not covered");
  Expect(!WatcherCovers(5000, 4950, 3000, 3000, 200),
         "same tick as the paste does not prove the hooks were first");
  Expect(!WatcherCovers(5000, 4950, 0, 3000, 200),
         "hooks not installed yet at the paste");
  Expect(!WatcherCovers(5000, 0, 1000, 3000, 200), "never beat");
  Expect(!WatcherCovers(5000, 4950, 1000, 0, 200), "no insert");
  // The last check before Ctrl+Z.
  Expect(DecideUndoSend("notepad", "notepad", true, 5, 1e9, 1e9, 1e9) ==
             UndoSendCheck::kSend,
         "untouched target gets Ctrl+Z");
  Expect(DecideUndoSend("notepad", "notepad", false, 5, 1e9, 1e9, 1e9) ==
             UndoSendCheck::kWatcherInactive,
         "lost hooks withhold Ctrl+Z");
  Expect(DecideUndoSend("notepad", "chrome", true, 5, 1e9, 1e9, 1e9) ==
             UndoSendCheck::kForegroundChanged,
         "another program in front");
  Expect(DecideUndoSend("", "", true, 5, 1e9, 1e9, 1e9) ==
             UndoSendCheck::kForegroundChanged,
         "unreadable target");
  Expect(DecideUndoSend("cmd", "cmd", true, 5, 1e9, 1e9, 1e9) ==
             UndoSendCheck::kUnsafeTarget,
         "console in front");
  Expect(DecideUndoSend("notepad", "notepad", true, 5, 1, 1e9, 1e9) ==
             UndoSendCheck::kUserInput,
         "a key since the insert");
  Expect(DecideUndoSend("notepad", "notepad", true, 5, 4.98, 5, 1e9) ==
             UndoSendCheck::kSend,
         "our own paste keys do not count");
  Expect(DecideUndoSend("notepad", "notepad", true, 5, 1e9, 1e9, 2) ==
             UndoSendCheck::kUserInput,
         "a click outside WhisPaste since the insert");
  Expect(std::string(UndoSendStatus(UndoSendCheck::kSend)) == "sent",
         "sent status");
  return failures == 0 ? 0 : 1;
}
