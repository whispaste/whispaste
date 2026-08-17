#include "snippet_picker_window.h"

#include <algorithm>

namespace {

constexpr const wchar_t kClassName[] = L"WHISPASTE_SNIPPET_PICKER_V1";

}  // namespace

bool SnippetPickerWindow::class_registered_ = false;

// ══════════════════════════════════════════════════════════════════════
// Window class registration
// ══════════════════════════════════════════════════════════════════════

bool SnippetPickerWindow::EnsureClassRegistered() {
  if (class_registered_) return true;
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kClassName;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  // No background brush — DWM / Flutter paints everything.
  wc.hbrBackground = nullptr;
  if (!RegisterClassExW(&wc)) return false;
  class_registered_ = true;
  return true;
}

// ══════════════════════════════════════════════════════════════════════
// Constructor / Destructor
// ══════════════════════════════════════════════════════════════════════

SnippetPickerWindow::SnippetPickerWindow() = default;
SnippetPickerWindow::~SnippetPickerWindow() { Destroy(); }

// ══════════════════════════════════════════════════════════════════════
// Create / Destroy
// ══════════════════════════════════════════════════════════════════════

bool SnippetPickerWindow::Create(HWND owner, int px, int py, int pwidth,
                                  int pheight, HWND flutter_child) {
  if (hwnd_) return true;

  if (!EnsureClassRegistered()) {
    OutputDebugStringW(L"[SnippetPicker] RegisterClassEx failed\n");
    return false;
  }

  owner_ = owner;
  flutter_child_ = flutter_child;

  // WS_EX_TOPMOST + WS_EX_TOOLWINDOW (no taskbar entry), deliberately
  // WITHOUT WS_EX_NOACTIVATE — see the header's file comment. No Win32
  // owner is set (matches FloatingButtonWindow) to avoid the owner window
  // auto-minimizing this shell when it is itself minimized.
  hwnd_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kClassName, L"",
                          WS_POPUP, px, py, pwidth, pheight, nullptr, nullptr,
                          GetModuleHandle(nullptr), this);

  if (!hwnd_) {
    OutputDebugStringW(L"[SnippetPicker] CreateWindowEx failed\n");
    return false;
  }

  // DWM sheet-of-glass transparency, same rationale as
  // FloatingButtonWindow::Create — composites the Flutter render engine's
  // own glass/blur painter over a transparent Win32 background instead of
  // opaque black.
  MARGINS m = {-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(hwnd_, &m);

  ApplyChildSize(pwidth, pheight);

  OutputDebugStringW(L"[SnippetPicker] Shell window created\n");
  return true;
}

void SnippetPickerWindow::Destroy() {
  if (shutting_down_) return;
  shutting_down_ = true;

  on_deactivate_cancel = nullptr;

  // Un-parent the Flutter child before destroying the shell so the Flutter
  // embedder can destroy it cleanly via its own controller teardown.
  if (flutter_child_ && IsWindow(flutter_child_)) {
    SetParent(flutter_child_, nullptr);
    flutter_child_ = nullptr;
  }

  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  visible_ = false;
  owner_ = nullptr;
  shutting_down_ = false;
}

// ══════════════════════════════════════════════════════════════════════
// Show / Hide
// ══════════════════════════════════════════════════════════════════════

void SnippetPickerWindow::Show() {
  if (!hwnd_ || shutting_down_) return;

  ShowWindow(hwnd_, SW_SHOW);
  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

  // Same AttachThreadInput fallback as
  // DesktopPasteHost::BringTargetToForeground() — a plain
  // SetForegroundWindow can be silently refused by Windows' foreground-lock
  // when this process has no recent input (e.g. the picker opening at the
  // end of a voice-only dictation flow). Checked, not assumed.
  HWND foreground = ::GetForegroundWindow();
  const DWORD foreground_thread =
      foreground ? ::GetWindowThreadProcessId(foreground, nullptr) : 0;
  const DWORD this_thread = ::GetWindowThreadProcessId(hwnd_, nullptr);

  bool attached = false;
  if (foreground_thread != 0 && this_thread != 0 &&
      foreground_thread != this_thread) {
    attached =
        ::AttachThreadInput(foreground_thread, this_thread, TRUE) != FALSE;
  }

  ::SetForegroundWindow(hwnd_);
  ::BringWindowToTop(hwnd_);
  ::SetActiveWindow(hwnd_);

  if (attached) {
    ::AttachThreadInput(foreground_thread, this_thread, FALSE);
  }

  if (flutter_child_) {
    ::SetFocus(flutter_child_);
  }

  visible_ = true;
}

