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

set_filter mas-guard "python3 macos/patch_plugin_registrant_guard.py --stdin"
set_filter podlock "python3 macos/normalize_podfile_lock.py --stdin"
