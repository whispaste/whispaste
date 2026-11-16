#!/usr/bin/env bash
# check-crashpad-exec.test.sh — negative test for scripts/check-crashpad-exec.sh.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-crashpad-exec.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-crashpad-exec.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
failures=0
expect() { # expect <0|nonzero> <label> <args...>
  local want="$1" label="$2" rc; shift 2
  bash "$GUARD" "$@" >"$WORK/out.txt" 2>&1; rc=$?
  if [[ "$want" == 0 && $rc -eq 0 ]] || [[ "$want" == nonzero && $rc -ne 0 ]]; then
    echo "ok   - $label"
  else
    echo "FAIL - $label (exit $rc)"; cat "$WORK/out.txt"; failures=$((failures + 1))
  fi
}
mkdir -p "$WORK/b/lib" "$WORK/empty/lib"
printf 'x' > "$WORK/b/lib/crashpad_handler"
chmod 644 "$WORK/b/lib/crashpad_handler"
expect nonzero "bundle without exec bit" "$WORK/b"
expect nonzero "bundle without crashpad_handler" "$WORK/empty"
chmod 755 "$WORK/b/lib/crashpad_handler"
# NTFS under Git Bash keeps no exec bit for a plain file, so chmod 755 has no
# effect there; the guard targets Linux bundles, the positive case runs where
# the filesystem can express it.
if [ -x "$WORK/b/lib/crashpad_handler" ]; then
  expect 0 "bundle with exec bit" "$WORK/b"
else
  echo "skip - bundle with exec bit (filesystem keeps no exec bit)"
fi
if command -v dpkg-deb >/dev/null; then
  for m in 644 755; do
    s="$WORK/deb$m"; mkdir -p "$s/DEBIAN" "$s/opt/w/lib"
    printf 'Package: t\nVersion: 1\nArchitecture: all\nMaintainer: t <t@t>\nDescription: t\n' > "$s/DEBIAN/control"
    printf 'x' > "$s/opt/w/lib/crashpad_handler"; chmod "$m" "$s/opt/w/lib/crashpad_handler"
    dpkg-deb --root-owner-group -b "$s" "$WORK/$m.deb" >/dev/null 2>&1
  done
  expect nonzero ".deb without exec bit" --deb "$WORK/644.deb"
  expect 0 ".deb with exec bit" --deb "$WORK/755.deb"
fi
exit $((failures > 0))
