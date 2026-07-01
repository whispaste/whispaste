#!/usr/bin/env bash
#
# generate_appcast.sh — deterministic signed appcast.xml for Sparkle self-updates.
#
# Self-updates (PRD Säule E) are gated on a SIGNED appcast: Sparkle (macOS)
# rejects unsigned enclosures. This script signs the macOS DMG with the EdDSA
# private key (delivered via the SPARKLE_SIGNING_KEY GitHub secret), emits a
# deterministic appcast.xml, verifies the enclosure carries an EdDSA signature,
# and uploads the feed to the GitHub release.
#
# Why sign_update and not generate_appcast? generate_appcast (the canonical
# Sparkle tool) does not reliably sign in non-interactive/keyless contexts and
# depends on Keychain access. sign_update is the lower-level signer that takes
# the key file directly and is verifiably deterministic. We template the
# (well-documented) appcast XML ourselves and sign each enclosure explicitly.
#
# Key format: SPARKLE_SIGNING_KEY is the 44-character base64 Ed25519 private
# seed exactly as exported by `generate_keys -x`. It is passed verbatim (NO
# base64 decode) to sign_update via the `--ed-key-file -` stdin form (see
# `sign_update --help`). The matching public key (SUPublicEDKey) is embedded in
# macos/Runner/Info.plist.
#
# Usage: generate_appcast.sh <tag> <artifacts-dir> [notes-url]
#
# Env (required):
#   SPARKLE_SIGNING_KEY   44-char base64 Ed25519 private key (GitHub secret)
#   GITHUB_TOKEN          token with `contents: write` for the gh upload
#
# Exit codes: 2 = signing key missing, 1 = any other failure.

set -euo pipefail

TAG="${1:?usage: generate_appcast.sh <tag> <artifacts-dir> [notes-url]}"
ARTIFACTS_DIR="${2:?missing artifacts-dir}"
NOTES_URL="${3:-https://github.com/whispaste/whispaste/releases/tag/${TAG#v}}"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.3}"

GITHUB_REPO_SLUG="${GITHUB_REPOSITORY:-whispaste/whispaste}"
VERSION="${TAG#v}"  # strip leading 'v'

# --- 0. Preconditions -------------------------------------------------------

if [[ -z "${SPARKLE_SIGNING_KEY:-}" ]]; then
  echo "ERROR: SPARKLE_SIGNING_KEY is not set — refusing to publish an unsigned appcast." >&2
  exit 2
fi

if [[ ! -d "$ARTIFACTS_DIR" ]]; then
  echo "ERROR: artifacts dir '$ARTIFACTS_DIR' does not exist." >&2
  exit 1
fi

