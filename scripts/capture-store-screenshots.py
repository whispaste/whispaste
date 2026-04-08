#!/usr/bin/env python3
"""
Real-window screenshot capture for WhisPaste (Windows).

Captures the running WhisPaste Flutter window with full chrome,
navigating to each app page via mouse automation on the sidebar.

Prerequisites:
    pip install mss pywin32 pyautogui Pillow

Usage:
    python scripts/capture-store-screenshots.py
    python scripts/capture-store-screenshots.py --pages history settings
    python scripts/capture-store-screenshots.py --all-pages --settle 2
"""

import argparse
import ctypes
import ctypes.wintypes
import sys
import time
from pathlib import Path

try:
    import mss
    import mss.tools
    import pyautogui
    import win32con
    import win32gui
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with: pip install mss pywin32 pyautogui Pillow")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = ROOT / "screenshots" / "raw"

# -- App layout constants (from lib/core/theme/tokens.dart + sidebar.dart) --
SIDEBAR_WIDTH = 72          # WpLayout.sidebarWidth
TITLE_BAR_HEIGHT = 64       # WpLayout.appBarHeight
STATUS_BAR_HEIGHT = 42      # WpLayout.statusBarHeight
NAV_ITEM_INNER = 42         # SizedBox height inside _NavItemWidget
NAV_ITEM_PAD = 8            # WpSpacing.xs vertical padding (top + bottom)
NAV_ITEM_HEIGHT = NAV_ITEM_INNER + 2 * NAV_ITEM_PAD  # 58px total per item
SETTINGS_BTN_HEIGHT = 42    # _SidebarSettingsButton SizedBox height
SETTINGS_BOTTOM_PAD = 16    # WpSpacing.md SizedBox below bottom items
NAV_ITEM_COUNT = 5          # history, replacements, analytics, about, feedback
SPACER_TOP_FLEX = 4
SPACER_BOTTOM_FLEX = 6

# -- Page definitions (order matches _navItems in app.dart) --
PAGES = [
    {"id": "history",      "label": "History",      "nav_index": 0},
    {"id": "replacements", "label": "Replacements", "nav_index": 1},
    {"id": "analytics",    "label": "Analytics",    "nav_index": 2},
    {"id": "about",        "label": "About",        "nav_index": 3},
    {"id": "feedback",     "label": "Feedback",     "nav_index": 4},
    {"id": "settings",     "label": "Settings",     "nav_index": -1},
]

DEFAULT_PAGES = ["history", "settings", "analytics", "about"]
WINDOW_TITLES = ["WhisPaste", "whispaste"]


def find_whispaste_window() -> int | None:
    """Find the WhisPaste main window handle."""
    result = []
    def enum_cb(hwnd, _):
        if not win32gui.IsWindowVisible(hwnd):
            return True
        title = win32gui.GetWindowText(hwnd)
        for pat in WINDOW_TITLES:
            if pat.lower() in title.lower():
                result.append((hwnd, title))
        return True
    win32gui.EnumWindows(enum_cb, None)
    if not result:
        return None
    result.sort(key=lambda x: (x[1] == "WhisPaste", len(x[1])), reverse=True)
    hwnd, title = result[0]
    print(f"  Found: '{title}' (hwnd=0x{hwnd:X})")
    return hwnd


def maximize_window(hwnd: int) -> None:
    """Maximize and bring window to foreground."""
    if win32gui.IsIconic(hwnd):
        win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
        time.sleep(0.5)
    win32gui.ShowWindow(hwnd, win32con.SW_MAXIMIZE)
    time.sleep(0.5)
    try:
        win32gui.SetForegroundWindow(hwnd)
    except Exception:
        try:
            import win32process, win32api
            fg = win32process.GetWindowThreadProcessId(win32gui.GetForegroundWindow())[0]
            me = win32api.GetCurrentThreadId()
            if fg != me:
                ctypes.windll.user32.AttachThreadInput(fg, me, True)
                win32gui.SetForegroundWindow(hwnd)
                ctypes.windll.user32.AttachThreadInput(fg, me, False)
        except Exception:
            pass
    time.sleep(0.5)


def get_window_rect(hwnd: int) -> tuple[int, int, int, int]:
    """Get accurate window rect using DWM extended frame bounds."""
    rect = ctypes.wintypes.RECT()
    hr = ctypes.windll.dwmapi.DwmGetWindowAttribute(
        hwnd, 9, ctypes.byref(rect), ctypes.sizeof(rect),
    )
    if hr == 0:
        return (rect.left, rect.top, rect.right, rect.bottom)
    return win32gui.GetWindowRect(hwnd)


def calc_nav_click_pos(hwnd: int, nav_index: int, is_settings: bool = False) -> tuple[int, int]:
    """Calculate screen coordinates for a sidebar nav item click.

    Sidebar Column layout:
      Spacer(flex:4)
      5x _NavItemWidget  (each 58px = 42 inner + 2x8 padding)
      Spacer(flex:6)
      _SidebarSettingsButton (42px)
      SizedBox(16px)

    The sidebar spans from title bar bottom to status bar top.
    """
    left, top, right, bottom = get_window_rect(hwnd)
    win_h = bottom - top

    click_x = left + SIDEBAR_WIDTH // 2

    # Sidebar vertical span
    sidebar_top = top + TITLE_BAR_HEIGHT
    sidebar_h = win_h - TITLE_BAR_HEIGHT - STATUS_BAR_HEIGHT

    # Fixed items total height
    nav_items_h = NAV_ITEM_COUNT * NAV_ITEM_HEIGHT  # 5 * 58 = 290
    bottom_fixed = SETTINGS_BTN_HEIGHT + SETTINGS_BOTTOM_PAD  # 42 + 16 = 58
    fixed_total = nav_items_h + bottom_fixed  # 348

    # Spacer heights
    flex_total = sidebar_h - fixed_total
    if flex_total < 0:
        flex_total = 0
    spacer_top_h = flex_total * SPACER_TOP_FLEX / (SPACER_TOP_FLEX + SPACER_BOTTOM_FLEX)

    if is_settings:
        # Settings button is after Spacer(6), at the bottom
        settings_top = sidebar_top + spacer_top_h + nav_items_h + (flex_total - spacer_top_h)
        click_y = int(settings_top + SETTINGS_BTN_HEIGHT / 2)
    else:
        # Nav items start after Spacer(4)
        first_item_top = sidebar_top + spacer_top_h
        item_top = first_item_top + nav_index * NAV_ITEM_HEIGHT
        click_y = int(item_top + NAV_ITEM_HEIGHT / 2)

    return (click_x, click_y)


