#!/usr/bin/env bash
# One-time: push the stable self-signed code-signing identity to GitHub Actions
# secrets so the release workflow can sign macOS builds (free, TCC-stable).
#
# Reads the identity created by ~/.config/whispaste-signing/gen-cert.sh.
# Run once from the repo root:  bash scripts/macos-selfsign-export-secret.sh
#
# The certificate is self-signed and has no trust value beyond providing a STABLE
# identity for TCC — its private key leaking only enables TCC-identity spoofing of
# this app, an accepted risk for this threat model. Do NOT reuse it for anything
# that relies on signature trust.
set -euo pipefail

DIR="$HOME/.config/whispaste-signing"
P12="$DIR/identity.p12"
P12_PASS="${1:-whispaste}"

[ -f "$P12" ] || { echo "Missing $P12 — run $DIR/gen-cert.sh first." >&2; exit 1; }
command -v gh >/dev/null || { echo "gh CLI not found." >&2; exit 1; }

B64="$(base64 < "$P12" | tr -d '\n')"
printf '%s' "$B64"     | gh secret set MACOS_SELFSIGN_P12_BASE64
printf '%s' "$P12_PASS" | gh secret set MACOS_SELFSIGN_P12_PASSWORD

echo "Set: MACOS_SELFSIGN_P12_BASE64, MACOS_SELFSIGN_P12_PASSWORD"
echo "Next release build will sign with the stable identity."
