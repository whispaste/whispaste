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
# Requires linuxdeploy (downloaded by the CI job) and pulseaudio-utils on the
# build host: its `parecord` and `pactl` are bundled (#1608). Validate syntax
# without running:
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
# The hicolor 512x512 slot needs a real 512px icon — the master app_icon.png is
# 1024x1024, which linuxdeploy rejects ("invalid x resolution: 1024"). Use the
# committed 512px derivative so no build-time image tooling is required.
install -Dm644 "$PKG_ROOT/assets/icons/app_icon_512.png" \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"

# Licence text of libXScrnSaver, which the app links against (BIZ-92). The Flutter
# bundle also carries it for the in-app licences page.
install -Dm644 "$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)/assets/licenses/libxscrnsaver-LICENSE.txt" \
  "$APPDIR/usr/share/licenses/libXScrnSaver/COPYING"

# linuxdeploy rewrites the executable's RUNPATH from $ORIGIN/lib to
# $ORIGIN/../lib, so usr/bin/lib is no longer searched. The app loads speech
# recognition and sound by bare name at runtime (Dart FFI), which no ldd or
# linuxdeploy step can see: without these links every dictation fails with
# "Failed to load dynamic library".
install -d "$APPDIR/usr/lib"
for lib in "$APPDIR"/usr/bin/lib/*.so*; do
  [ -e "$lib" ] || continue
  ln -sf "../bin/lib/$(basename "$lib")" "$APPDIR/usr/lib/"
done
for lib in libsherpa-onnx-c-api.so libwhisper.so libflutter_soloud_plugin.so; do
  if [ ! -e "$APPDIR/usr/lib/$lib" ]; then
    echo "$lib is not on the AppImage's library path; dictation would fail" >&2
    exit 1
  fi
done

# Sound tools (#1608). The record package records with `parecord` and lists
# microphones with `pactl`, both from pulseaudio-utils. A fresh Ubuntu 26.04
# Desktop has pipewire-pulse and libpulse0 but not pulseaudio-utils, so the
# AppImage brings its own copies from the build host (release.yml installs
# pulseaudio-utils there). On Debian/Ubuntu `parecord` is a symlink to `pacat`,
# which picks its mode from its own name: the real binary is copied under the
# name `parecord`, so it records. linuxdeploy bundles their libraries below
# (--executable), and AppRun puts usr/bin first in PATH.
AUDIO_TOOLS=(parecord pactl)
for tool in "${AUDIO_TOOLS[@]}"; do
  src=$(command -v "$tool" || true)
  if [ -z "$src" ]; then
    echo "$tool not found on the build host; install pulseaudio-utils (#1608)" >&2
    exit 1
  fi
  install -m755 "$(readlink -f "$src")" "$APPDIR/usr/bin/$tool"
done
# LGPL-2.1+ notice of the bundled tools, from the host package they came from.
# linuxdeploy copies the copyright files of the libraries (libpulse0 …) into
# usr/share/doc itself, but not of executables outside dpkg's file list.
install -Dm644 /usr/share/doc/pulseaudio-utils/copyright \
  "$APPDIR/usr/share/licenses/pulseaudio-utils/copyright"

# ── 2. Run linuxdeploy ───────────────────────────────────────────────────────
# linuxdeploy bundles the executable's shared-library dependencies. The Flutter
# plugin .so files already sit in the AppDir at usr/bin/lib (copied above);
# --deploy-deps-only points linuxdeploy at them so it resolves THEIR system
# dependencies and fixes their rpath without re-copying. (There is no
# --library-path flag in linuxdeploy — that was rejected as an unknown option.)
export ARCH=x86_64
export OUTPUT="$OUT_DIR/WhisPaste-${VERSION}-linux-x64.AppImage"
install -d "$OUT_DIR"

linuxdeploy \
  --appdir "$APPDIR" \
  --executable "$APPDIR/usr/bin/whispaste" \
  --desktop-file "$APPDIR/usr/share/applications/$APP_ID.desktop" \
  --icon-file "$APPDIR/usr/share/icons/hicolor/512x512/apps/$APP_ID.png" \
  --executable "$APPDIR/usr/bin/parecord" \
  --executable "$APPDIR/usr/bin/pactl" \
  --custom-apprun "$SCRIPT_DIR/AppRun" \
  --deploy-deps-only "$APPDIR/usr/bin/lib" \
  --output appimage

echo "Built $OUTPUT"

# Guard: recording and the microphone list need both sound tools in the AppDir,
# runnable with the libraries linuxdeploy bundled (#1608). `--version` needs no
# sound server. AppRun must be ours, or the host's tools (or none) are used.
for tool in "${AUDIO_TOOLS[@]}"; do
  if [ ! -x "$APPDIR/usr/bin/$tool" ] || [ -L "$APPDIR/usr/bin/$tool" ]; then
    echo "$tool is missing from the AppImage; recording would fail" >&2
    exit 1
  fi
  deps=$(ldd "$APPDIR/usr/bin/$tool")
  if grep -q 'not found' <<<"$deps" \
    || ! grep -q "libpulse.so.0 => $APPDIR/" <<<"$deps"; then
    echo "$tool in the AppImage does not load the bundled libpulse:" >&2
    echo "$deps" >&2
    exit 1
  fi
  "$APPDIR/usr/bin/$tool" --version >/dev/null \
    || { echo "$tool in the AppImage does not run" >&2; exit 1; }
done
if ! cmp -s "$SCRIPT_DIR/AppRun" "$APPDIR/AppRun"; then
  echo "AppRun is not packaging/appimage/AppRun; the bundled sound tools would not be on PATH" >&2
  exit 1
fi
echo "Sound tools guard ok (${AUDIO_TOOLS[*]} bundled, AppRun puts usr/bin first)"

# Guard: nothing in the AppDir may need a newer GLIBC than the supported
# baseline (Ubuntu 24.04 = 2.39; whispaste#478 / #1418). Build on that base.
MAX_GLIBC="${MAX_GLIBC:-2.39}"
worst=$(find "$APPDIR" -type f \( -name '*.so*' -o -perm -u+x \) -print0 \
  | xargs -0 -r objdump -T 2>/dev/null \
  | grep -o 'GLIBC_[0-9][0-9.]*' | sed 's/^GLIBC_//' | sort -uV | tail -n1 || true)
if [ -n "$worst" ] && [ "$(printf '%s\n%s\n' "$worst" "$MAX_GLIBC" | sort -V | tail -n1)" != "$MAX_GLIBC" ]; then
  echo "AppImage requires GLIBC_$worst, above the supported baseline GLIBC_$MAX_GLIBC" >&2
  exit 1
fi
echo "GLIBC guard ok (highest required: ${worst:-none}, limit $MAX_GLIBC)"
# The undo idle gate needs libXss.so.1 (XScreenSaver). linuxdeploy bundles it
# unless its excludelist matches, so warn loudly when the release log shows no
# bundled copy; the README then keeps libxss1 as a host dependency.
bundled_xss=$(find "$APPDIR" -name 'libXss.so.1*' -print -quit)
if [ -z "$bundled_xss" ]; then
  echo "::warning::libXss.so.1 is not bundled in the AppImage; hosts need libxss1" >&2
fi


# Stable-name alias (mirrors WhisPaste-Setup.exe / WhisPaste-macos-arm64.dmg):
# the website links a version-less URL under releases/latest/download/, which
# only resolves if the asset name doesn't change every release.
STABLE_OUTPUT="$OUT_DIR/WhisPaste-linux-x64.AppImage"
cp "$OUTPUT" "$STABLE_OUTPUT"
echo "Copied stable-name alias to $STABLE_OUTPUT"
