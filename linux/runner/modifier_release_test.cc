// Unit test for modifier_release.h. Plain C++17, no X11/GLib/evdev.
#include "modifier_release.h"

#include <cstdio>
#include <optional>
#include <vector>

namespace {

int failures = 0;

void Check(bool ok, const char* what) {
  std::printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

using std::chrono::milliseconds;

// Answers the given states in order, then repeats the last one.
struct Script {
  std::vector<std::optional<bool>> states;
  size_t calls = 0;
  std::optional<bool> operator()() {
    const size_t i = calls < states.size() ? calls : states.size() - 1;
    calls++;
    return states[i];
  }
};

}  // namespace

int main() {
  {
    Script s{{false}};
    int sleeps = 0;
    const auto r = WaitForModifierRelease(
        std::ref(s), milliseconds(500), [&](milliseconds) { sleeps++; });
    Check(r == ModifierWait::kNoneHeld && sleeps == 0,
          "nothing held: no wait at all");
  }
  {
    Script s{{true, true, true, false}};
    milliseconds slept(0);
    const auto r = WaitForModifierRelease(
        std::ref(s), milliseconds(500), [&](milliseconds d) { slept += d; });
    Check(r == ModifierWait::kNoneHeld && slept == milliseconds(30),
          "a held Alt is waited out, in 10 ms steps");
  }
  {
    Script s{{true}};
    milliseconds slept(0);
    const auto r = WaitForModifierRelease(
        std::ref(s), milliseconds(100), [&](milliseconds d) { slept += d; });
    Check(r == ModifierWait::kTimedOut && slept == milliseconds(100),
          "a key held for good stops the wait at max_wait");
  }
  {
    Script s{{std::nullopt}};
    int sleeps = 0;
    const auto r = WaitForModifierRelease(
        std::ref(s), milliseconds(500), [&](milliseconds) { sleeps++; });
    Check(r == ModifierWait::kUnknown && sleeps == 0,
          "unknown key state: no wait");
  }
  {
    Script s{{true, std::nullopt}};
    const auto r = WaitForModifierRelease(
        std::ref(s), milliseconds(500), [](milliseconds) {});
    Check(r == ModifierWait::kUnknown, "a reader that goes blind ends the wait");
  }
  {
    Script s{{true}};
    const auto r = WaitForModifierRelease(
        std::ref(s), milliseconds(0), [](milliseconds) {});
    Check(r == ModifierWait::kTimedOut, "zero budget never sleeps");
  }
  std::printf(failures == 0 ? "ALL PASS\n" : "%d FAILURE(S)\n", failures);
  return failures == 0 ? 0 : 1;
}
