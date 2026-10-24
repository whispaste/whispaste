#!/usr/bin/env bash
# ci-gates.sh — the cheap repo-wide gates, defined once for CI and the local hooks.
#
# CI (.github/workflows/ci.yml, job "Secret scan & change detection") and the
# git hooks (.githooks/pre-commit, .githooks/pre-push) all call this script.
# No other file may carry a copy of these checks: a gate that exists only in
# CI is found by a red run, which is exactly how the logging gate broke every
# dev push from 2026-10-20 on. scripts/check-workflow-hygiene.sh fails if a
# gate defined here is not wired into ci.yml and the pre-push hook.
#
# Usage: bash scripts/ci-gates.sh [gate ...]     (no argument = all gates)
#
#   logging   dev.log()/debugPrint() outside the AppLogger allowlist (LOGGING.md)
#   secrets   built-in secret patterns over the tree (gitleaks runs separately)
#
# Each gate prints a line on success and returns non-zero on a finding.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Files that may call dev.log()/debugPrint() directly. Every entry needs a
# reason in LOGGING.md ("Ausnahmen"). The first five are the logging/crash
# layer itself (routing their diagnostics through AppLogger would recurse);
# install_id.dart is the crash reporter's own id source (crash_reporter.dart
# imports it), so logging via AppLogger would close the cycle
# install_id -> app_logger -> crash_reporter -> install_id on the bootstrap path.
LOGGING_ALLOWED='lib/core/logging/app_logger\.dart|lib/core/logging/app_monitoring\.dart|lib/core/logging/crash_reporter\.dart|lib/core/logging/crash_reporting_consent\.dart|lib/core/logging/install_id\.dart|lib/services/floating_overlay/overlay_render_channel\.dart|_render_entrypoint\.dart'

# Annotations only mean something on a GitHub runner; plain text elsewhere.
# Invoked by name through gate_$g / annotate_error below.
# shellcheck disable=SC2329
annotate_error() {
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "::error::$1"
  else
    echo "ERROR: $1" >&2
  fi
}

# Invoked by name through gate_$g / annotate_error below.
# shellcheck disable=SC2329
gate_logging() {
  echo 'Checking for logging calls that bypass AppLogger...'
  local matches
  matches=$(grep -rEln 'dev\.log\(|debugPrint\(' --include='*.dart' lib \
    | grep -Ev "$LOGGING_ALLOWED" || true)
  if [ -n "$matches" ]; then
    echo "$matches"
    annotate_error "Found dev.log()/debugPrint() outside the AppLogger allowlist. Use AppLogger instead (see LOGGING.md)."
    return 1
  fi
  echo 'No stray dev.log/debugPrint calls found'
}

# Invoked by name through gate_$g / annotate_error below.
# shellcheck disable=SC2329
gate_secrets() {
  echo 'Scanning for potential secrets...'
  local pattern='(sk-[a-zA-Z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36}|password\s*=\s*"[^"]+")'
  local matches
  matches=$(grep -rEn "$pattern" \
    --include='*.dart' --include='*.swift' \
    --include='*.yaml' --include='*.yml' \
    --include='*.json' --include='*.md' \
    --include='*.ts' --include='*.js' \
    --exclude-dir=.git --exclude-dir=build --exclude-dir=node_modules . || true)
  if [ -n "$matches" ]; then
    echo "$matches" | grep -oE '^[^:]+:[0-9]+'
    annotate_error "Potential secrets detected in source files."
    return 1
  fi
  echo 'No secrets found'
}

# Known gates, in run order. Adding one means adding gate_<name>() above and
# listing it here; the hygiene guard checks both.
ALL_GATES="logging secrets"

if [ "${1:-}" = "--list" ]; then
  echo "$ALL_GATES"
  exit 0
fi

gates=("$@")
if [ ${#gates[@]} -eq 0 ]; then
  # shellcheck disable=SC2206
  gates=($ALL_GATES)
fi

status=0
for g in "${gates[@]}"; do
  case " $ALL_GATES " in
    *" $g "*) ;;
    *) echo "ci-gates: unknown gate '$g' (known: $ALL_GATES)" >&2; exit 2 ;;
  esac
  "gate_$g" || status=1
done
exit $status
