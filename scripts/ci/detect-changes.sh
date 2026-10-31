#!/usr/bin/env bash
# detect-changes.sh <before-sha> <after-sha> <full:true|false>
# Writes app/platform_full/native_windows/native_macos/website=true|false to $GITHUB_OUTPUT so ci.yml can skip
# jobs a push cannot affect. Fails open: an unknown base (new branch,
# force-push, shallow miss) or a non-push event runs everything.
set -euo pipefail

before="$1"; after="$2"; full="$3"
out="${GITHUB_OUTPUT:-/dev/stdout}"

all_true() {
  { echo "app=true"; echo "platform_full=true"; echo "native_windows=true"
    echo "native_macos=true"; echo "website=true"; } >> "$out"
  echo "app=true platform_full=true native_windows=true native_macos=true website=true (full run)"
  exit 0
}

[ "$full" = "true" ] && all_true
case "$before" in ''|0000000000000000000000000000000000000000) all_true ;; esac
# Fetch the base only when it is missing (CI's depth-1 checkout). A local
# run in a full clone must not fetch with --depth: worktrees share .git, so
# that would turn the maintainer's whole repo shallow.
git cat-file -e "$before^{commit}" 2>/dev/null \
  || git fetch --quiet --depth=1 origin "$before" 2>/dev/null || all_true
files=$(git diff --name-only "$before" "$after") || all_true

echo "Changed files:"; echo "$files"

# The workflow and its helper scripts affect every job.
if echo "$files" | grep -qE '^(\.github/workflows/ci\.yml|scripts/ci/)'; then
  all_true
fi

has() { echo "$files" | grep -qE "$1" && echo true || echo false; }

# App: anything that is not website, prose docs, or another workflow.
app=$(echo "$files" \
  | grep -vE '^website/|^docs/|\.md$|^\.github/|^\.githooks/|^\internal-notes|^\.claude/' \
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

# Native code of one OS (runner, shared native sources, plugin packages,
# dependency pins): only then does a dev push build that OS (decision 14a).
native_windows=$(has '^pubspec\.(yaml|lock)$|^(windows|native|packages)/')
native_macos=$(has '^pubspec\.(yaml|lock)$|^(macos|native|packages)/')

{ echo "app=$app"; echo "platform_full=$platform_full"; echo "native_windows=$native_windows"
  echo "native_macos=$native_macos"; echo "website=$website"; } >> "$out"
echo "app=$app platform_full=$platform_full native_windows=$native_windows native_macos=$native_macos website=$website"
