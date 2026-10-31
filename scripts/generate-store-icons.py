#!/usr/bin/env python3
"""
WhisPaste store icon generator — cross-platform.

Derives all store listing logos and app icons from the master 1024×1024
source asset for every relevant store/platform.

Store requirements:
  Microsoft Store (Partner Center store listing):
    StoreLogo  300×300  — primary listing logo
    MediumTile 150×150  — medium live tile
    SmallTile   71×71   — small tile / search results
    AppIcon     44×44   — shell/taskbar icon

  Mac App Store (App Store Connect):
    AppIcon  1024×1024  — RGBA PNG (macOS allows alpha)

  iOS App Store (App Store Connect):
    AppIcon  1024×1024  — flat PNG without alpha channel

  Google Play Store:
    ic_launcher  512×512 — store listing hi-res icon

Output layout:
  tools/store-icons/output/
    ms-store/
      StoreLogo_300x300.png
      StoreLogo_150x150.png
      StoreLogo_71x71.png
      AppIcon_44x44.png
    mac-app-store/
      AppIcon_1024x1024.png
    ios-app-store/
      AppIcon_1024x1024.png
    google-play/
      AppIcon_512x512.png

Usage:
    python scripts/generate-store-icons.py           # generate all
    python scripts/generate-store-icons.py --clean   # clean output first
    python scripts/generate-store-icons.py --source path/to/icon.png
"""

import argparse
import shutil
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow not found. Run: pip install Pillow", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = ROOT / "assets" / "icons" / "app_icon.png"
OUTPUT_DIR = ROOT / "tools" / "store-icons" / "output"

# ---------------------------------------------------------------------------
# Icon specs
# ---------------------------------------------------------------------------

MS_STORE_ICONS = [
    ("StoreLogo_300x300.png", 300, True),   # primary listing logo
    ("StoreLogo_150x150.png", 150, True),   # medium tile
    ("StoreLogo_71x71.png", 71, True),      # small tile
    ("AppIcon_44x44.png", 44, True),        # shell/taskbar
]

MAC_STORE_ICONS = [
    ("AppIcon_1024x1024.png", 1024, True),  # keeps alpha — macOS allows it
]

IOS_STORE_ICONS = [
    ("AppIcon_1024x1024.png", 1024, False), # no alpha — iOS requirement
]

GOOGLE_PLAY_ICONS = [
    ("AppIcon_512x512.png", 512, True),     # hi-res store listing icon
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def resize(source: Image.Image, size: int, keep_alpha: bool) -> Image.Image:
    """Return a high-quality resampled copy at ``size``×``size``."""
    if keep_alpha:
        img = source.copy().convert("RGBA")
    else:
        # Flatten alpha onto white background — required by iOS App Store
        bg = Image.new("RGB", source.size, (255, 255, 255))
        bg.paste(source, mask=source.split()[3] if source.mode == "RGBA" else None)
        img = bg
    return img.resize((size, size), Image.LANCZOS)


def generate_set(
    source: Image.Image,
    specs: list,
    out_dir: Path,
    label: str,
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for filename, size, keep_alpha in specs:
        dest = out_dir / filename
        icon = resize(source, size, keep_alpha)
        icon.save(dest, "PNG", optimize=True)
        print(f"  ✓ {label}/{filename}  ({size}×{size})")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Generate WhisPaste store icons")
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE,
        help="Master icon PNG (default: assets/icons/app_icon.png)",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Delete output directory before generating",
    )
    args = parser.parse_args()

    source_path: Path = args.source
    if not source_path.exists():
        print(f"ERROR: Source icon not found: {source_path}", file=sys.stderr)
        sys.exit(1)

    source = Image.open(source_path).convert("RGBA")
    if source.size != (1024, 1024):
        print(
            f"WARNING: Source is {source.size}, expected (1024, 1024). "
            "Proceeding anyway.",
            file=sys.stderr,
        )

    if args.clean and OUTPUT_DIR.exists():
        shutil.rmtree(OUTPUT_DIR)
        print(f"Cleaned: {OUTPUT_DIR}")

    print(f"\nSource: {source_path}  ({source.size[0]}×{source.size[1]})\n")

    print("Microsoft Store:")
    generate_set(source, MS_STORE_ICONS, OUTPUT_DIR / "ms-store", "ms-store")

    print("\nMac App Store:")
    generate_set(source, MAC_STORE_ICONS, OUTPUT_DIR / "mac-app-store", "mac-app-store")

    print("\niOS App Store:")
    generate_set(source, IOS_STORE_ICONS, OUTPUT_DIR / "ios-app-store", "ios-app-store")

    print("\nGoogle Play Store:")
    generate_set(source, GOOGLE_PLAY_ICONS, OUTPUT_DIR / "google-play", "google-play")

    print(f"\nAll store icons written to: {OUTPUT_DIR}\n")


if __name__ == "__main__":
    main()
