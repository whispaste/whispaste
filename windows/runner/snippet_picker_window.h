// Thin focusable Win32 WS_POPUP shell for the Snippet-Picker (ticket 29,
// visual-refresh-2026).
//
// Structural precedent: floating_button_window.{h,cpp} (ADR 0002 Phase 2 —
// second-Flutter-engine shell). Behavioral precedent:
// macos/Runner/SnippetPickerHost.swift.
//
// Unlike FloatingButtonWindow (deliberately non-activating / click-through,
// WS_EX_NOACTIVATE + MA_NOACTIVATE + HTTRANSPARENT hit-testing), this shell
// IS a normal focusable popup: the embedded Flutter search field needs real
// keyboard focus, and losing that focus to a window outside the process
// (click-outside) must cancel the picker — the opposite design goal. Do not
// copy those three mechanisms from the floating button.
//
// No native Escape/Return key interception: unlike the macOS shell (whose
// AppKit text-input-proxy view doesn't reliably forward Escape/Return
// through the normal responder chain — see SnippetPickerHost.swift's
// installEscapeMonitor/installReturnMonitor docs), Windows' Flutter embedder
// delivers raw key events to a focused text field through the ordinary
// keyboard channel, the same path every other WhisPaste text input on
// Windows already relies on. The render engine's own `Shortcuts`/`Actions`
// (Escape → `cancel`) and the search field's `onSubmitted` (Enter → select)
// are expected to just work here. Flagged for confirmation during the
// mandatory on-device verification pass (ticket 29's own AC) — if a Windows-
// specific routing gap turns up live, add the native intercept then, the
// same way the macOS file was hardened through several rounds of live tests.

#ifndef SNIPPET_PICKER_WINDOW_H_
#define SNIPPET_PICKER_WINDOW_H_

#include <windows.h>

#include <dwmapi.h>

#include <functional>

class SnippetPickerWindow {
 public:
  SnippetPickerWindow();
  ~SnippetPickerWindow();

  SnippetPickerWindow(const SnippetPickerWindow&) = delete;
  SnippetPickerWindow& operator=(const SnippetPickerWindow&) = delete;

  // |owner| is the main Flutter HWND (kept only for parity with
  // FloatingButtonWindow's constructor shape; no Win32 parent relationship
  // is created — see Create()'s body). |px|/|py|/|pwidth|/|pheight| are the
  // shell's initial position/size in PHYSICAL pixels, already DPI-resolved
  // and monitor-clamped by the caller (SnippetPickerHost owns that math,
  // since it must pick the DPI of the cursor's monitor before any window
  // exists there — see SnippetPickerHost::ComputePanelRect). |flutter_child|
  // is the render engine's view HWND.
  bool Create(HWND owner, int px, int py, int pwidth, int pheight,
              HWND flutter_child);
  void Destroy();

  // SW_SHOW + activate + SetFocus on the Flutter child (unlike the floating
  // button's SW_SHOWNOACTIVATE) — the picker must take keyboard focus
  // immediately for the search field to be usable without a manual click.
  //
  // Activation uses the same AttachThreadInput-fallback dance as
  // DesktopPasteHost::BringTargetToForeground(): a plain SetForegroundWindow
  // can be silently refused by Windows' foreground-lock (no recent input to
  // this process — e.g. the picker opening at the end of a voice-only
  // dictation flow, not from a RegisterHotKey keydown) and returns FALSE
  // without raising an error, which would otherwise leave a visible but
  // keyboard-dead panel. Checked, not assumed.
  void Show();
  void Hide();

  // Repositions/resizes the existing shell in physical pixels (same
  // pre-resolved-by-caller contract as Create()) — used on every re-show
  // since the cursor may now be on a different, differently-scaled monitor.
  void SetPhysicalRect(int px, int py, int pwidth, int pheight);

  bool visible() const { return visible_; }
  HWND hwnd() const { return hwnd_; }

  // Fired when the shell's own WM_ACTIVATE reports WA_INACTIVE — i.e. some
  // other window (outside this process) just took activation away, the
  // click-outside case. The owner (SnippetPickerHost) treats this exactly
  // like a cancel and is itself responsible for re-entrancy (its own
  // is_dismissing_ guard — see SnippetPickerHost::Dismiss), so this callback
  // may safely fire during the shell's own Hide().
  std::function<void()> on_deactivate_cancel;

 private:
  static bool EnsureClassRegistered();
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
  LRESULT HandleMessage(UINT msg, WPARAM wp, LPARAM lp);

  void ApplyChildSize(int pwidth, int pheight);

  static bool class_registered_;

  HWND hwnd_ = nullptr;
  HWND owner_ = nullptr;
  HWND flutter_child_ = nullptr;

  bool visible_ = false;
  bool shutting_down_ = false;
};

#endif  // SNIPPET_PICKER_WINDOW_H_
