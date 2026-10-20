#ifndef FLUTTER_DESKTOP_PASTE_HOST_H_
#define FLUTTER_DESKTOP_PASTE_HOST_H_

#include <flutter_linux/flutter_linux.h>

#include <chrono>
#include <memory>
#include <string>

#include "clipboard_receipt.h"
class PortalRemoteDesktop;

// Owns the public MethodChannel com.whispaste.desktop_paste and bridges it to
// a virtual /dev/uinput keyboard (visual-refresh-2026 ticket 30).
//
// Unlike the macOS (CGEvent/AX) and Windows (SendInput+SetForegroundWindow)
// bridges, Linux input injection goes through the kernel's uinput subsystem:
// we register a virtual USB keyboard with the kernel and emit real EV_KEY
// events on it. The compositor/X server sees this exactly like a physical
// keyboard press — it always lands on whatever currently holds input focus.
//
// uinput has no window handle of its own: the shortcut goes to whatever holds
// input focus when it fires. `captureTarget` records the focused X11 window
// (`CaptureTargetWindow`) for the block list and app profiles (WM_CLASS), and
// `pasteClipboard` checks it again (PAR-032): a target that lost focus is
// brought back with an EWMH `_NET_ACTIVE_WINDOW` request, as Windows does with
// SetForegroundWindow. One that closed or does not come back is refused with
// `target_changed`, so the text stays on the clipboard. Under Wayland nothing
// is captured: the block list fails closed and the paste goes to the focused
// window unchecked, which the settings point out.
// The Snippet-Picker restores focus itself (native X11 focus save/restore in
// SnippetPickerHost, see its file comment) before this class is invoked.
//
// The paste delay never blocks the GTK main thread (XP-7-14): it runs as a
// 10 ms poll, so frames and selection requests keep flowing. A target that
// still has focus only waits until the hotkey's modifiers are up, bounded by
// the delay, as on macOS. The transcript goes on the clipboard as a receipt
// write (`ClipboardReceipt`, GR-015), so Dart learns when the target read it.
//
// `typeText` mirrors the Windows bridge's decision to route through
// clipboard+paste rather than synthesizing per-character keycodes: uinput key
// codes are interpreted by the compositor via the *active keyboard layout*,
// so there is no reliable layout-independent way to inject arbitrary Unicode
// text as raw key events (same failure class documented in
// DesktopPasteHost::TypeText on Windows). Clipboard read/write uses GTK's
// synchronous clipboard API (already linked via PkgConfig::GTK).
class DesktopPasteHost {
 public:
  explicit DesktopPasteHost(FlBinaryMessenger* main_messenger);
  ~DesktopPasteHost();

  // Non-copyable.
  DesktopPasteHost(const DesktopPasteHost&) = delete;
  DesktopPasteHost& operator=(const DesktopPasteHost&) = delete;

  void Destroy();

 private:
  FlMethodChannel* channel_ = nullptr;
  bool destroyed_ = false;

  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* method_call,
                            gpointer user_data);
  void HandleMethodCall(FlMethodCall* method_call);

  // Lazily opens /dev/uinput and registers the virtual keyboard device.
  // Idempotent — safe to call before every paste. Returns false (and leaves
  // uinput_fd_ at -1) when the device can't be opened/created, which
  // `checkCapability` surfaces as `permission_missing` (missing udev
  // access) or `unsupported` (no /dev/uinput at all).
  bool EnsureUinputDevice();

  // Emits a Ctrl+V key-down/key-up burst on the virtual keyboard
  // (Ctrl+Shift+V with [shift]). Returns false if uinput isn't available or a
  // write() failed partway through.
  bool SendPasteShortcut(bool shift = false);

  // Emits Ctrl+<keycode> (Ctrl+Shift+<keycode> with [shift]) on the virtual
  // keyboard — shared by paste and copySelection; each passes the evdev code
  // of its letter on the active layout (LetterKeycode). Terminals bind
  // paste/copy to Ctrl+Shift; Dart decides per target (V1).
  bool SendCtrlShortcut(int keycode, bool shift = false);

  // Sends one shortcut through uinput, or through the portal's EIS keyboard
  // when [via_portal] is set.
  bool SendShortcut(int keycode, bool shift, bool via_portal);
  // portalInputConnect: the answer comes later from the portal callback, so
  // the call is kept until then (pending_connect_).
  void StartPortalConnect(FlMethodCall* method_call,
                          const std::string& restore_token);
  static void RespondConnect(FlMethodCall* method_call, const char* status,
                             const std::string& restore_token);

  // Evdev code of the key that types the letter [keyval] on the active keyboard
  // layout, or [fallback] when the layout has no such key (PAR-034).
  int LetterKeycode(guint keyval, int fallback);

  FlValue* CheckCapability();
  // Idle ages for the undo gate, or nullptr when the source is unavailable.
  FlValue* InputIdleSnapshot();
  // Focused X11 window at capture time (0: none, or no X11 display).
  void CaptureTargetWindow();
  // WM_CLASS instance name of the captured window, or nullptr when unknown.
  FlValue* TargetBundleId();
  // Answers [call] once the delay is over and the shortcut went out.
  void StartPaste(FlMethodCall* call, int delay_ms, bool via_portal,
                  bool shift);
  static gboolean OnPasteTick(gpointer user_data);
  // Sends the shortcut once the wait is over; false while still waiting.
  bool PasteTick();
  void FinishPaste(FlValue* result);
  FlValue* CopySelection(int delay_ms, bool via_portal, bool shift);
  FlValue* TypeText(const std::string& text, int delay_ms, bool via_portal,
                    bool shift);
  FlValue* DiagnosticPaste(const std::string& demo_text);

  // uinput virtual keyboard fd, or -1 if not (yet) created.
  int uinput_fd_ = -1;
  // X11 window that was focused at capture time; 0 when unknown (Wayland).
  unsigned long target_window_ = 0;

  // Read receipt of the transcript write (GR-015).
  std::unique_ptr<ClipboardReceipt> receipt_;

  // What the pending paste waits for before it sends the shortcut.
  enum class PasteWait {
    kDelay,       // The full delay: no target to check (Wayland, no EWMH).
    kModifiers,   // The target has focus: until the modifiers are up.
    kActivation,  // The target was brought back: the delay, then focus.
  };
  FlMethodCall* paste_call_ = nullptr;
  guint paste_timer_ = 0;
  PasteWait paste_wait_ = PasteWait::kDelay;
  std::chrono::steady_clock::time_point paste_started_{};
  int paste_delay_ms_ = 0;
  bool paste_via_portal_ = false;
  bool paste_shift_ = false;

  // Our own last synthetic key burst, for the undo gate's input check.
  std::chrono::steady_clock::time_point last_synthetic_key_{};
  bool has_synthetic_key_ = false;

  // Portal keyboard (RemoteDesktop v2), created on the first portalInputConnect.
  std::unique_ptr<PortalRemoteDesktop> portal_;
  // The portalInputConnect call waiting for the consent dialog, or nullptr.
  FlMethodCall* pending_connect_ = nullptr;
};

#endif  // FLUTTER_DESKTOP_PASTE_HOST_H_
