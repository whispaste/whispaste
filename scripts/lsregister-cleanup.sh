#!/usr/bin/env bash
# lsregister-cleanup.sh — keeps LaunchServices free of WhisPaste builds that
# are about to vanish or already have. Every .app that macOS sees (a build,
# `open`, Finder) is registered under its bundle id. When its folder is later
# deleted, the registration stays: System Settings then resolves the id to the
# dead path, so dragging the app into Accessibility does nothing and grants
# land on a missing bundle (2026-10-31, five dead de.whispaste.direct.dev
# entries from removed worktree build/ folders).
#
# Usage:
#   bash scripts/lsregister-cleanup.sh <dir>...  unregister every .app under
#                                               each dir; call it BEFORE the
#                                               dir (e.g. build/) is removed
#   bash scripts/lsregister-cleanup.sh --stale   unregister de.whispaste.*
#                                               entries whose path is gone
# macOS only; elsewhere a no-op. Exit 0 always unless the usage is wrong:
# cleanup must never fail the caller.
set -uo pipefail

LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ "$(uname -s)" = "Darwin" ] && [ -x "$LSR" ] || exit 0
[ $# -gt 0 ] || { echo "usage: $0 <dir>... | --stale" >&2; exit 2; }

unregister() { # <app path>
  "$LSR" -u "$1" >/dev/null 2>&1 && echo "lsregister: unregistered $1"
}

if [ "$1" = "--stale" ]; then
  # path: precedes identifier: within each bundle record of the dump.
  "$LSR" -dump 2>/dev/null | awk '
    /^path:/ { sub(/^path: +/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); p = $0 }
    /^identifier:/ { sub(/^identifier: +/, ""); if ($0 ~ /^de\.whispaste\./) print p }
  ' | sort -u | while IFS= read -r app; do
    [ -n "$app" ] && [ ! -e "$app" ] && unregister "$app"
  done
  exit 0
fi

for dir in "$@"; do
  [ -d "$dir" ] || continue
  # Nested apps (Sparkle's Updater.app) are registered on their own and
  # `lsregister -u` on the outer bundle leaves them, so every one goes,
  # innermost first.
  find "$dir" -type d -name '*.app' 2>/dev/null | sort -r | while IFS= read -r app; do
    unregister "$app"
  done
done
exit 0
