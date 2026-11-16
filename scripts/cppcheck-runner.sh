#!/usr/bin/env bash
# cppcheck-runner.sh — the one cppcheck invocation for windows/runner/, run by
# CI (ci.yml, Windows job) and the pre-commit hook, so both report the same
# findings: same version (scripts/cppcheck.pin), same checks, same
# suppressions (windows/runner/.cppcheck-suppress).
#
# Usage: bash scripts/cppcheck-runner.sh [<cppcheck binary>]   (default: cppcheck)
# Exit 0: clean. 1: findings (printed). 2: cppcheck missing, did not run a
# real analysis, or (in CI) is not the pinned version. Locally another
# version only warns: its findings may differ from CI's.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
CPPCHECK="${1:-cppcheck}"
# shellcheck disable=SC1091
. scripts/cppcheck.pin

version="$("$CPPCHECK" --version 2>/dev/null | sed -n 's/^Cppcheck //p' | tr -d '\r')"
if [ -z "$version" ]; then
  echo "cppcheck-runner: $CPPCHECK not found" >&2
  exit 2
fi
if [ "$version" != "$CPPCHECK_VERSION" ]; then
  if [ -n "${CI:-}" ]; then
    echo "cppcheck-runner: cppcheck $version, the pin is $CPPCHECK_VERSION" >&2
    exit 2
  fi
  echo "cppcheck-runner: warning: local cppcheck $version, CI runs $CPPCHECK_VERSION (scripts/cppcheck.pin); findings may differ" >&2
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
# The exit code is not trusted: cppcheck has exited non-zero without any
# finding (run 31871493722). The printed findings and "Checking" lines decide.
"$CPPCHECK" \
  --enable=style,warning,performance,portability \
  --std=c++17 \
  --platform=win64 \
  --suppressions-list=windows/runner/.cppcheck-suppress \
  --inline-suppr \
  --template='{file}({line}): {severity} ({id}): {message}' \
  -j "${CPPCHECK_JOBS:-2}" \
  windows/runner/ >"$log" 2>&1

findings="$(grep -E '\): (error|warning|style|performance|portability) \(' "$log")"
if [ -n "$findings" ]; then
  echo "$findings"
  echo "cppcheck-runner: $(printf '%s\n' "$findings" | wc -l | tr -d ' ') finding(s), cppcheck $version" >&2
  exit 1
fi
if grep -q '^cppcheck: error:' "$log" || ! grep -q '^Checking ' "$log"; then
  tail -20 "$log" >&2
  echo "cppcheck-runner: cppcheck did not complete a real analysis" >&2
  exit 2
fi
echo "cppcheck-runner: clean (cppcheck $version)"
