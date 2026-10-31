#!/usr/bin/env bash
#
# WhisPaste — public path filter.
#
# Reads repo paths from stdin and prints those that are public, i.e. listed
# in .ossallowlist (an exact path, or a prefix for entries ending in "/").
# Only public paths reach the open-source export, so the name and instruction
# guards check these and leave internal files alone. Without an allowlist
# every path counts as public, so the guards fail closed.
#
# Usage: <paths> | oss-public.sh
#
set -euo pipefail

ALLOWLIST="$(git rev-parse --show-toplevel)/.ossallowlist"
if [ ! -f "$ALLOWLIST" ]; then
  cat
  exit 0
fi

awk '
  NR == FNR {
    if ($0 == "" || substr($0, 1, 1) == "#") next
    if (substr($0, length($0)) == "/") prefix[++n] = $0
    else exact[$0] = 1
    next
  }
  $0 == "" { next }
  ($0 in exact) { print; next }
  {
    for (i = 1; i <= n; i++)
      if (substr($0, 1, length(prefix[i])) == prefix[i]) { print; next }
  }
' "$ALLOWLIST" -
