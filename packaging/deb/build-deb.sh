#!/usr/bin/env bash
# Builds a WhisPaste .deb from the prebuilt Linux x86_64 release bundle produced
# by the `build-linux` job in .github/workflows/release.yml (the Flutter bundle
# under build/linux/x64/release/bundle, packaged as
# WhisPaste-<version>-linux-x64.tar.gz, artifact `linux-release`).
#
# We do NOT rebuild Flutter here — all §3.1 build pitfalls are already baked into
# the bundle. We lay the bundle into /opt/whispaste, symlink the executable onto
# PATH, drop the .desktop entry + AppStream metainfo + icon, then assemble the
# control file and call dpkg-deb.
#
# Runtime writable paths: the app self-downloads the Sprachdienst (whisper-server)
# + Sprachmodell at first run into the *user's* config dir
# ($XDG_CONFIG_HOME/whispaste/models/stt, default ~/.config/whispaste/models/stt
# — see packages/whispaste_diagnostics/.../path_service.dart appDataDir()/sttDir()).
# That path is per-user and writable; the system install under /opt is read-only,
# which is correct — nothing is written under /opt at runtime.
#
# Usage:
#   build-deb.sh <bundle-dir> <version> <out-dir>
#
# Validate this script's syntax without running it:
#   bash -n packaging/deb/build-deb.sh
set -euo pipefail

BUNDLE_DIR="${1:?usage: build-deb.sh <bundle-dir> <version> <out-dir>}"
VERSION="${2:?missing version}"
OUT_DIR="${3:?missing out-dir}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$SCRIPT_DIR/../.."

APP_ID="de.whispaste.app"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# ── 1. Lay out the file system tree ──────────────────────────────────────────
install -d "$STAGE/opt/whispaste"
cp -r "$BUNDLE_DIR"/. "$STAGE/opt/whispaste/"
chmod +x "$STAGE/opt/whispaste/whispaste"
# crashpad_handler (sentry-native) must stay executable (§3.1).
if [ -f "$STAGE/opt/whispaste/lib/crashpad_handler" ]; then
  chmod +x "$STAGE/opt/whispaste/lib/crashpad_handler"
fi

# Executable on PATH.
install -d "$STAGE/usr/bin"
ln -s /opt/whispaste/whispaste "$STAGE/usr/bin/whispaste"

# Desktop entry + AppStream metainfo (reused verbatim from packaging/flatpak —
# single source of truth for App-ID, name, categories, keywords).
install -Dm644 "$PKG_ROOT/packaging/flatpak/$APP_ID.desktop" \
  "$STAGE/usr/share/applications/$APP_ID.desktop"
install -Dm644 "$PKG_ROOT/packaging/flatpak/$APP_ID.metainfo.xml" \
  "$STAGE/usr/share/metainfo/$APP_ID.metainfo.xml"
# Icon, renamed to the App-ID per the freedesktop icon-naming spec. Uses the
# committed 512px derivative — the master app_icon.png is 1024x1024, which does
# not match the hicolor 512x512 slot.
install -Dm644 "$PKG_ROOT/assets/icons/app_icon_512.png" \
  "$STAGE/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"

# ── 2. Control metadata ──────────────────────────────────────────────────────
install -d "$STAGE/DEBIAN"
sed "s/__VERSION__/$VERSION/" "$SCRIPT_DIR/control.template" \
  > "$STAGE/DEBIAN/control"

# Installed-Size (KiB) — dpkg-deb does not compute it; lintian flags its absence.
INSTALLED_KB="$(du -sk "$STAGE/opt" "$STAGE/usr" | awk '{s+=$1} END {print s}')"
printf 'Installed-Size: %s\n' "$INSTALLED_KB" >> "$STAGE/DEBIAN/control"

# ── 3. Build ─────────────────────────────────────────────────────────────────
install -d "$OUT_DIR"
DEB_NAME="WhisPaste-${VERSION}-linux-x64.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$OUT_DIR/$DEB_NAME"

echo "Built $OUT_DIR/$DEB_NAME"
dpkg-deb --info "$OUT_DIR/$DEB_NAME"
