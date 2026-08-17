#ifndef FLUTTER_SNIPPET_PICKER_HOST_H_
#define FLUTTER_SNIPPET_PICKER_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <string>
#include <vector>

#include "snippet_picker_window.h"

// Owns the public MethodChannel com.whispaste.snippet_picker and bridges it
// to the private render channel on the second engine
// (com.whispaste.snippet_picker_render) — visual-refresh-2026 ticket 30.
//
// Architecture mirrors FloatingButtonHost (Linux) and SnippetPickerHost.swift
// / SnippetPickerHost (Windows):
//
//   main engine  ←→  SnippetPickerHost  ←→  SnippetPickerWindow
//        ↕              (relay / translate)        ↕
//  public channel                          render channel (2nd engine)
//
// Fixed 360×420 logical-pixel panel, positioned by reading the CURRENT
// cursor position natively (never passed from Dart — see
// snippet_picker_controller_interface.dart's file comment for the historical
// vertical-mirror bug this avoids) and clamped into the cursor's monitor
// work area.
//
// ── Why this class does its own X11 focus save/restore ──────────────────────
//
// Unlike macOS (previousFrontApp/restorePreviousFrontApp) and Windows (no
// restore needed at all — DesktopPasteHost::BringTargetToForeground()
// re-activates its own captured target HWND regardless of current foreground
// state), Linux's Auto-Paste bridge (DesktopPasteHost, uinput-based) has no
// window-targeting concept whatsoever: it just emits Ctrl+V on a virtual
// keyboard, which lands on whatever the compositor currently considers
// focused. SnippetPickerWindow uses a normal WM-managed, focusable window
// (GDK_WINDOW_TYPE_HINT_UTILITY, accept_focus=TRUE — see its class comment)
// specifically so window managers' default "closing/hiding a window returns
// focus to what was focused before it" behaviour applies automatically. This
// class ALSO does an explicit XGetInputFocus/XSetInputFocus save-restore
// around Show()/Dismiss() as a belt-and-suspenders fallback for window
// managers or edge cases where the automatic behaviour doesn't fire in time
// — the same "capture before, restore after" shape as the macOS/Windows
// mechanisms, just implemented with raw Xlib since GDK exposes no portable
// equivalent.
//
// COMPILE RISK / residual limitation: XGetInputFocus/XSetInputFocus only see
// and control X11 (including XWayland) clients. A target application running
// as a *native* Wayland client (not XWayland) has no X11 window ID visible
// to this mechanism at all — restoring focus to it is then left entirely to
// the WM's own hide/withdraw-driven focus history. This is a real gap, not
// hidden: if it manifests, the clipboard still holds the picked snippet's
// text (Auto-Paste's own no-op-on-failure clipboard-preserving behaviour), so
// a manual Ctrl+V after clicking the target still works — degraded, not
// silently lost. main.cc forces GDK_BACKEND=x11 for this whole process
// (self only) so this class's OWN window is always a real X11 window; that
// says nothing about what other apps on the desktop are running as.
class SnippetPickerHost {
 public:
  explicit SnippetPickerHost(FlBinaryMessenger* main_messenger);
  ~SnippetPickerHost();

  SnippetPickerHost(const SnippetPickerHost&) = delete;
  SnippetPickerHost& operator=(const SnippetPickerHost&) = delete;

 private:
  // ── Public channel (main engine) ─────────────────────────────────────────
  FlMethodChannel* channel_ = nullptr;

  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* method_call,
                            gpointer user_data);
  void HandleMethodCall(FlMethodCall* method_call);

  // ── Picker window + render channel (2nd engine) ───────────────────────────
  SnippetPickerWindow* window_ = nullptr;
  FlMethodChannel* render_channel_ = nullptr;

  // Boot-race cache: the 2nd engine's Dart handler is not live until "ready"
  // fires. Cache the last item list here and flush on ready (mirrors
  // FloatingButtonHost's pending_state_ pattern and the Windows/macOS hosts).
  bool render_ready_ = false;
  bool has_pending_items_ = false;
  FlValue* pending_items_ = nullptr;  // Owned; a Flutter list of maps.

  void EnsureWindowAndEngine();
  void OpenRenderChannel();

  // Computes the panel's top-left in root-window coordinates from the
  // CURRENT cursor position, clamped into that cursor's monitor work area.
  static void ComputePanelOrigin(int* x, int* y);

  void Show(FlValue* items);
  // is_dismissing_ guards against re-entrant Dismiss() calls (e.g. the WM's
  // focus-out firing while a selectItem-triggered Dismiss is already
  // unwinding) — mirrors SnippetPickerHost.swift's isDismissing.
  bool is_dismissing_ = false;
  void Dismiss(bool fire_cancelled);

  // ── X11 focus save/restore (see class comment) ───────────────────────────
  void SaveFocusedWindow();
  void RestoreFocusedWindow();
  unsigned long saved_focus_window_ = 0;  // X11 Window, or None (0).

  static void OnWindowFocusLost(void* user_data);

  // ── Render channel handler (2nd engine → host) ────────────────────────────
  static void OnRenderMethodCall(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data);
  void HandleRenderMethodCall(FlMethodCall* method_call);
  void RelayPendingItems();

  // ── Helpers ───────────────────────────────────────────────────────────────
  void InvokeMainChannel(const char* method, FlValue* args);
  void InvokeRenderChannel(const char* method, FlValue* args);

  static void OnInvokeDone(GObject* source, GAsyncResult* result,
                            gpointer user_data);
};

#endif  // FLUTTER_SNIPPET_PICKER_HOST_H_
