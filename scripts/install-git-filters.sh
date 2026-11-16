#!/usr/bin/env bash
# install-git-filters.sh — sets the git clean filters that .gitattributes
# names for the generated macOS files (idempotent, ~10 ms).
#   mas-guard: GeneratedPluginRegistrant.swift keeps the #if !MAS_BUILD
#              guard (macos/patch_plugin_registrant_guard.py);
#   podlock:   Podfile.lock keeps the pinned CocoaPods version
#              (macos/normalize_podfile_lock.py).
# Filter commands live in the local git config, not in .gitattributes, so
# every clone needs them once; the pre-commit and pre-push hooks and
# scripts/sync-macos-plugins.sh call this. The paths are relative on purpose:
# the config is shared by every worktree and git runs filters from the
# worktree root, so an absolute path would break `git status` everywhere
# once that one worktree is removed.
set -euo pipefail

set_filter() { # <name> <clean command>
  if [ "$(git config --local --get "filter.$1.clean" 2>/dev/null || true)" != "$2" ]; then
    git config --local "filter.$1.clean" "$2"
    git config --local "filter.$1.smudge" cat
    git config --local "filter.$1.required" false
  fi
}

# Python through .githooks/python3.sh (see there). The config is shared with
# worktrees on an older base that lack the script: they fall back to python3.
PY='f=.githooks/python3.sh; if [ -f "$f" ]; then exec bash "$f" "$@"; fi; exec python3 "$@"'
set_filter mas-guard "bash -c '$PY' _ macos/patch_plugin_registrant_guard.py --stdin"
set_filter podlock "bash -c '$PY' _ macos/normalize_podfile_lock.py --stdin"
