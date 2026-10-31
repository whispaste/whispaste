// Runner-owned RawInput host that supplies global hotkey KEY-UP events on
// Windows (issue #39).
//
// Why this exists: the global hotkey is registered with RegisterHotKey (the
// hotkey_manager plugin), which only ever yields WM_HOTKEY on key-DOWN — there
// is no "hotkey up" message on Windows. That makes hold-to-talk (push-to-talk)
// impossible through the registrar alone.
//
// How it works WITHOUT taking over the hotkey: RawInput (RIDEV_INPUTSINK)
// observes keyboard transitions globally (never intercepting / swallowing
// keys, so RegisterHotKey still suppresses the keystroke and provides the
// key-down). Crucially, RegisterHotKey ALSO suppresses the hotkey key's DOWN
// from the RawInput stream — only its release is observable — so the main key
// cannot be learned by watching for a make. Instead Dart calls ArmRelease()
// the moment the hotkey fires; the host snapshots the non-modifier key that is
// physically down (GetAsyncKeyState) and reports `onKeyUp` when it is released.
//
// Channel: com.whispaste.keyboard_monitor
//   Dart → native:  start()  ·  armRelease()  ·  stop()  ·
//                    resolveLayoutLabel(vk)  ·  resolveLiveVirtualKey(scanCode)
//   native → Dart:  onKeyUp   (watched main key released; argument
//                    {pressMs} = how long it was held, or null if unknown)

#ifndef KEYBOARD_MONITOR_HOST_H_
#define KEYBOARD_MONITOR_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>

#include "menu_mask.h"

class KeyboardMonitorHost {
 public:
  KeyboardMonitorHost(flutter::FlutterEngine* engine, HWND owner);
  ~KeyboardMonitorHost();

  KeyboardMonitorHost(const KeyboardMonitorHost&) = delete;
  KeyboardMonitorHost& operator=(const KeyboardMonitorHost&) = delete;

  // Called by FlutterWindow's message handler for WM_INPUT.
  void HandleRawInput(HRAWINPUT raw_input);

  // Called by FlutterWindow's message handler for WM_HOTKEY (observed only).
  // Records when the hotkey's key went down, so the release can be timed.
  void HandleHotkeyDown(LPARAM lparam);

  void Destroy();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Registers/unregisters this window for RawInput keyboard observation.
  bool EnsureRawInputRegistered();
  void UnregisterRawInput();

  // Menu mask after a Win- or Alt-only hold (see menu_mask.h). Sent only from
  // the low-level keyboard hook, never from the RawInput path.
  void SendMenuMask();

  // The low-level hook exists only while Win or Alt is the watched modifier.
  // It is installed and removed here; UpdateMenuMaskHook() reconciles the
  // state with watched_mod_vk_.
  void UpdateMenuMaskHook();
  void UninstallMenuMaskHook();
  static LRESULT CALLBACK MenuMaskHookProc(int code, WPARAM wparam,
                                           LPARAM lparam);
  void OnMenuMaskHookKey(WPARAM wparam, const KBDLLHOOKSTRUCT& key);

  // Snapshots the currently-held non-modifier key as the one whose release
  // ends the hold (see header comment). `hotkey_mods` are the hotkey's modifier
  // bits from Dart; they define the combination that must stay intact.
  // Returns whether the armed main key is still held. False means it was
  // already up at the snapshot, so no release will come.
  bool ArmRelease(uint8_t hotkey_mods);

  // Repeat mask for the armed main key. While a hold session is armed, the
  // main key's key-DOWNs are swallowed, so once the hotkey's modifiers are
  // released the auto-repeat of the still-held key (e.g. AltGr+ö released
  // before ö) never reaches the focused app. Key-ups pass through so the
  // RawInput release still ends the session. The hook exists only between
  // ArmRelease() and that release.
  void UpdateRepeatMaskHook();
  void UninstallRepeatMaskHook();
  static LRESULT CALLBACK RepeatMaskHookProc(int code, WPARAM wparam,
                                             LPARAM lparam);
  bool SwallowsRepeat(WPARAM wparam, const KBDLLHOOKSTRUCT& key);
  // Ends the repeat mask for the armed session: no more swallowing, hook removed.
  void EndRepeatSession();
  // Largest gap between two key-downs of one held key that still counts as
  // auto-repeat, from the system keyboard delay and speed.
  static DWORD RepeatGapLimitMs();
  // Bitmask of the hotkey modifiers held (see kArmedCtrl…) right now.
  static uint8_t HeldModifierMask();

