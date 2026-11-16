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
// keyboard focus, and a click outside it must be seen (on_focus_lost, which
// closes the picker, #1680) — the opposite design goal. Do not
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
// are expected to just work here.
//
// Live on-device testing (ticket 29's own AC) DID turn up a routing gap,
// confirmed via GetAsyncKeyState/GetGUIThreadInfo diagnostics: Down/Up-arrow
// key presses were delivered correctly at the OS level (focus on the
// FLUTTERVIEW child was always correct) but never reached the render
// engine's LogicalKeyboardKey stream, while typing, Enter and Escape all
// worked. `forward_to_flutter` (HandleTopLevelWindowProc, mirroring
// flutter_window.cpp's FlutterWindow::MessageHandler — every other native
// shell in this runner is deliberately non-activating/non-keyboard and never
// needed it) turned out NOT to fix this: WM_KEYDOWN is sent by Windows
// straight to whichever HWND has keyboard focus, which is `flutter_child_`
// (a separate window with the engine's own registered WndProc), never this
// shell's. HandleTopLevelWindowProc is still correct to forward (matches the
// official template, needed for IME/DPI/font-change messages the SHELL
// receives) but structurally can't see keystrokes at all.
//
// The actual fix: `SetWindowSubclass` directly on `flutter_child_` (see
// Create()/Destroy()), intercepting WM_KEYDOWN for VK_UP/VK_DOWN before
// Flutter's own WndProc ever sees them and driving `on_navigate` instead —
// the same native-intercept pattern SnippetPickerHost.swift already uses for
// Escape/Return on macOS, applied at the one Windows-specific layer
// (LogicalKeyboardKey.arrowUp/Down) where the ordinary channel provably
// doesn't reach the render engine. Escape/Enter/typing are unaffected and
// keep using the normal channel — this narrow gap is Down/Up-arrow only.

#ifndef SNIPPET_PICKER_WINDOW_H_
#define SNIPPET_PICKER_WINDOW_H_

#include <windows.h>

#include <commctrl.h>
#include <dwmapi.h>

#include <functional>
#include <optional>

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

  // Fired while shown when the shell loses activation (WM_ACTIVATE /
  // WA_INACTIVE) or a mouse button goes down outside it (#1680).
  // |outside_click| tells the two apart: true when a button is down with the
  // cursor outside the shell, false for a focus change without a click (a
  // notification, another app raising itself, Alt+Tab). The owner
  // (SnippetPickerHost) only reports it; Dart decides, and only a click
  // outside closes the picker. A focus change without a click is followed
  // by the poll below, so a later click outside still arrives here.
  std::function<void(bool outside_click)> on_focus_lost;

  // Opt-in click poll (see StartClickPoll): the snippet picker turns it on,
  // the tray panel (which reuses this shell and closes on any focus loss)
  // leaves it off. Set before Show().
  bool poll_outside_clicks = false;

  // Forwarded to the render engine's FlutterViewController::
  // HandleTopLevelWindowProc before this window's own message handling (see
  // the file comment above) — lets the embedder's keyboard/IME/DPI handling
  // see every message this shell receives, the same as FlutterWindow does
  // for the main window. A returned value means Flutter consumed the
  // message; nullopt falls through to this window's own handling.
  std::function<std::optional<LRESULT>(HWND, UINT, WPARAM, LPARAM)>
      forward_to_flutter;

  // Fired from the flutter_child_ subclass on VK_UP/VK_DOWN with -1/+1 —
  // see the file comment. The owner (SnippetPickerHost) relays this to the
  // render engine as a `moveHighlight` render-channel call.
  std::function<void(int delta)> on_navigate;

 private:
  static bool EnsureClassRegistered();
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
  LRESULT HandleMessage(UINT msg, WPARAM wp, LPARAM lp);

  // Subclass proc installed on flutter_child_ — intercepts WM_KEYDOWN for
  // VK_UP/VK_DOWN (see file comment) and lets everything else fall through
  // to Flutter's own WndProc via DefSubclassProc.
  static LRESULT CALLBACK ChildSubclassProc(HWND hwnd, UINT msg, WPARAM wp,
                                            LPARAM lp, UINT_PTR subclass_id,
                                            DWORD_PTR ref_data);

  void ApplyChildSize(int pwidth, int pheight);

  // Click-outside detection that does not depend on activation (#1680): a
  // click into a window that does not take activation, or a second click
  // after the picker already lost focus without one, never produces another
  // WA_INACTIVE. A short timer polls the physical button state while shown;
  // a low-level mouse hook would see every click too, but it runs on this
  // UI thread and stalls the whole system's mouse whenever that thread is
  // busy, so polling is the safer trade.
  static bool AnyMouseButtonDown();
  bool CursorOutside() const;
  void StartClickPoll();
  void StopClickPoll();
  bool button_was_down_ = false;

  static bool class_registered_;

  HWND hwnd_ = nullptr;
  HWND owner_ = nullptr;
  HWND flutter_child_ = nullptr;

  bool visible_ = false;
  bool shutting_down_ = false;
};

#endif  // SNIPPET_PICKER_WINDOW_H_
