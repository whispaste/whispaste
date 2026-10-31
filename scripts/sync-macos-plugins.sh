#!/usr/bin/env bash
# sync-macos-plugins.sh — writes the two generated macOS plugin files from
# pubspec.lock, macos/Podfile and the Flutter SDK in .flutter-version:
#   macos/Flutter/GeneratedPluginRegistrant.swift  (flutter pub get, then
#                                                   the #if !MAS_BUILD guard)
#   macos/Podfile.lock                             (pod install, then the
#                                                   pinned CocoaPods line)
# pod install runs without --repo-update, so pods that only Podfile.lock
# pins (Sparkle) keep their version; move them with `pod update <pod>`.
#
# Usage: bash scripts/sync-macos-plugins.sh [--stage]
#   --stage  also `git add` the two files, and only them (pre-commit).
# macOS only. Exit 0: written. 3: not written (not macOS, a tool is missing
# or failed, or another sync holds the lock); the reason is printed. Callers
# warn on 3 and never block on it: the pre-push plugin check catches a
# missed sync.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 3
REGISTRANT=macos/Flutter/GeneratedPluginRegistrant.swift
LOCKFILE=macos/Podfile.lock
STAGE=0
[ "${1:-}" = "--stage" ] && STAGE=1

skip() { echo "sync-macos-plugins: $* — not synced" >&2; exit 3; }

[ "$(uname -s)" = "Darwin" ] || skip "macOS only"
command -v flutter >/dev/null 2>&1 || skip "flutter not found"
command -v pod >/dev/null 2>&1 || skip "CocoaPods (pod) not found"

# One sync per repository at a time: worktrees share the pub cache and the
# main tree shares its index between sessions. A lock left by a dead process
# is taken over.
LOCK="$(git rev-parse --git-common-dir)/wp-macos-plugin-sync.lock"
for _ in $(seq 1 60); do
  if mkdir "$LOCK" 2>/dev/null; then
    echo $$ >"$LOCK/pid"
    break
  fi
  holder="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
    rm -rf "$LOCK"
    continue
  fi
  sleep 1
done
[ "$(cat "$LOCK/pid" 2>/dev/null)" = "$$" ] || skip "another sync holds $LOCK"
trap 'exit 3' INT TERM

bash scripts/install-git-filters.sh

# Flutter and CocoaPods must not see the variables git sets for its hooks.
tool() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_PREFIX "$@"; }

LOG="$(mktemp)"
trap 'rm -rf "$LOCK" "$LOG"' EXIT
run() { # <reason if it fails> <cmd...>
  local reason="$1"; shift
  tool "$@" >"$LOG" 2>&1 || { tail -5 "$LOG" >&2; skip "$reason"; }
}

run "flutter pub get failed (offline?)" flutter pub get
python3 macos/patch_plugin_registrant_guard.py "$REGISTRANT" >/dev/null
run "pod install failed (offline or a stale spec repo: try 'pod repo update')" \
  pod install --project-directory=macos
python3 macos/normalize_podfile_lock.py "$LOCKFILE"

if [ "$STAGE" = "1" ]; then
  git add -- "$REGISTRANT" "$LOCKFILE"
fi
echo "sync-macos-plugins: $REGISTRANT and $LOCKFILE match pubspec.lock"
