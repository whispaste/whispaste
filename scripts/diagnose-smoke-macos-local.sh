#!/usr/bin/env bash
#
# diagnose-smoke-macos-local.sh — WhisPaste-Diagnose smoke test on the Mac.
# Replaces the former `smoke-macos` job of .github/workflows/diagnose-dart-smoke.yml
# (GitHub macOS runners bill 10x). Same steps, run before a merge that touches
# packages/whispaste_diagnostics/ and before a release.
#
# Usage: bash scripts/diagnose-smoke-macos-local.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$REPO_ROOT/packages/whispaste_diagnostics"
die() { echo "ERROR: $*" >&2; exit 1; }

cd "$PKG"
dart pub get
bash tool/build_app_bundle.sh

APP="dist/WhisPaste-Diagnose.app"
EXEC="$APP/Contents/MacOS/WhisPaste-Diagnose"
PLIST="$APP/Contents/Info.plist"
[[ -f "$EXEC" ]] || die "executable not found at $EXEC"
[[ -x "$EXEC" ]] || die "executable bit not set"
[[ -f "$PLIST" ]] || die "Info.plist not found"
file "$EXEC" | grep -q 'Mach-O' || die "not a Mach-O binary"
echo "==> .app structure OK"

OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT
"./$EXEC" --output-dir "$OUT_DIR" || die "binary exited non-zero"
TXT_COUNT="$(find "$OUT_DIR" -name '*.txt' | wc -l | tr -d ' ')"
ZIP_COUNT="$(find "$OUT_DIR" -name '*.zip' | wc -l | tr -d ' ')"
[[ "$TXT_COUNT" -ge 1 ]] || die "no .txt report written"
[[ "$ZIP_COUNT" -ge 1 ]] || die "no .zip bundle written"
echo "==> Smoke OK — report written:"
find "$OUT_DIR" -type f
