// Unit test for desktop_entry.h. Plain C++17, no GLib, so it builds on any
// host: test/scripts/desktop_entry_test.sh compiles and runs it (also in the
// Linux CI job).
#include "desktop_entry.h"

#include <cstdio>
#include <string>

namespace {

int failures = 0;

void Expect(bool ok, const char* what) {
  if (!ok) {
    std::fprintf(stderr, "FAIL: %s\n", what);
    ++failures;
  }
}

bool Contains(const std::string& haystack, const std::string& needle) {
  return haystack.find(needle) != std::string::npos;
}

}  // namespace

int main() {
  // ── Exec argument quoting (Desktop Entry Spec, "The Exec key") ──────────
  Expect(DesktopExecArg("/opt/whispaste/whispaste") ==
             "\"/opt/whispaste/whispaste\"",
         "plain path is quoted");
  Expect(DesktopExecArg("/home/a b/WhisPaste/whispaste") ==
             "\"/home/a b/WhisPaste/whispaste\"",
         "space stays inside the quotes");
  // Quote-level escape first (\" \` \$ \\), then the string-value escape
  // doubles every backslash: a literal '$' ends up as \\$ in the file.
  Expect(DesktopExecArg("/x/$HOME/w") == "\"/x/\\\\$HOME/w\"",
         "dollar is escaped twice");
  Expect(DesktopExecArg("/x/\"q\"/w") == "\"/x/\\\\\"q\\\\\"/w\"",
         "double quote is escaped twice");
  Expect(DesktopExecArg("/x/`c`/w") == "\"/x/\\\\`c\\\\`/w\"",
         "backtick is escaped twice");
  Expect(DesktopExecArg("/x/a\\b/w") == "\"/x/a\\\\\\\\b/w\"",
         "backslash becomes four backslashes");
  Expect(DesktopExecArg("/x/100%/w") == "\"/x/100%%/w\"",
         "percent is not a field code");
  Expect(!DesktopExecArg("/x/a\nb/w").has_value(), "newline is rejected");
  Expect(!DesktopExecArg("/x/a\tb/w").has_value(), "tab is rejected");
  Expect(!DesktopExecArg("relative/whispaste").has_value(),
         "relative path is rejected");
  Expect(!DesktopExecArg("").has_value(), "empty path is rejected");

  // ── Entry content ───────────────────────────────────────────────────────
  const auto entry =
      BuildDesktopEntry("/home/a b/whispaste", "/home/a b/data/icon.png");
  Expect(entry.has_value(), "entry is built");
  const std::string text = entry.value_or("");
  Expect(text.rfind("[Desktop Entry]\n", 0) == 0, "starts with the group");
  Expect(Contains(text, "\nType=Application\n"), "type");
  Expect(Contains(text, "\nName=WhisPaste\n"), "name");
  Expect(Contains(text, "\nExec=\"/home/a b/whispaste\"\n"), "exec quoted");
  Expect(Contains(text, "\nIcon=/home/a b/data/icon.png\n"), "icon path");
  Expect(Contains(text, "\nNoDisplay=true\n"), "hidden from launchers");
  Expect(Contains(text, "\n" + std::string(kDesktopEntryMarker) + "\n"),
         "marker line");
  Expect(text.back() == '\n', "ends with a newline");

  const auto no_icon = BuildDesktopEntry("/opt/w/whispaste", "");
  Expect(no_icon.has_value() && !Contains(*no_icon, "Icon="),
         "no icon key without an icon");
  Expect(!BuildDesktopEntry("/opt/w/whispaste", "/i/a\nb.png").has_value(),
         "icon with a newline is rejected");
  Expect(!BuildDesktopEntry("whispaste", "").has_value(),
         "relative exec is rejected");

  // ── Write decision: never touch an entry WhisPaste did not write ───────
  const std::string desired = no_icon.value_or("");
  Expect(DecideDesktopEntry(false, std::nullopt, desired) ==
             DesktopEntryAction::kWrite,
         "missing entry is written");
  Expect(DecideDesktopEntry(true, std::nullopt, desired) ==
             DesktopEntryAction::kKeep,
         "packaged entry elsewhere (.deb) is kept");
  Expect(DecideDesktopEntry(false, std::string("[Desktop Entry]\nExec=x\n"),
                            desired) == DesktopEntryAction::kKeep,
         "foreign user entry without the marker is kept");
  Expect(DecideDesktopEntry(false, desired, desired) ==
             DesktopEntryAction::kKeep,
         "own up-to-date entry is kept");
  const std::string moved = BuildDesktopEntry("/new/place/whispaste", "")
                                .value_or("");
  Expect(DecideDesktopEntry(false, desired, moved) ==
             DesktopEntryAction::kWrite,
         "own entry is rewritten after the bundle moved");
  Expect(DecideDesktopEntry(true, desired, moved) ==
             DesktopEntryAction::kKeep,
         "packaged entry wins over an own stale one");

  if (failures == 0) std::printf("desktop_entry_test: all passed\n");
  return failures == 0 ? 0 : 1;
}