void SnippetPickerWindow::Hide() {
  if (!hwnd_ || shutting_down_) return;
  ShowWindow(hwnd_, SW_HIDE);
  visible_ = false;
}

// ══════════════════════════════════════════════════════════════════════
// Position / size
// ══════════════════════════════════════════════════════════════════════

void SnippetPickerWindow::SetPhysicalRect(int px, int py, int pwidth,
                                           int pheight) {
  if (!hwnd_) return;
  SetWindowPos(hwnd_, nullptr, px, py, pwidth, pheight,
               SWP_NOZORDER | SWP_NOACTIVATE);
  ApplyChildSize(pwidth, pheight);
}

void SnippetPickerWindow::ApplyChildSize(int pwidth, int pheight) {
  if (!flutter_child_) return;
  LONG style = GetWindowLong(flutter_child_, GWL_STYLE);
  style = (style & ~(WS_OVERLAPPEDWINDOW | WS_CAPTION | WS_BORDER)) |
          WS_CHILD;
  SetWindowLong(flutter_child_, GWL_STYLE, style);
  SetParent(flutter_child_, hwnd_);
  SetWindowPos(flutter_child_, nullptr, 0, 0, pwidth, pheight,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

// ══════════════════════════════════════════════════════════════════════
// WndProc
// ══════════════════════════════════════════════════════════════════════

LRESULT CALLBACK SnippetPickerWindow::WndProc(HWND hwnd, UINT msg, WPARAM wp,
                                              LPARAM lp) {
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCT*>(lp);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    return TRUE;
  }
  auto* self = reinterpret_cast<SnippetPickerWindow*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self) return self->HandleMessage(msg, wp, lp);
  return DefWindowProcW(hwnd, msg, wp, lp);
}

LRESULT SnippetPickerWindow::HandleMessage(UINT msg, WPARAM wp, LPARAM lp) {
  if (shutting_down_) return DefWindowProcW(hwnd_, msg, wp, lp);

  switch (msg) {
    // ── Click-outside detection ───────────────────────────────────────
    // WA_INACTIVE fires when some other top-level window (outside this
    // process, or WhisPaste's own non-picker windows) takes activation
    // away. Only meaningful while shown — the shell also receives
    // WM_ACTIVATE/WA_INACTIVE as part of its own Hide()/Destroy(), which
    // on_deactivate_cancel's caller (SnippetPickerHost) is documented to
    // tolerate via its own re-entrancy guard, so no extra suppression here.
    case WM_ACTIVATE:
      if (LOWORD(wp) == WA_INACTIVE && visible_ && on_deactivate_cancel) {
        on_deactivate_cancel();
      }
      return DefWindowProcW(hwnd_, msg, wp, lp);

    // ── Display change (monitor plug/unplug) ──────────────────────────
    case WM_DISPLAYCHANGE:
      return 0;

    // ── No WM_PAINT needed — Flutter child paints everything ──────────
    case WM_PAINT: {
      PAINTSTRUCT ps;
      BeginPaint(hwnd_, &ps);
      EndPaint(hwnd_, &ps);
      return 0;
    }

    case WM_DESTROY:
      return 0;

    case WM_NCDESTROY:
      SetWindowLongPtrW(hwnd_, GWLP_USERDATA, 0);
      hwnd_ = nullptr;
      owner_ = nullptr;
      visible_ = false;
      flutter_child_ = nullptr;
      return 0;
  }

  return DefWindowProcW(hwnd_, msg, wp, lp);
}