def click_nav(hwnd: int, page: dict, debug: bool = False) -> None:
    """Click a sidebar nav item."""
    is_settings = page["id"] == "settings"
    x, y = calc_nav_click_pos(hwnd, page["nav_index"], is_settings)
    if debug:
        print(f"    Click ({x}, {y}) for '{page['label']}'")
    pyautogui.click(x, y)


def capture_window(hwnd: int, output_path: Path) -> bool:
    """Capture the window region to PNG."""
    left, top, right, bottom = get_window_rect(hwnd)
    w, h = right - left, bottom - top
    if w <= 0 or h <= 0:
        print(f"  ERROR: Invalid rect ({left},{top},{right},{bottom})")
        return False
    with mss.mss() as sct:
        shot = sct.grab({"left": left, "top": top, "width": w, "height": h})
        output_path.parent.mkdir(parents=True, exist_ok=True)
        mss.tools.to_png(shot.rgb, shot.size, output=str(output_path))
    kb = output_path.stat().st_size / 1024
    print(f"    Saved: {output_path.name} ({w}x{h}, {kb:.0f} KB)")
    return True


def capture_pages(hwnd, out_dir, page_ids, settle, debug=False):
    """Navigate to each page and capture a screenshot."""
    pages = [p for p in PAGES if p["id"] in page_ids]
    captured = []

    # First, navigate to a different page to ensure the first real navigation
    # is visible (the app may already be on the first page).
    if pages:
        # Navigate to settings first (always different from first capture page)
        warmup = {"id": "settings", "label": "Settings", "nav_index": -1}
        if debug:
            print("  [warmup] Navigating to Settings to reset state...")
        click_nav(hwnd, warmup, debug)
        time.sleep(settle)

    for i, page in enumerate(pages):
        print(f"\n  [{i+1}/{len(pages)}] {page['label']}...")
        click_nav(hwnd, page, debug)
        time.sleep(settle)

        fname = f"screenshot-{i+1:02d}-{page['id']}.png"
        if capture_window(hwnd, out_dir / fname):
            captured.append(out_dir / fname)
        else:
            print(f"    FAILED: {page['id']}")

    return captured


def main():
    parser = argparse.ArgumentParser(
        description="Capture WhisPaste window screenshots for store listings",
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--pages", nargs="*", default=None,
        help=f"Pages to capture (default: {' '.join(DEFAULT_PAGES)})")
    parser.add_argument("--all-pages", action="store_true")
    parser.add_argument("--settle", type=float, default=1.5,
        help="Seconds to wait after navigation (default: 1.5)")
    parser.add_argument("--no-maximize", action="store_true")
    parser.add_argument("--debug", action="store_true",
        help="Print click coordinates for debugging")
    args = parser.parse_args()

    # DPI awareness
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass

    pyautogui.FAILSAFE = False
    pyautogui.PAUSE = 0.1

    print("=" * 60)
    print("WhisPaste Store Screenshot Capture")
    print("=" * 60)

    print("\n[1/3] Finding WhisPaste window...")
    hwnd = find_whispaste_window()
    if not hwnd:
        print("  ERROR: WhisPaste not found. Start it first.")
        sys.exit(1)

    if not args.no_maximize:
        print("\n[2/3] Maximizing window...")
        maximize_window(hwnd)
    else:
        print("\n[2/3] Bringing to front...")
        try:
            win32gui.SetForegroundWindow(hwnd)
        except Exception:
            pass
        time.sleep(0.3)

    page_ids = ([p["id"] for p in PAGES] if args.all_pages
                else args.pages or DEFAULT_PAGES)
    valid = {p["id"] for p in PAGES}
    bad = [p for p in page_ids if p not in valid]
    if bad:
        print(f"  ERROR: Unknown pages: {', '.join(bad)}")
        sys.exit(1)

    if args.debug:
        r = get_window_rect(hwnd)
        print(f"\n  Window rect: {r}  ({r[2]-r[0]}x{r[3]-r[1]})")
        for p in PAGES:
            is_s = p["id"] == "settings"
            x, y = calc_nav_click_pos(hwnd, p["nav_index"], is_s)
            print(f"    {p['label']:15s} -> ({x}, {y})")

    print(f"\n[3/3] Capturing {len(page_ids)} pages...")
    captured = capture_pages(hwnd, args.output, page_ids, args.settle, args.debug)

    print("\n" + "=" * 60)
    print(f"Done! {len(captured)}/{len(page_ids)} screenshots captured.")
    print(f"Output: {args.output}")
    for p in captured:
        print(f"  - {p.name}")
    print("=" * 60)

    if len(captured) < len(page_ids):
        sys.exit(1)


if __name__ == "__main__":
    main()