#!/usr/bin/env bash
# Builds a WhisPaste AppImage from the prebuilt Linux x86_64 release bundle
# produced by the `build-linux` job in .github/workflows/release.yml (the Flutter
# bundle under build/linux/x64/release/bundle, packaged as
# WhisPaste-<version>-linux-x64.tar.gz, artifact `linux-release`).
#
# We do NOT rebuild Flutter — all §3.1 build pitfalls are already baked into the
# bundle. We assemble an AppDir, then call linuxdeploy to bundle the Flutter
# bundle's shared libs and emit a single relocatable AppImage.
#
# Runtime writable paths: an AppImage is unsandboxed, so the app self-downloads
# the Sprachdienst (whisper-server) + Sprachmodell at first run into the user's
# config dir ($XDG_CONFIG_HOME/whispaste/models/stt, default
# ~/.config/whispaste/models/stt — see appDataDir()/sttDir() in
# packages/whispaste_diagnostics/.../path_service.dart). That path is writable
# and not noexec, so the downloaded binary is chmod +x'd and executed there.
# The AppImage mount itself is read-only, which is correct — nothing runtime is
# written inside it.
#
# Usage:
#   build-appimage.sh <bundle-dir> <version> <out-dir>
#
# Requires linuxdeploy (downloaded by the CI job). Validate syntax without
# running:
#   bash -n packaging/appimage/build-appimage.sh
set -euo pipefail

BUNDLE_DIR="${1:?usage: build-appimage.sh <bundle-dir> <version> <out-dir>}"
VERSION="${2:?missing version}"
OUT_DIR="${3:?missing out-dir}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$SCRIPT_DIR/../.."

APP_ID="de.whispaste.app"
APPDIR="$(mktemp -d)/WhisPaste.AppDir"
trap 'rm -rf "$(dirname "$APPDIR")"' EXIT

# ── 1. Lay out the AppDir ────────────────────────────────────────────────────
install -d "$APPDIR/usr/bin"
cp -r "$BUNDLE_DIR"/. "$APPDIR/usr/bin/"
chmod +x "$APPDIR/usr/bin/whispaste"
# crashpad_handler (sentry-native) must stay executable (§3.1).
if [ -f "$APPDIR/usr/bin/lib/crashpad_handler" ]; then
  chmod +x "$APPDIR/usr/bin/lib/crashpad_handler"
fi

# Desktop entry + icon (reused verbatim from packaging/flatpak — single source
# of truth). linuxdeploy reads these to populate the AppDir root.
install -Dm644 "$PKG_ROOT/packaging/flatpak/$APP_ID.desktop" \
  "$APPDIR/usr/share/applications/$APP_ID.desktop"
install -Dm644 "$PKG_ROOT/packaging/flatpak/$APP_ID.metainfo.xml" \
  "$APPDIR/usr/share/metainfo/$APP_ID.metainfo.xml"
install -Dm644 "$PKG_ROOT/assets/icons/app_icon.png" \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"

# ── 2. Run linuxdeploy ───────────────────────────────────────────────────────
# linuxdeploy bundles the executable's shared-library dependencies. We also
# point it at the Flutter bundle's own lib/ so its plugin .so files are picked
# up. ARCH + OUTPUT control the emitted file.
export ARCH=x86_64
export OUTPUT="$OUT_DIR/WhisPaste-${VERSION}-linux-x64.AppImage"
install -d "$OUT_DIR"

linuxdeploy \
  --appdir "$APPDIR" \
  --executable "$APPDIR/usr/bin/whispaste" \
  --desktop-file "$APPDIR/usr/share/applications/$APP_ID.desktop" \
  --icon-file "$APPDIR/usr/share/icons/hicolor/512x512/apps/$APP_ID.png" \
  --library-path "$APPDIR/usr/bin/lib" \
  --output appimage

echo "Built $OUTPUT"
