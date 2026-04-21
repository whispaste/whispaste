#!/usr/bin/env python3
"""
WhisPaste screenshot pipeline — cross-platform (macOS / Windows / Linux).

Generates all store and website screenshots from Flutter golden tests.

Pipeline:
  1. Clean all output directories (goldens, store, website)
  2. Run `flutter test --update-goldens` to regenerate golden PNGs
  3. Copy goldens → screenshots/store/  (with `store-` prefix)
  4. Copy goldens → website/public/screenshots/{locale}/{theme}/{name}.png

The golden tests render the FULL app window including title bar, sidebar,
content panel and status bar via WpScreenshotShell — no live app required.

Usage:
    python scripts/store-screenshots.py             # full pipeline
    python scripts/store-screenshots.py --no-regen  # skip test run, use existing goldens
    python scripts/store-screenshots.py --store-only # skip website copy
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GOLDENS_DIR = ROOT / "test" / "screenshots" / "goldens" / "windowsStoreScreenshots"
STORE_DIR = ROOT / "screenshots" / "store"
WEBSITE_DIR = ROOT / "website" / "public" / "screenshots"
TEST_PATH = "test/screenshots/store_screenshots_test.dart"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def find_flutter() -> str:
    """Return the flutter binary, checking common locations."""
    candidates = [
        # macOS / Linux on PATH
        "flutter",
        # Windows PATH alternative
        r"C:\flutter\bin\flutter.bat",
        r"C:\src\flutter\bin\flutter.bat",
    ]
    for candidate in candidates:
        if shutil.which(candidate) or Path(candidate).exists():
            return candidate
    print("ERROR: flutter not found on PATH.")
    sys.exit(1)


def clean_dir(directory: Path, *, glob: str = "*.png") -> int:
    """Delete files matching glob in directory. Returns count removed."""
    if not directory.exists():
        return 0
    removed = 0
    for f in directory.glob(glob):
        f.unlink()
        removed += 1
    return removed


def clean_website_screenshots(web_dir: Path) -> int:
    """Delete all PNG files inside the locale/theme subdirectory tree."""
    removed = 0
    for locale_dir in web_dir.iterdir():
        if not locale_dir.is_dir():
            continue
        for theme_dir in locale_dir.iterdir():
            if not theme_dir.is_dir():
                continue
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
    stem = Path(filename).stem  # strip .png
    # Locale is always the last segment, theme second-to-last.
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
    n = clean_dir(GOLDENS_DIR)
    print(f"   goldens:  {n} files removed")
    n = clean_dir(STORE_DIR)
    print(f"   store:    {n} files removed")
    n = clean_website_screenshots(WEBSITE_DIR)
    print(f"   website:  {n} files removed")


def step_generate(flutter: str) -> bool:
    """Run `flutter test --update-goldens` to regenerate golden PNGs."""
    print(f"\n🧪 Running golden tests (flutter test --update-goldens)...")
    result = subprocess.run(
        [flutter, "test", "--update-goldens", TEST_PATH],
        cwd=str(ROOT),
    )
    if result.returncode != 0:
        print("\n❌ Golden tests failed — check output above.")
        return False
    return True


def step_copy_store() -> list[Path]:
    """Copy goldens to screenshots/store/ with `store-` prefix."""
    STORE_DIR.mkdir(parents=True, exist_ok=True)
    copied = []
    for png in sorted(GOLDENS_DIR.glob("*.png")):
        dest = STORE_DIR / f"store-{png.name}"
        shutil.copy2(png, dest)
        size_kb = dest.stat().st_size / 1024
        copied.append(dest)
        print(f"   {dest.name}  ({size_kb:.0f} KB)")
    return copied


def step_copy_website() -> list[Path]:
    """Copy goldens to website/public/screenshots/{locale}/{theme}/{base}.png.

    Each golden is copied to BOTH the dark and light theme folders so the
    website gallery can show all screenshots regardless of theme toggle.
    """
    copied = []
    for png in sorted(GOLDENS_DIR.glob("*.png")):
        parsed = parse_golden_name(png.name)
        if parsed is None:
            print(f"   ⚠ Could not parse '{png.name}' — skipped")
            continue
        base, _native_theme, locale = parsed
        for theme in ("dark", "light"):
            dest = WEBSITE_DIR / locale / theme / f"{base}.png"
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(png, dest)
            size_kb = dest.stat().st_size / 1024
            copied.append(dest)
            print(f"   {locale}/{theme}/{base}.png  ({size_kb:.0f} KB)")
    return copied


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="WhisPaste screenshot pipeline",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--no-regen",
        action="store_true",
        help="Skip flutter test run, use existing goldens",
    )
    parser.add_argument(
        "--store-only",
        action="store_true",
        help="Copy to screenshots/store/ only, skip website copy",
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
        print("\n⏭  Skipping generation (--no-regen)")

    if not GOLDENS_DIR.exists() or not any(GOLDENS_DIR.glob("*.png")):
        print("\n❌ No goldens found. Run without --no-regen first.")
        sys.exit(1)

    print(f"\n📦 Copying to store: screenshots/store/")
    store_files = step_copy_store()

    if not args.store_only:
        print(f"\n🌐 Copying to website: website/public/screenshots/")
        web_files = step_copy_website()
    else:
        web_files = []

    print()
    print("=" * 60)
    print(f"  ✅ Done!")
    print(f"  📦 {len(store_files)} store screenshot(s) → screenshots/store/")
    if not args.store_only:
        print(f"  🌐 {len(web_files)} website screenshot(s) → website/public/screenshots/")
    print()
    print("  Next steps:")
    print("  • Upload screenshots/store/store-*.png to Microsoft Store")
    print("  • Run `python scripts/premium-screenshots.py` for framed composites")
    print("=" * 60)


if __name__ == "__main__":
    main()

