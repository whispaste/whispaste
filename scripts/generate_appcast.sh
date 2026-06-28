#!/usr/bin/env bash
#
# generate_appcast.sh — build & upload the Sparkle/WinSparkle appcast feed.
#
# Self-updates (PRD Säule E) are gated on a SIGNED appcast: Sparkle (macOS) and
# WinSparkle (Windows) reject unsigned enclosures. This script signs every
# release artifact with the EdDSA private key (delivered via the
# SPARKLE_SIGNING_KEY GitHub secret), emits appcast.xml, verifies that every
# enclosure carries a signature, and uploads the feed to the release.
#
# Contract (see docs/signing-key-setup.md §5):
#   1. Decode SPARKLE_SIGNING_KEY (base64) → temp PEM
#   2. generate_appcast --ed-key-file <pem> <artifacts-dir>   (signs enclosures)
#   3. shred the temp PEM immediately
#   4. Verify EVERY <enclosure> has a signature → else abort (no unsigned feed)
#   5. Upload appcast.xml to the GitHub release
#
# Usage:
#   generate_appcast.sh <tag> <release-notes-url> [artifacts-dir]
#
# Env (required):
#   SPARKLE_SIGNING_KEY   base64-encoded Ed25519 private PEM (GitHub secret)
#   GITHUB_TOKEN          token with `contents: write` for the gh upload
#
# Exit codes: 2 = signing key missing, 1 = any other failure.

set -euo pipefail

TAG="${1:?usage: generate_appcast.sh <tag> <release-notes-url> [artifacts-dir]}"
NOTES_URL="${2:?missing release-notes URL}"
ARTIFACTS_DIR="${3:-dist}"

# --- 0. Preconditions -------------------------------------------------------

if [[ -z "${SPARKLE_SIGNING_KEY:-}" ]]; then
  echo "ERROR: SPARKLE_SIGNING_KEY is not set — refusing to publish an unsigned appcast." >&2
  exit 2
fi

if ! command -v generate_appcast >/dev/null 2>&1; then
  echo "ERROR: 'generate_appcast' not found (brew install sparkle)." >&2
  exit 1
fi

if [[ ! -d "$ARTIFACTS_DIR" ]]; then
  echo "ERROR: artifacts dir '$ARTIFACTS_DIR' does not exist." >&2
  exit 1
fi

# --- 1. Decode the private key into a temp PEM, scrubbed on exit -------------

KEY_PEM="$(mktemp -t sparkle_key.XXXXXX.pem)"
cleanup() {
  if [[ -f "$KEY_PEM" ]]; then
    # Best-effort secure delete; fall back to rm where shred is absent (macOS).
    shred -u "$KEY_PEM" 2>/dev/null || rm -f "$KEY_PEM"
  fi
}
trap cleanup EXIT

printf '%s' "$SPARKLE_SIGNING_KEY" | base64 --decode > "$KEY_PEM"

# --- 2. Sign enclosures & emit appcast.xml ----------------------------------

echo "Signing $ARTIFACTS_DIR/* and generating appcast.xml…"
generate_appcast \
  --ed-key-file "$KEY_PEM" \
  --link "$NOTES_URL" \
  "$ARTIFACTS_DIR"

APPCAST="$ARTIFACTS_DIR/appcast.xml"
if [[ ! -f "$APPCAST" ]]; then
  echo "ERROR: generate_appcast did not produce $APPCAST." >&2
  exit 1
fi

# --- 3. Verify every enclosure is signed ------------------------------------

ENCLOSURES="$(grep -c '<enclosure' "$APPCAST" || true)"
SIGNED="$(grep -c 'edSignature=' "$APPCAST" || true)"
echo "Enclosures: ${SIGNED}/${ENCLOSURES} signed."

if [[ "$ENCLOSURES" -eq 0 ]]; then
  echo "ERROR: appcast contains no enclosures — nothing to publish." >&2
  exit 1
fi
if [[ "$SIGNED" -ne "$ENCLOSURES" ]]; then
  echo "ERROR: $((ENCLOSURES - SIGNED)) enclosure(s) unsigned — aborting." >&2
  exit 1
fi

# --- 4. Upload to the release -----------------------------------------------

echo "Uploading $APPCAST to release $TAG…"
gh release upload "$TAG" "$APPCAST" --clobber

echo "OK — signed appcast published for $TAG."
