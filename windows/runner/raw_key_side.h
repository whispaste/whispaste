#ifndef RUNNER_RAW_KEY_SIDE_H_
#define RUNNER_RAW_KEY_SIDE_H_

// Which physical modifier key a Raw Input keyboard event stands for.
//
// Raw Input reports Ctrl and Alt with the generic virtual keys (VK_CONTROL,
// VK_MENU) on both sides. The right-hand key carries the RI_KEY_E0 flag, so
// the side is read from that flag. Shift may arrive as VK_SHIFT; its side is
// in the scan code (0x36 right, 0x2A left). Win arrives side-specific.
//
// AltGr (right Alt on layouts such as German) also sends a synthetic Ctrl,
// before the Alt and again with every auto-repeat. Raw Input reports it as
// VK_CONTROL with the Alt scan code 0x38 and the E0 flag, so by the flag alone
// it would read as right Ctrl; a real Ctrl key has scan code 0x1D on both
// sides (measured on Windows 11 26H2 with a German keyboard, #263 F25-2).
//
// Pure C++17, free of Win32, so raw_key_side_test.cc runs on any host. The
// constants are the winuser.h values; keyboard_monitor_host.cpp asserts that.
#include <cstdint>

namespace raw_key_side {

constexpr uint16_t kShift = 0x10;
constexpr uint16_t kControl = 0x11;
constexpr uint16_t kMenu = 0x12;
constexpr uint16_t kLShift = 0xA0;
constexpr uint16_t kRShift = 0xA1;
constexpr uint16_t kLControl = 0xA2;
constexpr uint16_t kRControl = 0xA3;
constexpr uint16_t kLMenu = 0xA4;
constexpr uint16_t kRMenu = 0xA5;
constexpr uint16_t kFlagE0 = 0x02;  // RI_KEY_E0

constexpr uint16_t kAltScanCode = 0x38;
constexpr uint16_t kRightShiftScanCode = 0x36;

// The synthetic Ctrl of AltGr: part of the right Alt press, no Ctrl key.
inline bool IsAltGrCtrl(uint16_t vkey, uint16_t make_code) {
  return vkey == kControl && make_code == kAltScanCode;
}

// The side-specific virtual key of the event, the unchanged key for anything
// that is not Shift, Ctrl or Alt, and 0 for the AltGr Ctrl.
inline uint16_t SideSpecificVk(uint16_t vkey, uint16_t make_code,
                               uint16_t flags) {
  if (IsAltGrCtrl(vkey, make_code)) return 0;
  const bool e0 = (flags & kFlagE0) != 0;
  if (vkey == kControl) return e0 ? kRControl : kLControl;
  if (vkey == kMenu) return e0 ? kRMenu : kLMenu;
  if (vkey == kShift) {
    return make_code == kRightShiftScanCode ? kRShift : kLShift;
  }
  return vkey;
}

}  // namespace raw_key_side

#endif  // RUNNER_RAW_KEY_SIDE_H_
