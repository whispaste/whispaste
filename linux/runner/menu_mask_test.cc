// Unit test for menu_mask.h. Plain C++17, no X11/Win32.
#include "menu_mask.h"
#include "../../windows/runner/hook_health.h"

#include <cstdio>

namespace {

int failures = 0;

void Check(bool ok, const char* what) {
  std::printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

}  // namespace

int main() {
  {
    HookHealth health;
    health.Reset(100);
    Check(!health.MissingAt(99), "queued input before hook installation ignored");
    Check(!health.MissingAt(1100), "hook health allows timestamp slack");
    Check(health.MissingAt(1101), "raw input detects silent hook removal");
    health.Seen(1200);
    Check(!health.MissingAt(1200), "live hook precedes raw input");
    health.Reset(1300);
    Check(!health.MissingAt(1301), "reinstallation rearms health");
    health.Reset(0xffffff00u);
    Check(health.MissingAt(1000), "hook health handles timestamp wrap");
  }
  {
    MenuMaskTracker t;
    t.OnWatchedDown();
    Check(t.OnWatchedUp(), "alone: down then up sends the mask");
  }
  {
    MenuMaskTracker t;
    t.OnWatchedDown();
    t.OnOtherKeyDown();
    Check(!t.OnWatchedUp(), "other key during the hold: no mask");
  }
  {
    MenuMaskTracker t;
    t.OnWatchedDown();
    t.OnOtherKeyDown();
    t.OnOtherKeyDown();
    Check(!t.OnWatchedUp(), "several other keys during the hold: no mask");
  }
  {
    MenuMaskTracker t;
    t.OnWatchedDown();
    Check(t.OnWatchedUp(), "one cycle sends once");
    Check(!t.OnWatchedUp(), "release without a press: no mask");
  }
  {
    MenuMaskTracker t;
    t.OnOtherKeyDown();
    t.OnWatchedDown();
    Check(t.OnWatchedUp(),
          "other key before the press does not count");
  }
  {
    MenuMaskTracker t;
    t.OnWatchedDown();
    t.OnWatchedDown();  // autorepeat while held
    Check(t.OnWatchedUp(), "autorepeat while held keeps the alone state");
  }
  {
    MenuMaskTracker t;
    t.OnWatchedDown();
    t.OnWatchedDown();
    t.OnOtherKeyDown();
    Check(!t.OnWatchedUp(),
          "autorepeat then other key: no mask");
  }
  {
    MenuMaskTracker t;
    t.OnWatchedDown();
    t.Reset();
    Check(!t.OnWatchedUp(), "reset ends the hold: no mask");
  }
  {
    MenuMaskTracker t;
    t.OnWatchedDown();
    t.OnWatchedUp();
    t.OnWatchedDown();
    t.OnOtherKeyDown();
    Check(!t.OnWatchedUp(), "second cycle with other key: no mask");
    t.OnWatchedDown();
    Check(t.OnWatchedUp(), "third cycle alone: mask again");
  }
  {
    MenuMaskTracker t;
    t.OnWatchedDown();
    t.OnOtherKeyDown();
    t.OnWatchedUp();
    t.OnOtherKeyDown();  // after the release: must not leak into the next hold
    t.OnWatchedDown();
    Check(t.OnWatchedUp(), "other key after a release does not leak");
  }

  std::printf("%d failure(s)\n", failures);
  return failures == 0 ? 0 : 1;
}
