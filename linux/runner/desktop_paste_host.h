#ifndef FLUTTER_DESKTOP_PASTE_HOST_H_
#define FLUTTER_DESKTOP_PASTE_HOST_H_

#include <flutter_linux/flutter_linux.h>

#include <string>

// Owns the public MethodChannel com.whispaste.desktop_paste and bridges it to
// a virtual /dev/uinput keyboard (visual-refresh-2026 ticket 30).
//
// Unlike the macOS (CGEvent/AX) and Windows (SendInput+SetForegroundWindow)
// bridges, Linux input injection goes through the kernel's uinput subsystem:
// we register a virtual USB keyboard with the kernel and emit real EV_KEY
// events on it. The compositor/X server sees this exactly like a physical
// keyboard press — it always lands on whatever currently holds input focus.
//
// This has one structural consequence that shapes the whole class: uinput has
// no concept of a "target window" at all (there is no window handle to
// capture, bring to front, or attach thread input to). `CaptureTarget()` is
// therefore a documented no-op that always reports success — the real
// precondition for a correct paste is "the intended app still has focus when
// the shortcut fires", which is guaranteed for the direct dictation flow (the
// floating button never steals focus) and is the Snippet-Picker's own
// responsibility to restore (native X11 focus save/restore in
// SnippetPickerHost — see its file comment) before this class is invoked.
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

  // Emits a Ctrl+V key-down/key-up burst on the virtual keyboard. Returns
  // false if uinput isn't available or a write() failed partway through.
  bool SendPasteShortcut();

  FlValue* CheckCapability();
  FlValue* PasteClipboard(int delay_ms);
  FlValue* TypeText(const std::string& text, int delay_ms);
  FlValue* DiagnosticPaste(const std::string& demo_text);

  // uinput virtual keyboard fd, or -1 if not (yet) created.
  int uinput_fd_ = -1;
};

#endif  // FLUTTER_DESKTOP_PASTE_HOST_H_
