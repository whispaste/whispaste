#!/usr/bin/env bash
# detect-changes.sh <before-sha> <after-sha> <full:true|false>
# Writes app/platform_full/website/golden=true|false to $GITHUB_OUTPUT so ci.yml can skip
# jobs a push cannot affect. Fails open: an unknown base (new branch,
# force-push, shallow miss) or a non-push event runs everything.
set -euo pipefail

before="$1"; after="$2"; full="$3"
out="${GITHUB_OUTPUT:-/dev/stdout}"

all_true() {
  { echo "app=true"; echo "platform_full=true"; echo "website=true"; echo "golden=true"; } >> "$out"
  echo "app=true platform_full=true website=true golden=true (full run)"
  exit 0
}

[ "$full" = "true" ] && all_true
case "$before" in ''|0000000000000000000000000000000000000000) all_true ;; esac
git fetch --quiet --depth=1 origin "$before" 2>/dev/null || all_true
files=$(git diff --name-only "$before" "$after") || all_true

echo "Changed files:"; echo "$files"

# The workflow and its helper scripts affect every job.
if echo "$files" | grep -qE '^(\.github/workflows/ci\.yml|scripts/ci/)'; then
  all_true
fi

has() { echo "$files" | grep -qE "$1" && echo true || echo false; }

# App: anything that is not website, prose docs, or another workflow.
app=$(echo "$files" \
  | grep -vE '^website/|^docs/|\.md$|^\.github/|^\.githooks/|^\.scratch/|^\.claude/' \
  | grep -q . && echo true || echo false)
website=$(has '^website/')
# Windows/macOS normally run only the tests that branch on the platform
# themselves. A platform branch in app code can break any test that reaches
# it (c1d9540c: a Linux-only branch in lib/ failed 335 tests), so such
# changes — and plugin/native changes — get the complete suite there too.
platform_full=false
if echo "$files" | grep -qE '^pubspec\.(yaml|lock)$|^(windows|macos|linux|packages)/'; then
  platform_full=true
else
  while IFS= read -r f; do
    case "$f" in lib/*.dart) ;; *) continue ;; esac
    if [ -f "$f" ] && grep -qE 'Platform\.is(Windows|MacOS|Linux)|defaultTargetPlatform' "$f"; then
      platform_full=true
      break
    fi
  done <<< "$files"
fi
# Golden baselines render widgets, theme, strings, fonts/assets and the
# overlay. Deeper dependencies (providers, data layer) are left to the
# weekly full run and the local pre-commit golden reminder.
golden=$(has '^lib/(features|widgets|core/theme|core/l10n|l10n|services/floating_overlay)/|^lib/app\.dart$|^assets/|^fonts/|golden|^test/(screenshots|fixtures)/|^pubspec\.(yaml|lock)$|^l10n\.yaml$')

{ echo "app=$app"; echo "platform_full=$platform_full"; echo "website=$website"; echo "golden=$golden"; } >> "$out"
echo "app=$app platform_full=$platform_full website=$website golden=$golden"
