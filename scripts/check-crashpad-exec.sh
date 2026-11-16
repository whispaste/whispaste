#!/usr/bin/env bash
# check-crashpad-exec.sh — release guard (#95): crashpad_handler must keep its
# exec bit. sentry-native spawns it as a subprocess; without the bit it logs
# "failed to spawn ... crashpad_handler: Permission denied" and no native crash
# report is ever sent. The plugin copies it with install(FILES), which drops
# the bit, so every package path has to restore and verify it.
#
# Usage: scripts/check-crashpad-exec.sh <bundle-dir>
#        scripts/check-crashpad-exec.sh --deb <file.deb>
# A missing crashpad_handler is a failure (the guard never passes vacuously).
set -uo pipefail
export LC_ALL=C

fail() { echo "check-crashpad-exec: $*" >&2; exit 1; }

if [[ "${1:-}" == "--deb" ]]; then
  [[ -f "${2:-}" ]] || fail "usage: $0 --deb <file.deb>"
  line="$(dpkg-deb --contents "$2" | grep -E '/lib/crashpad_handler$' | head -n1)"
  [[ -n "$line" ]] || fail "no lib/crashpad_handler in $2"
  mode="${line%% *}"
  [[ "$mode" =~ ^-r.xr.xr.x$ ]] || fail "crashpad_handler in $2 is not executable (mode $mode)"
  echo "check-crashpad-exec: ok ($2, $mode)"
  exit 0
fi

dir="${1:-}"
[[ -d "$dir" ]] || fail "usage: $0 <bundle-dir> | --deb <file.deb>"
f="$dir/lib/crashpad_handler"
[[ -f "$f" ]] || fail "missing $f"
[[ -x "$f" ]] || fail "$f has no exec bit (mode $(stat -c %a "$f"))"
echo "check-crashpad-exec: ok ($f)"
