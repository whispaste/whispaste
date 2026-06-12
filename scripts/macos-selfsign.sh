#!/usr/bin/env bash
# Signs a WhisPaste .app inside-out with a STABLE self-signed code-signing
# certificate — free, no Apple Developer Program.
#
# Why: macOS binds the Accessibility (TCC) permission to the app's *designated
# requirement* (signing identity). An ad-hoc build's requirement is cdhash-based
# and changes on every build, so the permission is lost on every update. Signing
# with one stable certificate makes the requirement identity-based
# (`identifier "<bundle-id>" and certificate root = H"<cert>"`), constant across
# builds — so the permission PERSISTS across updates.
#
# This does NOT notarize (that needs the paid program). The one-time Gatekeeper
# "unidentified developer" warning on a quarantined browser download remains; the
# in-app updater bypasses it (programmatic download sets no quarantine attribute).
#
# Usage: macos-selfsign.sh <App.app> <entitlements.plist>
# Env:   MACOS_SELFSIGN_P12_BASE64    base64 of the stable .p12 identity
#        MACOS_SELFSIGN_P12_PASSWORD  its export password
#        MACOS_SELFSIGN_IDENTITY      cert common name (default "WhisPaste Code Signing")
set -euo pipefail

APP="${1:?usage: macos-selfsign.sh <App.app> <entitlements.plist>}"
ENT="${2:?entitlements plist required}"
: "${MACOS_SELFSIGN_P12_BASE64:?MACOS_SELFSIGN_P12_BASE64 env required}"
: "${MACOS_SELFSIGN_P12_PASSWORD:?MACOS_SELFSIGN_P12_PASSWORD env required}"
IDENTITY="${MACOS_SELFSIGN_IDENTITY:-WhisPaste Code Signing}"
[ -d "$APP" ] || { echo "no such bundle: $APP" >&2; exit 1; }

TMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KEYCHAIN="$TMP/wp-selfsign.keychain-db"
KCPASS="$(openssl rand -hex 16)"
P12="$TMP/wp-selfsign.p12"

cleanup() { security delete-keychain "$KEYCHAIN" 2>/dev/null || true; rm -f "$P12"; }
trap cleanup EXIT

printf '%s' "$MACOS_SELFSIGN_P12_BASE64" | base64 --decode > "$P12"

security create-keychain -p "$KCPASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$KCPASS" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$MACOS_SELFSIGN_P12_PASSWORD" -T /usr/bin/codesign -A
# Keep existing keychains searchable so codesign and the build still work.
EXISTING="$(security list-keychains -d user | sed 's/[" ]//g')"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $EXISTING
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KEYCHAIN" >/dev/null
rm -f "$P12"

echo "Signing nested code (deepest first)…"
find "$APP/Contents" \( -name '*.framework' -o -name '*.dylib' -o -name '*.app' -o -name '*.xpc' \) -print0 2>/dev/null \
  | awk -v RS='\0' '{print length, $0}' | sort -rn | cut -d' ' -f2- \
  | while IFS= read -r item; do
      [ "$item" = "$APP" ] && continue
      codesign --force --timestamp=none --sign "$IDENTITY" --keychain "$KEYCHAIN" "$item"
    done

echo "Signing main bundle with entitlements…"
codesign --force --timestamp=none --sign "$IDENTITY" --keychain "$KEYCHAIN" \
  --entitlements "$ENT" "$APP"

echo "Verifying…"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Designated requirement (must be identity-based, stable across builds):"
codesign -d -r- "$APP" 2>&1 | grep designated
