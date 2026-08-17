#ifndef FLUTTER_SNIPPET_PICKER_WINDOW_H_
#define FLUTTER_SNIPPET_PICKER_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Fixed panel size in logical (GTK application) pixels — identical across
// macOS/Windows/Linux, part of the cross-platform shell contract (see
// snippet_picker_controller_interface.dart). Unlike the Windows shell, GTK
// window sizes are already expressed in application pixels; GDK applies the
// per-monitor scale factor itself, so no manual DPI math is needed here.
constexpr int kSnippetPickerWidth = 360;
constexpr int kSnippetPickerHeight = 420;

// Lifecycle-only decorationless GtkWindow that hosts the second Flutter
// engine for the Snippet-Picker (ADR 0002 phase 2, Linux — visual-refresh-2026
// ticket 30).
//
// Differs from FloatingButtonWindow/FloatingOverlayWindow in exactly the ways
// the picker needs to be usable: GDK_WINDOW_TYPE_HINT_UTILITY (a normal,
// WM-managed window — NOT override-redirect) and accept_focus=TRUE, so the
// window manager tracks it in the regular focus stack and hands focus back to
// whatever was focused before it when it is hidden/withdrawn — the same
// "closing a dialog returns focus" behaviour every EWMH-compliant WM
// implements. SnippetPickerHost still does its own explicit XGetInputFocus/
// XSetInputFocus save-restore around Show()/Dismiss() as a belt-and-suspenders
// fallback (see that file's comment) rather than relying on this alone.
class SnippetPickerWindow {
 public:
  SnippetPickerWindow();
  ~SnippetPickerWindow();

  SnippetPickerWindow(const SnippetPickerWindow&) = delete;
  SnippetPickerWindow& operator=(const SnippetPickerWindow&) = delete;

  // Creates the GtkWindow, boots the 2nd Flutter engine, realizes the shell.
  // Must be called before any other method. Call at most once.
  void Create();

  // Returns the binary messenger of the 2nd engine so the host can open the
  // private render channel (com.whispaste.snippet_picker_render).
  FlBinaryMessenger* GetRenderMessenger();

  // Move the shell to absolute screen coordinates (X11 root, top-left
  // origin). Reliable only when GDK_BACKEND=x11 is in effect (see main.cc).
  void MoveTo(int x, int y);

  // Show the shell window, grab keyboard focus (SetFocus-equivalent —
  // gtk_widget_show + gtk_window_present so the WM actually activates it,
  // not just maps it).
  void Show();

  // Hide the shell window (gtk_widget_hide — withdraws it from the WM's
  // mapped-window list, which is what triggers focus-return on well-behaved
  // WMs).
  void Hide();

  void Destroy();

  bool IsCreated() const { return window_ != nullptr; }

  GtkWidget* GetGtkWindow() const { return window_; }

  // Fired when the shell loses keyboard focus while visible (WM activated a
  // different window) — the host treats this as "click outside", mirroring
  // WM_ACTIVATE/WA_INACTIVE on Windows and the NSWindow resignKey path on
  // macOS.
  using OnFocusLostCallback = void (*)(void* user_data);
  void SetOnFocusLost(OnFocusLostCallback cb, void* user_data);

 private:
  GtkWidget* window_ = nullptr;
  FlView* fl_view_ = nullptr;  // Non-owning; container holds the ref.

  OnFocusLostCallback on_focus_lost_cb_ = nullptr;
  void* on_focus_lost_user_data_ = nullptr;

  static gboolean OnFocusOutEvent(GtkWidget* widget, GdkEventFocus* event,
                                  gpointer user_data);
};

#endif  // FLUTTER_SNIPPET_PICKER_WINDOW_H_
