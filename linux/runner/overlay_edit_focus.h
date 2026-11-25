#ifndef RUNNER_OVERLAY_EDIT_FOCUS_H_
#define RUNNER_OVERLAY_EDIT_FOCUS_H_

// Keyboard focus of the recording overlay while the write preview's edit
// field is open (#254, D13/D21). The overlay never takes focus otherwise; for
// an edit session it accepts focus, is activated, and afterwards gives the
// focus back. Pure and free of GTK/X11 so overlay_edit_focus_test.cc runs on
// any host; floating_overlay_window.cc feeds it the X11 facts.

// Whether this session can hand the keyboard focus to the overlay and get it
// back with a confirmation. Plain X11 only: on a Wayland session WhisPaste
// runs under XWayland and cannot activate the (mostly native Wayland) target
// app again, so a paste after editing would land in the overlay itself (R7).
// A tiling WM gets an override-redirect overlay, which the WM never focuses
// or reports as active (positioned_window_type.h). Without the EWMH
// _NET_ACTIVE_WINDOW hint the return cannot be confirmed.
inline bool OverlayEditFocusSupported(bool x11_display, bool wayland_session,
                                      bool managed_toplevel,
                                      bool active_window_hint) {
  return x11_display && !wayland_session && managed_toplevel &&
         active_window_hint;
}

// Whether the overlay holds the edit focus for the snapshot it shows: a
// visible notice card whose edit field is open, on a session that supports it.
inline bool OverlayWantsEditFocus(bool supported, bool visible,
                                  bool edit_open) {
  return supported && visible && edit_open;
}

// The window to activate when an edit session ends: the window that was
// active before the overlay took the focus, but only while the overlay still
// has it (Esc, a closed card). After an insert the target app is active
// already, and a window the user chose meanwhile is left alone. 0: none.
inline unsigned long OverlayFocusRestoreWindow(unsigned long active,
                                               unsigned long own,
                                               unsigned long previous) {
  if (own == 0 || previous == 0 || previous == own) return 0;
  return active == own ? previous : 0;
}

#endif  // RUNNER_OVERLAY_EDIT_FOCUS_H_
