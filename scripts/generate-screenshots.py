#!/usr/bin/env python3
"""
WhisPaste screenshot pipeline — cross-platform (macOS / Windows / Linux).

Generates all store composites, website screenshots, and OG images
from Flutter golden tests in a single clean run.

Pipeline:
  1. Clean all output directories
  2. flutter test --update-goldens  →  generates golden PNGs
  3. Copy goldens → website/public/screenshots/{locale}/{theme}/{name}.png
  4. node tools/appstore-screens/generate.cjs  →  store composites (MS + Mac)
  5. node tools/appstore-screens/generate-og.cjs  →  OG images

Usage:
    python scripts/generate-screenshots.py              # full pipeline
    python scripts/generate-screenshots.py --no-regen   # skip flutter test
    python scripts/generate-screenshots.py --no-composites  # skip Node steps
    python scripts/generate-screenshots.py --no-clean   # keep existing outputs
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WINDOWS_GOLDENS_DIR = ROOT / "test" / "screenshots" / "goldens" / "windowsStoreScreenshots"
MAC_GOLDENS_DIR = ROOT / "test" / "screenshots" / "goldens" / "macStoreScreenshots"
WEBSITE_DIR = ROOT / "website" / "public" / "screenshots"
WEBSITE_MAC_DIR = WEBSITE_DIR / "mac"
APPSTORE_SCREENS_DIR = ROOT / "tools" / "appstore-screens"
APPSTORE_OUTPUT_DIR = APPSTORE_SCREENS_DIR / "output"
TEST_PATH = "test/screenshots/store_screenshots_test.dart"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def find_flutter() -> str:
    """Return the flutter binary, checking common locations."""
    candidates = [
        "flutter",
        r"C:\flutter\bin\flutter.bat",
        r"C:\src\flutter\bin\flutter.bat",
    ]
    for candidate in candidates:
        if shutil.which(candidate) or Path(candidate).exists():
            return candidate
    print("ERROR: flutter not found on PATH.")
    sys.exit(1)


def find_node() -> str:
    """Return the node binary."""
    node = shutil.which("node") or shutil.which("node.exe")
    if not node:
        print("ERROR: node not found on PATH. Install Node.js.")
        sys.exit(1)
    return node


def clean_dir(directory: Path, *, glob: str = "*.png") -> int:
    """Delete files matching glob in directory. Returns count removed."""
    if not directory.exists():
        return 0
    removed = 0
    for f in directory.glob(glob):
        f.unlink()
        removed += 1
    return removed


def clean_dir_recursive(directory: Path) -> int:
    """Delete all PNG files recursively under directory."""
    if not directory.exists():
        return 0
    removed = 0
    for f in directory.rglob("*.png"):
        f.unlink()
        removed += 1
    return removed


def clean_website_screenshots(web_dir: Path) -> int:
    """Delete all PNG files inside the locale/theme subdirectory tree.

    Handles both 2-level (locale/theme) and 3-level (platform/locale/theme)
    structures so that the mac/ subdirectory is cleaned properly.
    """
    removed = 0
    for locale_or_platform_dir in web_dir.iterdir():
        if not locale_or_platform_dir.is_dir():
            continue
        for next_dir in locale_or_platform_dir.iterdir():
            if not next_dir.is_dir():
                continue
            # 2-level: web_dir/{locale}/{theme}/
            inner = list(next_dir.iterdir())
            if any(f.is_file() and f.suffix == '.png' for f in inner):
                removed += clean_dir(next_dir)
            else:
                # 3-level: web_dir/{platform}/{locale}/{theme}/
                for theme_dir in inner:
                    if theme_dir.is_dir():
                        removed += clean_dir(theme_dir)
    return removed


def parse_golden_name(filename: str):
    """
    Parse a golden filename into (base, theme, locale).

    Pattern: {base}_{theme}_{locale}.png
    Examples:
      01_workspace_overview_dark_en → ('01_workspace_overview', 'dark', 'en')
      04_settings_light_de           → ('04_settings', 'light', 'de')
    """
    stem = Path(filename).stem
    parts = stem.rsplit("_", 2)
    if len(parts) != 3:
        return None
    base, theme, locale = parts
    return base, theme, locale


# ---------------------------------------------------------------------------
# Pipeline steps
# ---------------------------------------------------------------------------

def step_clean() -> None:
    """Remove all stale outputs before regenerating."""
    print("🧹 Cleaning output directories...")
    n = clean_dir(WINDOWS_GOLDENS_DIR)
    n += clean_dir(MAC_GOLDENS_DIR)
    print(f"   goldens:          {n} files removed")
    n = clean_website_screenshots(WEBSITE_DIR)
    print(f"   website/screenshots: {n} files removed")
    n = clean_dir_recursive(APPSTORE_OUTPUT_DIR)
    print(f"   store composites: {n} files removed")


def step_generate(flutter: str) -> bool:
    """Run flutter test --update-goldens to regenerate golden PNGs."""
    print("\n🧪 Running golden tests (flutter test --update-goldens)...")
    result = subprocess.run(
        [flutter, "test", "--update-goldens", TEST_PATH],
        cwd=str(ROOT),
    )
    if result.returncode != 0:
        print("\n❌ Golden tests failed — check output above.")
        return False
    return True


def step_copy_website() -> list[Path]:
    """Copy goldens to website/public/screenshots/.

    Windows goldens → {locale}/{theme}/{base}.png
    Mac goldens     → mac/{locale}/{theme}/{base}.png

    Each golden is copied to BOTH dark and light theme folders so the
    website gallery works regardless of theme toggle.
    """
    copied: list[Path] = []
    copied.extend(_copy_goldens(WINDOWS_GOLDENS_DIR, WEBSITE_DIR))
    copied.extend(_copy_goldens(MAC_GOLDENS_DIR, WEBSITE_MAC_DIR))
    return copied


def _copy_goldens(goldens_dir: Path, dest_root: Path) -> list[Path]:
    """Copy goldens from goldens_dir into dest_root/{locale}/{theme}/{base}.png."""
    copied: list[Path] = []
    for png in sorted(goldens_dir.glob("*.png")):
        parsed = parse_golden_name(png.name)
        if parsed is None:
            print(f"   ⚠ Could not parse '{png.name}' — skipped")
            continue
        base, _native_theme, locale = parsed
        for theme in ("dark", "light"):
            dest = dest_root / locale / theme / f"{base}.png"
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(png, dest)
            size_kb = dest.stat().st_size / 1024
            copied.append(dest)
            rel = dest.relative_to(dest_root.parent.parent.parent)
            print(f"   {rel}  ({size_kb:.0f} KB)")
    return copied


def step_node(node: str, script: str, label: str) -> bool:
    """Run a Node.js script from tools/appstore-screens/."""
    script_path = APPSTORE_SCREENS_DIR / script
    if not script_path.exists():
        print(f"\n❌ Script not found: {script_path}")
        return False
    print(f"\n🎨 {label}...")
    result = subprocess.run(
        [node, str(script_path), "--lang=all"],
        cwd=str(APPSTORE_SCREENS_DIR),
    )
    if result.returncode != 0:
        print(f"\n❌ {label} failed — check output above.")
        return False
    return True


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="WhisPaste screenshot pipeline — generates all store and website images",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--no-regen",
        action="store_true",
        help="Skip flutter test run, use existing goldens",
    )
    parser.add_argument(
        "--no-composites",
        action="store_true",
        help="Skip Node.js composite/OG-image generation (goldens + website copy only)",
    )
    parser.add_argument(
        "--no-clean",
        action="store_true",
        help="Skip cleaning output directories (faster for iteration)",
    )
    args = parser.parse_args()

    print("=" * 60)
    print("  WhisPaste Screenshot Pipeline")
    print("=" * 60)

    if not args.no_clean:
        step_clean()

    flutter = find_flutter()

    if not args.no_regen:
        if not step_generate(flutter):
            sys.exit(1)
    else:
        print("\n⏭  Skipping golden regen (--no-regen)")

    if not WINDOWS_GOLDENS_DIR.exists() or not any(WINDOWS_GOLDENS_DIR.glob("*.png")):
        print("\n❌ No goldens found. Run without --no-regen first.")
        sys.exit(1)

    print(f"\n🌐 Copying to website/public/screenshots/")
    web_files = step_copy_website()

    if not args.no_composites:
        node = find_node()
        if not step_node(node, "generate.cjs", "Generating store composites (MS Store + Mac App Store)"):
            sys.exit(1)
        if not step_node(node, "generate-og.cjs", "Generating OG images"):
            sys.exit(1)
    else:
        print("\n⏭  Skipping composites (--no-composites)")

    print()
    print("=" * 60)
    print("  ✅ Done!")
    print(f"  🌐 {len(web_files)} website screenshot(s) → website/public/screenshots/")
    if not args.no_composites:
        ms_dir = APPSTORE_OUTPUT_DIR / "en" / "microsoft"
        mac_dir = APPSTORE_OUTPUT_DIR / "en" / "mac"
        ms_count = len(list(ms_dir.glob("*.png"))) if ms_dir.exists() else 0
        mac_count = len(list(mac_dir.glob("*.png"))) if mac_dir.exists() else 0
        print(f"  🪟 {ms_count * 2} MS Store composites → tools/appstore-screens/output/{{en,de}}/microsoft/")
        print(f"  🍎 {mac_count * 2} Mac App Store composites → tools/appstore-screens/output/{{en,de}}/mac/")
        print(f"  🖼️  2 OG images → website/public/og-image{{,-de}}.png")
    print("=" * 60)


if __name__ == "__main__":
    main()
