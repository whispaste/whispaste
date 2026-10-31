#!/usr/bin/env bash
#
# WhisPaste — agent instruction guard.
#
# Agent instruction and internal context files are private and must never
# reach the public repository — at any depth, even when forced past
# .gitignore with `git add -f` or nested inside an allowlisted directory
# (maintainer 2026-10-31: instruction files of every CLI or agent tool are
# internal). Covered: Claude Code (CLAUDE*.md, .claude/), CONTEXT.md, the
# AGENTS.md family (Codex, Jules, Pi, OpenCode, Amp and others), Gemini,
# Jules, Codex, Copilot, Cursor, Windsurf, Cline, Roo, Kiro, Junie, Aider,
# Continue, Amazon Q, Augment, Goose, Qwen, Crush, Warp, Trae, OpenHands and
# generic agent/skill folders. A new tool's file goes into RX and
# .gitignore together.
#
# Usage (all modes exit 1 and list the offending paths on a match):
#   instruction-guard.sh staged           paths of the index
#   instruction-guard.sh tree <rev>       every path of a tree
#   instruction-guard.sh range <range>    paths added/changed in a rev range
#
# Bash-3.2-compatible (macOS /bin/bash).
#
set -euo pipefail

FILES='CLAUDE(\.local)?\.md|CONTEXT\.md|AGENTS?(\.override|\.local)?\.md|GEMINI\.md|JULES\.md|CODEX\.md|QWEN\.md|CRUSH\.md|WARP\.md|\.cursorrules|\.windsurfrules|\.clinerules|\.roorules|\.goosehints|\.augment-guidelines|\.aider[^/]*|copilot-instructions\.md|[^/]+\.instructions\.md|[^/]+\.prompt\.md|[^/]+\.chatmode\.md'
DIRS='\.claude|\.gemini|\.jules|\.codex|\.cursor|\.windsurf|\.clinerules|\.roo|\.kiro|\.junie|\.continue|\.amazonq|\.augment|\.qwen|\.crush|\.trae|\.openhands|\.opencode|\.agent|\.agents|\.skills'
RX="(^|/)($FILES)\$|(^|/)($DIRS)/"

scan() {
  local hits
  hits="$(grep -E -- "$RX" || true)"
  [ -z "$hits" ] && return 0
  echo "╳ instruction-guard: BLOCKED — private agent instruction file ($1):" >&2
  printf '%s\n' "$hits" | sed 's/^/    /' >&2
  echo "  These files stay local (gitignored). Unstage: git restore --staged <path>" >&2
  exit 1
}

mode="${1:-}"
case "$mode" in
  staged)
    git diff --cached --name-only --diff-filter=ACMR | scan "staged path"
    ;;
  tree)
    git ls-tree -r --name-only "${2:?rev}" | scan "path in ${2}"
    ;;
  range)
    # shellcheck disable=SC2086
    git log --name-only --diff-filter=ACMR --format='' ${2:?range} | scan "path in ${2}"
    ;;
  *)
    echo "usage: instruction-guard.sh staged|tree <rev>|range <range>" >&2
    exit 2
    ;;
esac
