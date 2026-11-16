#!/usr/bin/env bash
#
# fetch_sparkle_test.sh — scripts/fetch-sparkle.sh unpacks the Sparkle
# tarball only when its SHA-256 matches scripts/sparkle.pin.
#
# Hermetic: a fixture tarball with a stub Sparkle.framework, a pin file in a
# temp dir and a file:// download URL; no network.
#
# Run: bash test/scripts/fetch_sparkle_test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/fetch-sparkle.sh"

PASS=0
FAIL=0
ok()   { printf '  ok   - %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }
# check <description> <0|nonzero>
check() { if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sha256() {
  if command -v shasum >/dev/null; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}

# --- fixture: Sparkle-9.9.9.tar.xz with the release layout ------------------
SRC="$WORK/src/Sparkle.framework"
mkdir -p "$SRC/Versions/B/Resources"
cat > "$SRC/Versions/B/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>CFBundleShortVersionString</key>
	<string>9.9.9</string>
</dict>
</plist>
PLIST
printf 'stub' > "$SRC/Versions/B/Sparkle"
ln -s B "$SRC/Versions/Current"
ln -s Versions/Current/Resources "$SRC/Resources"
ln -s Versions/Current/Sparkle "$SRC/Sparkle"
TARBALL="$WORK/Sparkle-9.9.9.tar.xz"
(cd "$WORK/src" && tar -cJf "$TARBALL" ./Sparkle.framework)
GOOD_SHA="$(sha256 "$TARBALL")"

pin() {
  printf 'SPARKLE_VERSION=9.9.9\nSPARKLE_SHA256=%s\n' "$1" > "$WORK/sparkle.pin"
}

run() {
  SPARKLE_PIN_FILE="$WORK/sparkle.pin" \
  SPARKLE_DOWNLOAD_URL="file://$TARBALL" \
  SPARKLE_CACHE_DIR="$WORK/cache" \
    bash "$SCRIPT" "$1" >"$WORK/out.log" 2>&1
}

echo "fetch-sparkle.sh"

bash -n "$SCRIPT"
check "script is syntax-clean" $?

# A wrong hash: nothing is unpacked, the bad download is not kept.
pin "0000000000000000000000000000000000000000000000000000000000000000"
run "$WORK/fw-bad"; rc=$?
[[ $rc -ne 0 ]]; check "wrong SHA-256 fails" $?
grep -q "SHA-256 mismatch" "$WORK/out.log"; check "wrong SHA-256 is named" $?
[[ ! -e "$WORK/fw-bad/Sparkle.framework" ]]; check "wrong SHA-256 unpacks nothing" $?
[[ ! -e "$WORK/cache/Sparkle-9.9.9.tar.xz" ]]; check "wrong SHA-256 drops the download" $?

# The pinned hash: the framework lands with its symlinks intact.
pin "$GOOD_SHA"
run "$WORK/fw"; check "pinned SHA-256 installs" $?
[[ -L "$WORK/fw/Sparkle.framework/Versions/Current" ]]; check "Versions/Current stays a symlink" $?
grep -q "<string>9.9.9</string>" "$WORK/fw/Sparkle.framework/Resources/Info.plist"
check "installed framework is the pinned version" $?

# Already there in the pinned version: no download, nothing touched.
rm -f "$WORK/cache/Sparkle-9.9.9.tar.xz"
SPARKLE_PIN_FILE="$WORK/sparkle.pin" SPARKLE_DOWNLOAD_URL="file://$WORK/missing.tar.xz" \
  SPARKLE_CACHE_DIR="$WORK/cache" bash "$SCRIPT" "$WORK/fw" >"$WORK/out.log" 2>&1
check "pinned version present: no-op without download" $?

# A cached tarball that changed after download is rejected too.
mkdir -p "$WORK/cache"
cp "$TARBALL" "$WORK/cache/Sparkle-9.9.9.tar.xz"
printf 'x' >> "$WORK/cache/Sparkle-9.9.9.tar.xz"
run "$WORK/fw-cache"; rc=$?
[[ $rc -ne 0 && ! -e "$WORK/fw-cache/Sparkle.framework" ]]
check "tampered cached tarball is rejected" $?

# The repo pin names a version and a 64-hex hash.
grep -Eq '^SPARKLE_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$REPO_ROOT/scripts/sparkle.pin"
check "repo pin has SPARKLE_VERSION" $?
grep -Eq '^SPARKLE_SHA256=[0-9a-f]{64}$' "$REPO_ROOT/scripts/sparkle.pin"
check "repo pin has SPARKLE_SHA256" $?

echo "passed $PASS, failed $FAIL"
[[ $FAIL -eq 0 ]]
