#!/usr/bin/env bash
#
# publish_beta_fallback.sh — keep the beta-channel appcast from falling
# behind stable.
#
# beta-appcast-pointer (consumed by WhisPaste's Beta channel, see
# _betaAppcastFeedUrl in lib/services/auto_updater_service.dart) is normally
# only refreshed when an actual vX.Y.Z-beta.N build ships. If a long stretch
# of stable-only releases follows the last beta build, beta-channel users
# stay stuck seeing that old beta as "latest" even though many newer stable
# releases exist — Sparkle correctly treats a lower beta pre-release version
# as "not newer" than the installed one, so self-update never offers them.
#
# Fix: every STABLE release also republishes an appcast-beta.xml pointing at
# the stable release's own artifacts, so beta users always see at least the
# latest stable version as an available update. A genuinely newer beta build
# still wins afterwards through normal Sparkle version comparison — no
# client-side change needed.
#
# Guard: never overwrite beta-appcast-pointer with an OLDER core version
# than what is already published there — e.g. a hotfix stable release
# tagged after an already-shipped, more advanced beta build must not hide
# that beta from the users who already see it.
#
# Usage: publish_beta_fallback.sh <tag> <artifacts-dir>
#   <tag>            The stable release tag (vX.Y.Z, no -beta suffix).
#   <artifacts-dir>  Directory containing the release's DMG/Setup.exe — the
#                     same directory generate_appcast.sh was already run
#                     against for the stable channel.
#
# Env (required): SPARKLE_SIGNING_KEY, GITHUB_TOKEN (see generate_appcast.sh)

set -euo pipefail

TAG="${1:?Usage: publish_beta_fallback.sh <tag> <artifacts-dir>}"
ARTIFACTS_DIR="${2:?Usage: publish_beta_fallback.sh <tag> <artifacts-dir>}"
REPO="${GITHUB_REPOSITORY:-whispaste/whispaste}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NEW_CORE="${TAG#v}"
NEW_CORE="${NEW_CORE%%-*}"

EXISTING_CORE="0.0.0"
POINTER_URL="https://raw.githubusercontent.com/${REPO}/beta-appcast-pointer/appcast-beta.xml"
if curl -fsSL "$POINTER_URL" -o /tmp/existing-beta-appcast.xml 2>/dev/null; then
  EXISTING_VERSION="$(grep -o '<sparkle:shortVersionString>[^<]*' /tmp/existing-beta-appcast.xml | head -1 | sed 's/<sparkle:shortVersionString>//')"
  [[ -n "$EXISTING_VERSION" ]] && EXISTING_CORE="${EXISTING_VERSION%%-*}"
fi

NEWEST_CORE="$(printf '%s\n%s\n' "$EXISTING_CORE" "$NEW_CORE" | sort -V | tail -1)"
if [[ "$NEWEST_CORE" != "$NEW_CORE" ]]; then
  echo "beta-appcast-pointer already offers ${EXISTING_CORE} (>= stable ${NEW_CORE}) — leaving it untouched."
  exit 0
fi

echo "Publishing stable ${TAG} as the beta-channel fallback (was ${EXISTING_CORE})…"
bash "$SCRIPT_DIR/generate_appcast.sh" \
  --channel beta \
  "$TAG" \
  "$ARTIFACTS_DIR" \
  "https://github.com/${REPO}/releases/tag/${TAG#v}"

POINTER_DIR="$(mktemp -d)"
cp "$ARTIFACTS_DIR/appcast-beta.xml" "$POINTER_DIR/appcast-beta.xml"
cd "$POINTER_DIR"
git init -q -b beta-appcast-pointer
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add appcast-beta.xml
git commit -q -m "beta appcast pointer: stable fallback ${TAG}"
git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO}.git"
git push -q --force origin beta-appcast-pointer
echo "beta-appcast-pointer branch updated with stable fallback ${TAG}."
