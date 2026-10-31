#!/usr/bin/env bash
# build_exe.sh — builds WhisPaste-GPU-Probe.exe (Windows x64, host-platform AOT)
#
# Prerequisites:
#   - Dart SDK on PATH (must match the target platform — dart compile exe
#     produces a native binary for the HOST platform only; cross-compile is
#     NOT supported by dart compile exe as of Dart 3.x).
#     To build the Windows .exe, run this script on a Windows host or a
#     Windows CI runner (e.g. windows-latest on GitHub Actions).
#   - Run from the package root: packages/whispaste_gpu_probe/
#
# Produces:
#   dist/WhisPaste-GPU-Probe.exe   — self-contained AOT executable
#   dist/README.md                 — runtime bundling layout docs
#
# Usage:
#   cd packages/whispaste_gpu_probe
#   bash tool/build_exe.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PACKAGE_DIR/dist"
EXE_NAME="WhisPaste-GPU-Probe.exe"
EXE_PATH="$DIST_DIR/$EXE_NAME"

echo "==> Building $EXE_NAME..."
mkdir -p "$DIST_DIR"

# Stamp the report with the repo app version (from the root pubspec).
REPO_ROOT="$(cd "$PACKAGE_DIR/../.." && pwd)"
APP_VERSION="$(grep -m1 '^version:' "$REPO_ROOT/pubspec.yaml" 2>/dev/null \
  | sed -E 's/^version:[[:space:]]*//; s/\+.*$//' || true)"
APP_VERSION="${APP_VERSION:-unbekannt}"
echo "    Version: $APP_VERSION"

dart compile exe "$PACKAGE_DIR/bin/whispaste_gpu_probe.dart" \
  --define=whispaste_version="$APP_VERSION" \
  -o "$EXE_PATH"

echo "==> Staging bundled assets..."
# Copy the reference WAV clips next to the exe so the probe candidates can
# locate them without installation.
# See dist/README.md for the full runtime layout.
ASSETS_SRC="$PACKAGE_DIR/assets"
ASSETS_DST="$DIST_DIR/assets"
if [ -d "$ASSETS_SRC" ]; then
  cp -r "$ASSETS_SRC/." "$ASSETS_DST/"
  echo "    Assets staged: $ASSETS_DST"
else
  echo "    (no assets/ directory found — skipped)"
fi

# Engine binaries are NOT bundled here: they are platform-specific large
# binaries (whisper.cpp .exe, DirectML .dll, etc.) that must be placed by the
# developer/CI in dist/engines/ before packaging.
# See dist/README.md → "Engine binaries" section.

echo "==> Verifying exe..."
if [ ! -f "$EXE_PATH" ]; then
  echo "ERROR: Executable not found at $EXE_PATH" >&2
  exit 1
fi

echo "==> Build OK: $EXE_PATH"
echo "    Size: $(ls -lh "$EXE_PATH" | awk '{print $5}')"
echo ""
echo "    Next steps:"
echo "      1. Copy engine binaries into dist/engines/ (see dist/README.md)"
echo "      2. Zip the dist/ directory for distribution"
echo "      3. Smoke-test: $EXE_PATH --output-dir %TEMP% --no-deliver"
