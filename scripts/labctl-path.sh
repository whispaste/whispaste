#!/usr/bin/env bash
# labctl-path.sh — sourced: finds labctl the same way on every worker device (#460).
# Order: $LABCTL (an explicit override wins, even if it does not exist), then the
# shared ~/.claude/bin/labctl (config-sync puts it on every device), then labctl
# on PATH, then the lab's own checkout (~/Developer/repos/internal-repo/bin/labctl):
# the release Mac had labctl only there on the first real release run (#1722). Prints the
# path, or nothing when labctl is not installed; the caller decides what a missing labctl means.
labctl_find() {
  local p
  if [ -n "${LABCTL:-}" ]; then printf '%s\n' "$LABCTL"; return 0; fi
  p="$HOME/.claude/bin/labctl"
  if [ -x "$p" ]; then printf '%s\n' "$p"; return 0; fi
  if command -v labctl 2>/dev/null; then return 0; fi
  p="$HOME/Developer/repos/internal-repo/bin/labctl"
  if [ -x "$p" ]; then printf '%s\n' "$p"; fi
  return 0
}
