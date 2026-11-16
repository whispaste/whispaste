// Unit test for raw_key_side.h. Plain C++17, no Win32. The cases are the
// Raw Input events recorded on real hardware for #263 (F13-1, F25-2):
// virtual key, scan code and flags exactly as GetRawInputData returned them.
// The injected Ctrl (scan code 0) comes from a SendInput self-test on the
// same machine; Win and Q were recorded from the keyboard.
#include "raw_key_side.h"

#include <cstdint>
#include <cstdio>

namespace {

using namespace raw_key_side;

constexpr uint16_t kBreak = 0x01;  // RI_KEY_BREAK
constexpr uint16_t kLWin = 0x5B;
constexpr uint16_t kQ = 0x51;

int failures = 0;

void Check(bool ok, const char* what) {
  std::printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

}  // namespace

int main() {
  Check(SideSpecificVk(kShift, 0x2A, 0) == kLShift, "left Shift");
  Check(SideSpecificVk(kShift, 0x36, 0) == kRShift, "right Shift");
  Check(SideSpecificVk(kControl, 0x1D, 0) == kLControl, "left Ctrl");
  Check(SideSpecificVk(kControl, 0x1D, kFlagE0) == kRControl, "right Ctrl");
  Check(SideSpecificVk(kMenu, 0x38, 0) == kLMenu, "left Alt");
  Check(SideSpecificVk(kMenu, 0x38, kFlagE0) == kRMenu, "right Alt (AltGr)");
  Check(SideSpecificVk(kControl, 0x1D, kFlagE0 | kBreak) == kRControl,
        "the release keeps the side");

  // The synthetic Ctrl of AltGr, on press, auto-repeat and release.
  Check(IsAltGrCtrl(kControl, 0x38), "AltGr Ctrl is recognised");
  Check(SideSpecificVk(kControl, 0x38, kFlagE0) == 0,
        "AltGr Ctrl is not right Ctrl");
  Check(SideSpecificVk(kControl, 0x38, kFlagE0 | kBreak) == 0,
        "AltGr Ctrl release is not right Ctrl either");
  Check(!IsAltGrCtrl(kControl, 0x1D), "a real Ctrl is no AltGr Ctrl");
  Check(!IsAltGrCtrl(kMenu, 0x38), "the AltGr key itself is no AltGr Ctrl");

  // Injected Ctrl (SendInput without a scan code, e.g. the app's own paste).
  Check(SideSpecificVk(kControl, 0x00, 0) == kLControl,
        "injected Ctrl stays left Ctrl");

  Check(SideSpecificVk(kLWin, 0x5B, kFlagE0) == kLWin, "Win passes through");
  Check(SideSpecificVk(kQ, 0x10, 0) == kQ, "a letter passes through");

  if (failures > 0) {
    std::printf("raw_key_side_test: %d failed\n", failures);
    return 1;
  }
  std::printf("raw_key_side_test: all passed\n");
  return 0;
}
