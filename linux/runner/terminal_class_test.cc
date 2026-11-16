// Test of the terminal window-class list (terminal_class.h). Platform-neutral
// C++17; run via test/scripts/terminal_class_test.sh.
#include "terminal_class.h"

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
  Expect(IsTerminalWindowClass("gnome-terminal-server"), "GNOME Terminal");
  Expect(IsTerminalWindowClass("Konsole"), "case does not matter");
  Expect(IsTerminalWindowClass("code"), "an editor with an embedded terminal");
  Expect(IsTerminalWindowClass("jetbrains-idea-ce"), "JetBrains IDE prefix");
  Expect(IsTerminalWindowClass("org.gnome.Ptyxis"), "reverse-DNS class");
  Expect(!IsTerminalWindowClass("gedit"), "a plain editor is no terminal");
  Expect(!IsTerminalWindowClass("firefox"), "a browser is no terminal");
  Expect(!IsTerminalWindowClass("stellarium"), "a prefix of 'st' is no match");
  Expect(!IsTerminalWindowClass(""), "an empty class is unknown, not a terminal");
  Expect(IsUndoSafeWindowClass("Navigator"), "Firefox is a safe target");
  Expect(IsUndoSafeWindowClass("gedit"), "a plain editor is a safe target");
  Expect(!IsUndoSafeWindowClass("xterm"), "a terminal is never safe");
  Expect(!IsUndoSafeWindowClass("code"), "an editor with a terminal is not safe");
  Expect(!IsUndoSafeWindowClass("some-new-terminal"),
         "an unknown class takes the clipboard path");
  Expect(!IsUndoSafeWindowClass(""), "an empty class is not safe");
  Expect(DecideActivateStep(7, 7, 0, 500) == ActivateStep::kDone,
         "target in front: done at once");
  Expect(DecideActivateStep(3, 7, 100, 500) == ActivateStep::kWait,
         "other window in front: keep waiting");
  Expect(DecideActivateStep(3, 7, 500, 500) == ActivateStep::kFailed,
         "timeout reached: failed");
  Expect(DecideActivateStep(7, 7, 900, 500) == ActivateStep::kDone,
         "a late arrival that is in front still counts");
  Expect(DecideActivateStep(7, 0, 0, 500) == ActivateStep::kFailed,
         "no target: failed");
  Expect(DecideActivateStep(0, 7, 100, 500) == ActivateStep::kWait,
         "no active window yet: keep waiting");
  // Undo send decision (#731).
  const double kNone = 1e9;
  Expect(DecideUndoSend(false, 7, 7, "gedit", 5, kNone, kNone, kNone) ==
             UndoSendCheck::kWatcherInactive,
         "no watcher: nothing is sent");
  Expect(DecideUndoSend(true, 3, 7, "gedit", 5, kNone, kNone, kNone) ==
             UndoSendCheck::kForegroundChanged,
         "other window in front");
  Expect(DecideUndoSend(true, 0, 7, "gedit", 5, kNone, kNone, kNone) ==
             UndoSendCheck::kForegroundChanged,
         "no active window");
  Expect(DecideUndoSend(true, 7, 0, "gedit", 5, kNone, kNone, kNone) ==
             UndoSendCheck::kForegroundChanged,
         "no remembered target");
  Expect(DecideUndoSend(true, 7, 7, "xterm", 5, kNone, kNone, kNone) ==
             UndoSendCheck::kUnsafeTarget,
         "terminal: never");
  Expect(DecideUndoSend(true, 7, 7, "gedit", 5, kNone, kNone, kNone) ==
             UndoSendCheck::kSend,
         "quiet since the paste: send");
  Expect(DecideUndoSend(true, 7, 7, "gedit", 5, 2, kNone, kNone) ==
             UndoSendCheck::kUserInput,
         "typed since the paste");
  Expect(DecideUndoSend(true, 7, 7, "gedit", 5, 4.99, 5.0, kNone) ==
             UndoSendCheck::kSend,
         "the host's own synthetic key does not count");
  Expect(DecideUndoSend(true, 7, 7, "gedit", 5, 20, kNone, kNone) ==
             UndoSendCheck::kSend,
         "typing before the paste does not count");
  Expect(DecideUndoSend(true, 7, 7, "gedit", 5, kNone, kNone, 1) ==
             UndoSendCheck::kUserInput,
         "clicked outside since the paste");
  Expect(std::string(UndoSendStatus(UndoSendCheck::kUserInput)) == "user_input",
         "status string");
  Expect(std::string(UndoSendStatus(UndoSendCheck::kSend)) == "sent",
         "status string sent");
  return failures == 0 ? 0 : 1;
}
