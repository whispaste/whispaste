#!/usr/bin/env bash
#
# WhisPaste — agent instruction guard.
#
# Agent instruction and internal context files are internal: they are
# versioned in the internal repository but must never reach the public
# export — at any depth, even nested inside an allowlisted directory
# (maintainer 2026-10-31: instruction files of every CLI or agent tool are
# internal). Only public paths (.ossallowlist, see oss-public.sh) are checked. Covered: Claude Code (CLAUDE*.md, .claude/), CONTEXT.md, the
# AGENTS.md family (Codex, Jules, Pi, OpenCode, Amp and others), Gemini,
# Jules, Codex, Copilot, Cursor, Windsurf, Cline, Roo, Kiro, Junie, Aider,
# Continue, Amazon Q, Augment, Goose, Qwen, Crush, Warp, Trae, OpenHands and
# generic agent/skill folders. A new tool's file goes into RX and
# .gitignore together.
#
# Usage: instruction-guard.sh staged — public paths of the index block;
# internal ones are versioned on purpose and only get a note. The export
# gate checks what reaches GitHub.
#
# Bash-3.2-compatible (macOS /bin/bash).
#
set -euo pipefail

FILES='CLAUDE(\.local)?\.md|CONTEXT\.md|AGENTS?(\.override|\.local)?\.md|GEMINI\.md|JULES\.md|CODEX\.md|QWEN\.md|CRUSH\.md|WARP\.md|\.cursorrules|\.windsurfrules|\.clinerules|\.roorules|\.goosehints|\.augment-guidelines|\.aider[^/]*|copilot-instructions\.md|[^/]+\.instructions\.md|[^/]+\.prompt\.md|[^/]+\.chatmode\.md'
DIRS='\.claude|\.gemini|\.jules|\.codex|\.cursor|\.windsurf|\.clinerules|\.roo|\.kiro|\.junie|\.continue|\.amazonq|\.augment|\.qwen|\.crush|\.trae|\.openhands|\.opencode|\.agent|\.agents|\.skills'
RX="(^|/)($FILES)\$|(^|/)($DIRS)/"

PUBLIC="$(dirname "$0")/oss-public.sh"

scan() {
  local paths hits
  paths="$(cat)"
  if [ -n "$paths" ] && printf '%s\n' "$paths" | grep -qE -- "$RX"; then
    hits="$(printf '%s\n' "$paths" | "$PUBLIC" | grep -E -- "$RX" || true)"
    [ -n "$hits" ] || echo "instruction-guard: note — agent instruction files committed (internal, never exported)" >&2
  fi
  [ -z "${hits:-}" ] && return 0
  echo "╳ instruction-guard: BLOCKED — private agent instruction file ($1):" >&2
  printf '%s\n' "$hits" | sed 's/^/    /' >&2
  echo "  These files stay internal: move them out of the public path or out of .ossallowlist." >&2
  exit 1
}

mode="${1:-}"
case "$mode" in
  staged)
    git diff --cached --name-only --diff-filter=ACMR | scan "staged path"
    ;;
  *)
    echo "usage: instruction-guard.sh staged" >&2
    exit 2
    ;;
esac
