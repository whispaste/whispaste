#!/usr/bin/env python3
"""
Microsoft Store screenshot generator for WhisPaste (Flutter).

Uses golden_screenshot to generate high-quality PNGs headlessly —
no app launch, no display required, CI-friendly.

Usage:
    python scripts/store-screenshots.py
    python scripts/store-screenshots.py --output screenshots/

Output: screenshots/ directory with PNG files ready for MS Store upload.
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GOLDENS_DIR = ROOT / "test" / "screenshots" / "goldens" / "windowsStoreScreenshots"
DEFAULT_OUTPUT = ROOT / "screenshots"


def find_flutter() -> str:
    """Locate Flutter binary."""
    for candidate in [r"C:\flutter\bin\flutter.bat", "flutter"]:
        if shutil.which(candidate) or Path(candidate).exists():
            return candidate
    print("ERROR: flutter not found on PATH.")
    sys.exit(1)


def run_golden_tests(flutter: str) -> bool:
    """Run golden screenshot tests to generate/refresh PNGs."""
    print("Running golden screenshot tests...")
    result = subprocess.run(
        [flutter, "test", "--update-goldens", "test/screenshots/"],
        cwd=str(ROOT),
        env={**__import__("os").environ, "CI": "true"},
    )
    return result.returncode == 0


def collect_screenshots(output_dir: Path) -> list[Path]:
    """Copy generated goldens to the output directory with Store naming."""
    output_dir.mkdir(parents=True, exist_ok=True)
    collected = []

    if not GOLDENS_DIR.exists():
        print(f"ERROR: Goldens directory not found: {GOLDENS_DIR}")
        return collected

    for png in sorted(GOLDENS_DIR.glob("*.png")):
        dest = output_dir / f"store-{png.name}"
        shutil.copy2(png, dest)
        size_kb = dest.stat().st_size / 1024
        print(f"  {dest.name} ({size_kb:.1f} KB)")
        collected.append(dest)

    return collected


def main():
    parser = argparse.ArgumentParser(
        description="WhisPaste Store screenshot generator (golden_screenshot)",
    )
    parser.add_argument(
        "--output", type=Path, default=DEFAULT_OUTPUT,
        help=f"Output directory (default: {DEFAULT_OUTPUT.relative_to(ROOT)})",
    )
    parser.add_argument(
        "--skip-generate", action="store_true",
        help="Skip test run, just collect existing goldens",
    )
    args = parser.parse_args()

    print("=" * 60)
    print("WhisPaste Store Screenshot Generator")
    print("=" * 60)
    print()

    flutter = find_flutter()

    if not args.skip_generate:
        if not run_golden_tests(flutter):
            print("\nWARNING: Some screenshot tests failed (see above).")
            print("Collecting whatever was generated...\n")
    else:
        print("Skipping generation, collecting existing goldens.\n")

    screenshots = collect_screenshots(args.output)

    print()
    if screenshots:
        print(f"Done! {len(screenshots)} screenshot(s) in {args.output}")
        print("\nMicrosoft Store requirements:")
        print("  - Format: PNG ✓")
        print("  - Resolution: 1366×768 (min) to 3840×2160 (max)")
        print("  - Max 10 screenshots, at least 1 required")
    else:
        print("No screenshots generated. Check test output above.")
        sys.exit(1)


if __name__ == "__main__":
    main()