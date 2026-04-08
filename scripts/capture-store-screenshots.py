#!/usr/bin/env python3
"""
Real-window screenshot capture for WhisPaste (Windows).

Captures the running WhisPaste Flutter window including title bar,
borders, and frame chrome using mss + pywin32.

Prerequisites:
    pip install mss pywin32

Usage:
    # With WhisPaste already running:
    python scripts/capture-store-screenshots.py

    # Custom output directory:
    python scripts/capture-store-screenshots.py --output screenshots/raw

Output: PNG screenshots at native window resolution.
"""

import argparse
import ctypes
import sys
import time
from pathlib import Path

try:
    import mss
    import mss.tools
    import win32gui
    import win32con
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with: pip install mss pywin32")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = ROOT / "screenshots" / "raw"

# Window titles to search for (Flutter debug and release)
WINDOW_TITLES = [
    "WhisPaste",
    "whispaste",
]


def find_whispaste_window() -> int | None:
    """Find the WhisPaste main window handle."""
    result = []

    def enum_callback(hwnd: int, _: object) -> bool:
        if not win32gui.IsWindowVisible(hwnd):
            return True
        title = win32gui.GetWindowText(hwnd)
        for pattern in WINDOW_TITLES:
            if pattern.lower() in title.lower():
                result.append((hwnd, title))
        return True

    win32gui.EnumWindows(enum_callback, None)

    if not result:
        return None

    # Prefer exact match, then longest title
    result.sort(key=lambda x: (x[1] == "WhisPaste", len(x[1])), reverse=True)
    hwnd, title = result[0]
    print(f"  Found window: '{title}' (hwnd={hwnd})")
    return hwnd


def bring_to_front(hwnd: int) -> None:
    """Bring the window to the foreground and restore if minimized."""
    if win32gui.IsIconic(hwnd):
        win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
        time.sleep(0.3)

    win32gui.SetForegroundWindow(hwnd)
    time.sleep(0.2)


def get_window_rect(hwnd: int) -> tuple[int, int, int, int]:
    """Get the actual window rectangle including frame (DPI-aware)."""
    # Use DwmGetWindowAttribute for accurate bounds on Windows 10/11
    try:
        rect = ctypes.wintypes.RECT()
        DWMWA_EXTENDED_FRAME_BOUNDS = 9
        ctypes.windll.dwmapi.DwmGetWindowAttribute(
            hwnd,
            DWMWA_EXTENDED_FRAME_BOUNDS,
            ctypes.byref(rect),
            ctypes.sizeof(rect),
        )
        return (rect.left, rect.top, rect.right, rect.bottom)
    except Exception:
        # Fallback to GetWindowRect
        return win32gui.GetWindowRect(hwnd)


def capture_window(hwnd: int, output_path: Path) -> bool:
    """Capture the window region to a PNG file."""
    bring_to_front(hwnd)
    time.sleep(0.5)  # Let window settle after focus

    left, top, right, bottom = get_window_rect(hwnd)
    w = right - left
    h = bottom - top

    if w <= 0 or h <= 0:
        print(f"  ERROR: Invalid window rect ({left},{top},{right},{bottom})")
        return False

    monitor = {"left": left, "top": top, "width": w, "height": h}

    with mss.mss() as sct:
        screenshot = sct.grab(monitor)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        mss.tools.to_png(screenshot.rgb, screenshot.size, output=str(output_path))

    size_kb = output_path.stat().st_size / 1024
    print(f"  Captured: {output_path.name} ({w}x{h}, {size_kb:.0f} KB)")
    return True


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Capture WhisPaste window screenshots",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Output directory (default: {DEFAULT_OUTPUT.relative_to(ROOT)})",
    )
    parser.add_argument(
        "--name",
        type=str,
        default="screenshot",
        help="Base name for screenshots (default: screenshot)",
    )
    args = parser.parse_args()

    # Enable DPI awareness for accurate coordinates
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass

    print("=" * 60)
    print("WhisPaste Window Screenshot Capture")
    print("=" * 60)
    print()

    hwnd = find_whispaste_window()
    if hwnd is None:
        print("ERROR: WhisPaste window not found.")
        print("Start the app first: flutter run -d windows")
        sys.exit(1)

    output = args.output / f"{args.name}.png"
    if capture_window(hwnd, output):
        print(f"\nDone! Screenshot saved to: {output}")
    else:
        print("\nFailed to capture screenshot.")
        sys.exit(1)


if __name__ == "__main__":
    main()