# --- 1. Ensure the Sparkle CLI tools are available --------------------------
# `brew install sparkle` installs the Cask (a demo app), NOT the CLI tools.
# Bootstrap the official Sparkle release tarball instead. Cached under the
# home dir so repeated CI/local runs reuse it.
TOOLS_DIR="${SPARKLE_TOOLS_DIR:-$HOME/.cache/sparkle-tools}"
SIGN_UPDATE="$TOOLS_DIR/sign_update"
if [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "Bootstrapping Sparkle $SPARKLE_VERSION CLI tools → $TOOLS_DIR"
  mkdir -p "$TOOLS_DIR"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL -o "$TMP/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  tar -xJf "$TMP/sparkle.tar.xz" -C "$TMP"
  BIN="$(find "$TMP" -type d -name bin | head -1)"
  cp "$BIN/sign_update" "$BIN/generate_appcast" "$TOOLS_DIR/"
  chmod +x "$TOOLS_DIR/"*
fi

# --- helper: sign one payload with EdDSA; stdout = "<sig> <length>" ----------
# sign_update prints `sparkle:edSignature="<sig>" length="<n>"`; both are parsed.
# Non-zero exit (with a stderr message) if either field is missing, so callers
# fail loudly rather than emit an unsigned enclosure (Sparkle/WinSparkle reject
# those). The progress line goes to stderr so stdout stays the clean sig pair.
sign_enclosure() {
  local payload="$1" label="$2" out sig length
  out="$(printf '%s' "$SPARKLE_SIGNING_KEY" | "$SIGN_UPDATE" --ed-key-file - "$payload")"
  sig="$(printf '%s' "$out" | grep -o 'edSignature="[^"]*"' | head -1 | sed 's/edSignature="//;s/"//')"
  length="$(printf '%s' "$out" | grep -o 'length="[0-9]*"' | head -1 | sed 's/length="//;s/"//')"
  if [[ -z "$sig" || -z "$length" ]]; then
    echo "ERROR: sign_update did not yield edSignature/length for $label." >&2
    echo "Output was: $out" >&2
    return 1
  fi
  echo "  ${label}: edSignature=${sig:0:24}…  length=$length" >&2
  printf '%s %s' "$sig" "$length"
}

# Sparkle compares <sparkle:version> against the installed app's CFBundleVersion.
# Both are the dotted version string (CFBundleVersion=$(FLUTTER_BUILD_NAME) in
# Info.plist), so e.g. "1.2.44" > "1.2.40" offers the update and
# "1.2.44" == "1.2.44" does NOT (no update loop).
PUBDATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
APPCAST="$ARTIFACTS_DIR/appcast.xml"

# Enclosure URL base: GitHub Releases by default. WP_ENCLOSURE_BASE overrides for
# the local E2E self-update test (served from http://localhost:PORT/).
ENC_BASE="https://github.com/$GITHUB_REPO_SLUG/releases/download/$TAG"
if [[ -n "${WP_ENCLOSURE_BASE:-}" ]]; then
  ENC_BASE="${WP_ENCLOSURE_BASE%/}"
fi

# --- 2. Resolve + sign the macOS DMG (required) -----------------------------
# macOS Sparkle consumes this enclosure (sparkle:os="macos"); always present in CI.
DMG_NAME="WhisPaste-macos-arm64.dmg"
DMG="$ARTIFACTS_DIR/$DMG_NAME"
if [[ ! -f "$DMG" ]]; then
  echo "ERROR: macOS DMG not found at $DMG" >&2
  echo "Available artifacts:"; ls -la "$ARTIFACTS_DIR" >&2
  exit 1
fi
echo "Signing macOS payload…"
sig_line="$(sign_enclosure "$DMG" "$DMG_NAME")" || exit 1
read -r MAC_SIG MAC_LEN <<<"$sig_line"
MACOS_ITEM="    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
      <enclosure url=\"${ENC_BASE}/${DMG_NAME}\" sparkle:edSignature=\"${MAC_SIG}\" length=\"${MAC_LEN}\" type=\"application/octet-stream\" sparkle:os=\"macos\"/>
    </item>"

# --- 3. Resolve + sign the Windows Setup.exe (optional) ---------------------
# WinSparkle 0.9.x (vendored) consumes this enclosure (sparkle:os="windows"),
# verifying it with the SAME EdDSA pubkey embedded in the Windows runner — so one
# signed feed serves both platforms. The Setup.exe is absent during a macOS-only
# local E2E test; then we emit a macOS-only feed and skip Windows (no error).
SETUP_NAME="WhisPaste-Setup.exe"
SETUP="$ARTIFACTS_DIR/$SETUP_NAME"
WINDOWS_ITEM=""
if [[ -f "$SETUP" ]]; then
  echo "Signing Windows payload…"
  sig_line="$(sign_enclosure "$SETUP" "$SETUP_NAME")" || exit 1
  read -r WIN_SIG WIN_LEN <<<"$sig_line"
  WINDOWS_ITEM="    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <enclosure url=\"${ENC_BASE}/${SETUP_NAME}\" sparkle:edSignature=\"${WIN_SIG}\" length=\"${WIN_LEN}\" type=\"application/octet-stream\" sparkle:os=\"windows\"/>
    </item>"
else
  echo "No $SETUP_NAME in artifacts — emitting macOS-only appcast (Windows enclosure skipped)."
fi

# --- 4. Emit deterministic appcast.xml -------------------------------------
cat > "$APPCAST" <<XML
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>WhisPaste</title>
    <link>${NOTES_URL}</link>
    <description>Most recent WhisPaste releases</description>
    <language>en</language>
${MACOS_ITEM}
${WINDOWS_ITEM}
  </channel>
</rss>
XML

# --- 5. Verify the enclosure is signed -------------------------------------

ENCLOSURES="$(grep -c '<enclosure' "$APPCAST" || true)"
SIGNED="$(grep -c 'sparkle:edSignature=' "$APPCAST" || true)"
echo "Enclosures: ${SIGNED}/${ENCLOSURES} signed."
if [[ "$ENCLOSURES" -eq 0 || "$SIGNED" -ne "$ENCLOSURES" ]]; then
  echo "ERROR: appcast has unsigned enclosures — aborting (no unsigned feed published)." >&2
  exit 1
fi

echo "Wrote $APPCAST"

# --- 6. Upload to the release -----------------------------------------------
# Skipped when GITHUB_TOKEN is unset (local dry-run / E2E test harness serves
# the feed itself). In CI the token is always present.

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "Uploading appcast.xml to release $TAG…"
  gh release upload "$TAG" "$APPCAST" --clobber
  echo "OK — signed appcast published for $TAG."
else
  echo "GITHUB_TOKEN unset — skipping release upload (local mode, appcast left at $APPCAST)."
fi