  // Resolves the character the given Windows virtual-key produces on the ACTIVE
  // keyboard layout, unmodified (e.g. US `;` VK_OEM_1 → "ö" on a German layout).
  // Lets the hotkey recorder show the real key (Ö/Ä/Ü) instead of the canonical
  // US label that Flutter reports when a Ctrl/AltGr modifier is held (#39).
  // Returns "" when the key has no character (function keys etc.).
  std::string ResolveLayoutLabel(int vk);

  // Resolves the Windows virtual-key that the ACTIVE keyboard layout assigns
  // to a hardware scan code, right now. Windows layout drivers reassign the
  // VK_OEM_* codes to different physical keys per layout (e.g. the German
  // driver maps the physical "#" key, scan code 0x2B, to VK_OEM_2 — not
  // VK_OEM_5 as the US layout does) — this is a live OS query rather than a
  // hardcoded table, so it is correct for every layout, not just German
  // (issue #108). Returns 0 when the scan code has no live mapping.
  int ResolveLiveVirtualKey(int scan_code);

  flutter::FlutterEngine* engine_;
  HWND owner_;
  bool destroyed_ = false;
  bool raw_input_registered_ = false;

  // Virtual-key of the armed main key (0 = not armed). Set by ArmRelease(); its
  // release (break) fires `onKeyUp`.
  USHORT watched_vk_ = 0;

  // Press timing. The hotkey's WM_HOTKEY gives its virtual key and the time it
  // went down (GetMessageTime). ArmRelease() keeps that time when the armed key
  // is the hotkey key, and the release's WM_INPUT gives the time it went up.
  // Both are message times, so a UI thread that is busy when the release is
  // processed does not stretch the press.
  USHORT hotkey_vk_ = 0;
  DWORD hotkey_down_ms_ = 0;
  bool armed_down_known_ = false;
  DWORD armed_down_ms_ = 0;

  // Virtual-key of a watched modifier-only hotkey (0 = none). Pass-through
  // only: every make/break of this key fires `onModifierDown` / `onModifierUp`,
  // and any non-modifier make fires `onOtherKey`. Gesture decisions stay in
  // Dart (HotkeyGestureMachine).
  USHORT watched_mod_vk_ = 0;

  // Decides whether a Win- or Alt-only release must be masked (PAR-036). Fed
  // only by the low-level hook, which sees the Win release before the shell.
  MenuMaskTracker menu_mask_;

  // Installed WH_KEYBOARD_LL hook (nullptr = not installed). The hook callback
  // has no user data argument, so it reaches the owning host via this pointer.
  HHOOK menu_mask_hook_ = nullptr;
  static KeyboardMonitorHost* menu_mask_owner_;

  // Installed WH_KEYBOARD_LL hook for the repeat mask (nullptr = not
  // installed). Separate from menu_mask_hook_, so each hook is installed only
  // while its own feature is active.
  HHOOK repeat_mask_hook_ = nullptr;
  // Modifiers held when the session was armed. Repeats are swallowed only once
  // one of them has been released, so the hotkey's own key-down (with its
  // modifiers still held) is never touched.
  uint8_t armed_mods_ = 0;
  // Time of the last key-down of the armed main key (KBDLLHOOKSTRUCT::time),
  // and the gap limit computed at arm time. A key-down after a longer gap is a
  // new press whose key-up was lost, so the session ends.
  DWORD last_main_down_ms_ = 0;
  bool main_down_seen_ = false;
  DWORD repeat_gap_limit_ms_ = 0;
  static KeyboardMonitorHost* repeat_mask_owner_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // KEYBOARD_MONITOR_HOST_H_
