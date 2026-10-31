#!/usr/bin/env bash
# build_app_bundle.sh — builds WhisPaste-Diagnose.app (arm64, macOS)
#
# Prerequisites:
#   - Dart SDK on PATH (arm64, for arm64-only output)
#   - Run from the package root: packages/whispaste_diagnostics/
#
# Produces:
#   dist/WhisPaste-Diagnose.app   — minimal .app bundle (no Flutter)
#   dist/WhisPaste-Diagnose.zip   — DMG-ready archive (optional, use hdiutil externally)
#
# Usage:
#   cd packages/whispaste_diagnostics
#   bash tool/build_app_bundle.sh
#
# To create a DMG from the resulting .app:
#   hdiutil create -volname "WhisPaste-Diagnose" \
#     -srcfolder dist/WhisPaste-Diagnose.app \
#     -ov -format UDZO \
#     dist/WhisPaste-Diagnose.dmg
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PACKAGE_DIR/dist"
APP_NAME="WhisPaste-Diagnose"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
EXE_PATH="$DIST_DIR/$APP_NAME"

echo "==> Building $APP_NAME Mach-O binary..."
mkdir -p "$DIST_DIR"

# Stamp the report with the repo app version (from the root pubspec).
REPO_ROOT="$(cd "$PACKAGE_DIR/../.." && pwd)"
APP_VERSION="$(grep -m1 '^version:' "$REPO_ROOT/pubspec.yaml" 2>/dev/null \
  | sed -E 's/^version:[[:space:]]*//; s/\+.*$//' || true)"
APP_VERSION="${APP_VERSION:-unbekannt}"
echo "    Version: $APP_VERSION"

dart compile exe "$PACKAGE_DIR/bin/whispaste_diagnose.dart" \
  --define=whispaste_version="$APP_VERSION" \
  -o "$EXE_PATH"

echo "==> Assembling .app bundle..."
# Clean any previous bundle.
rm -rf "$APP_BUNDLE"

# Minimal .app structure: Contents/MacOS/ + Contents/Info.plist
mkdir -p "$APP_BUNDLE/Contents/MacOS"

# Copy binary and preserve executable bit.
cp "$EXE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Write Info.plist (minimal, no CFBundleIconFile, no LSUIElement tricks needed
# for a pure CLI — it just needs CFBundleExecutable and CFBundleIdentifier).
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>WhisPaste-Diagnose</string>
  <key>CFBundleDisplayName</key>
  <string>WhisPaste-Diagnose</string>
  <key>CFBundleExecutable</key>
  <string>WhisPaste-Diagnose</string>
  <key>CFBundleIdentifier</key>
  <string>com.silvio.whispaste.diagnose</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>LSBackgroundOnly</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "==> Verifying bundle..."
EXEC="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [ ! -f "$EXEC" ]; then
  echo "ERROR: Executable not found at $EXEC" >&2
  exit 1
fi
if [ ! -x "$EXEC" ]; then
  echo "ERROR: Executable bit not set on $EXEC" >&2
  exit 1
fi
PLIST_PATH="$APP_BUNDLE/Contents/Info.plist"
if [ ! -f "$PLIST_PATH" ]; then
  echo "ERROR: Info.plist not found at $PLIST_PATH" >&2
  exit 1
fi

echo "==> Bundle OK: $APP_BUNDLE"
echo "    Executable: $(ls -la "$EXEC")"
echo ""
echo "    To create a DMG:"
echo "      hdiutil create -volname \"WhisPaste-Diagnose\" \\"
echo "        -srcfolder \"$APP_BUNDLE\" \\"
echo "        -ov -format UDZO \\"
echo "        \"$DIST_DIR/$APP_NAME.dmg\""
