#!/usr/bin/env bash
# Owner-only: approve one production release (main push + stable tag).
# Usage: bash scripts/approve-release.sh v1.4.0
# Records the full SHA the local tag points at in the approval file that
# .githooks/pre-push checks. Agents must never run this script themselves.
set -euo pipefail

tag="${1:?usage: approve-release.sh vX.Y.Z}"
file="${WP_RELEASE_APPROVAL_FILE:-$HOME/.config/whispaste/release-approval}"
sha="$(git rev-parse "$tag^{commit}")"

mkdir -p "$(dirname "$file")"
echo "$sha" >>"$file"
chmod 600 "$file"
echo "approved $tag → $sha"
git log -1 --format='  %h %s' "$sha"
