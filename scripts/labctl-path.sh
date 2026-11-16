#!/usr/bin/env bash
# labctl-path.sh — sourced: finds labctl the same way on every worker device (#460).
# Order: $LABCTL (an explicit override wins, even if it does not exist), then the
# shared ~/.claude/bin/labctl (config-sync puts it on every device), then labctl
# on PATH. Prints the path, or nothing when labctl is not installed; the caller
# decides what a missing labctl means. No project-specific checkout path.
labctl_find() {
  local p
  if [ -n "${LABCTL:-}" ]; then printf '%s\n' "$LABCTL"; return 0; fi
  p="$HOME/.claude/bin/labctl"
  if [ -x "$p" ]; then printf '%s\n' "$p"; return 0; fi
  command -v labctl 2>/dev/null || true
}
