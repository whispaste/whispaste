// Unit test for autorepeat_filter.h. Plain C++17, no X11/GLib, so it builds
// on any host: test/scripts/autorepeat_filter_test.sh compiles and runs it
// (also in the Linux CI job).
#include "autorepeat_filter.h"

#include <cstdio>

namespace {

int failures = 0;

void Expect(bool ok, const char* what) {
  if (!ok) {
    std::fprintf(stderr, "FAIL: %s\n", what);
    ++failures;
  }
}

// Feeds raw events through the filter the way the host does: a release arms
// the confirmation timer, a press of the same key disarms it. Returns whether
// the timer is still armed afterwards, i.e. whether key-up would be reported.
struct Sim {
  unsigned watched;
  bool armed = false;
  void Feed(unsigned keycode, bool is_release) {
    switch (ClassifyRawKeyEvent(watched, keycode, is_release)) {
      case RawKeyAction::kScheduleRelease:
        armed = true;
        break;
      case RawKeyAction::kCancelPendingRelease:
        armed = false;
        break;
      case RawKeyAction::kIgnore:
        break;
    }
  }
};

}  // namespace

int main() {
  constexpr unsigned kKey = 65;
  constexpr unsigned kOther = 66;

  Expect(ClassifyRawKeyEvent(0, kKey, true) == RawKeyAction::kIgnore,
         "nothing watched: release ignored");
  Expect(ClassifyRawKeyEvent(kKey, kOther, true) == RawKeyAction::kIgnore,
         "other key release ignored");
  Expect(ClassifyRawKeyEvent(kKey, kOther, false) == RawKeyAction::kIgnore,
         "other key press ignored");
  Expect(ClassifyRawKeyEvent(kKey, kKey, true) ==
             RawKeyAction::kScheduleRelease,
         "watched release schedules key-up");
  Expect(ClassifyRawKeyEvent(kKey, kKey, false) ==
             RawKeyAction::kCancelPendingRelease,
         "watched press cancels pending key-up");

  Sim held{kKey};
  for (int i = 0; i < 5; ++i) {
    held.Feed(kKey, true);
    held.Feed(kKey, false);
  }
  Expect(!held.armed, "autorepeat release/press pairs never report key-up");

  Sim released{kKey};
  released.Feed(kKey, true);
  released.Feed(kKey, false);
  released.Feed(kKey, true);
  Expect(released.armed, "final release after autorepeat reports key-up");

  Sim chord{kKey};
  chord.Feed(kKey, true);
  chord.Feed(kOther, false);
  Expect(chord.armed, "pressing another key does not cancel key-up");

  // Press length: known start only, plausible length, wrap of the clock.
  Expect(!PressDurationMs(false, 100, 250).has_value(),
         "unknown press start gives no length");
  Expect(PressDurationMs(true, 100, 250) == 150L, "press length in ms");
  Expect(PressDurationMs(true, 0xFFFFFFF0u, 0x10u) == 32L,
         "press length across a 32-bit clock wrap");
  Expect(!PressDurationMs(true, 0, 60001).has_value(),
         "press longer than the cap gives no length");
  Expect(PressDurationMs(true, 0, 60000) == 60000L, "cap itself is kept");
  Expect(PortalPressDurationMs(true, 1000000, 1150000) == 150L,
         "portal press length in microseconds");
  Expect(!PortalPressDurationMs(false, 1, 2).has_value(),
         "portal press without start gives no length");
  Expect(!PortalPressDurationMs(true, 5000, 1000).has_value(),
         "portal release before press gives no length");

  if (failures == 0) std::puts("autorepeat_filter_test: OK");
  return failures == 0 ? 0 : 1;
}
