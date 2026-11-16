#!/usr/bin/env bash
# sdk-env.test.sh — scripts/sdk-env.sh runs flutter and dart without the
# git variables a hook sets, and leaves them in place for everything else;
# no hook takes the SDK path from `command -v` (the wrapper's name).
# Stub flutter/dart on PATH print what they see; no SDK needed.
# Run: bash scripts/sdk-env.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sdk-env.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

for tool in flutter dart; do
  # shellcheck disable=SC2016  # expanded by the stub, not here
  printf '#!/bin/sh\necho "%s GIT_DIR=${GIT_DIR-unset} GIT_INDEX_FILE=${GIT_INDEX_FILE-unset} GIT_WORK_TREE=${GIT_WORK_TREE-unset} GIT_PREFIX=${GIT_PREFIX-unset} args=$*"\n' "$tool" >"$WORK/$tool"
  chmod +x "$WORK/$tool"
done

failures=0
out="$(
  export PATH="$WORK:$PATH" GIT_DIR=/repo/.git GIT_INDEX_FILE=/repo/.git/index.tmp \
    GIT_WORK_TREE=/repo GIT_PREFIX=lib/
  # shellcheck disable=SC1091  # scripts/sdk-env.sh: two wrapper functions
  . "$HERE/sdk-env.sh"
  flutter pub get
  dart format lib
  echo "shell GIT_INDEX_FILE=$GIT_INDEX_FILE"
)"

check() {
  if printf '%s\n' "$out" | grep -qxF -- "$2"; then
    echo "ok   - $1"
  else
    echo "FAIL - $1"
    printf '%s\n' "$out" | sed 's/^/       /'
    failures=$((failures + 1))
  fi
}
check "flutter runs without the git variables" \
  "flutter GIT_DIR=unset GIT_INDEX_FILE=unset GIT_WORK_TREE=unset GIT_PREFIX=unset args=pub get"
check "dart runs without the git variables" \
  "dart GIT_DIR=unset GIT_INDEX_FILE=unset GIT_WORK_TREE=unset GIT_PREFIX=unset args=format lib"
check "the hook's own index stays set" "shell GIT_INDEX_FILE=/repo/.git/index.tmp"

# Behind the wrappers `command -v flutter` prints the function name, not a
# path; whoever needs the SDK path asks for it with `type -P`.
uses="$(grep -nE '\$\(command -v (flutter|dart)\)' "$HERE/../.githooks/"* "$HERE/check.sh" "$HERE/sync-macos-plugins.sh" 2>/dev/null)"
if [ -z "$uses" ]; then
  echo "ok   - no hook resolves the SDK path with command -v"
else
  echo "FAIL - SDK path via command -v (use type -P):"
  printf '%s\n' "$uses" | sed 's/^/       /'
  failures=$((failures + 1))
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
