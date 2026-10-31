#!/usr/bin/env bash
# check.sh — one entry point for the local checks, staged like CI.
#
#   bash scripts/check.sh commit          gates + format + analyze (pre-commit)
#   bash scripts/check.sh push [<range>]  gates + the tests the range can
#                                         break (pre-push), default
#                                         origin/dev...HEAD
#   bash scripts/check.sh tests [<range>] only those tests (.githooks/pre-push,
#                                         which runs the gates itself)
#   bash scripts/check.sh full            the complete suite (integration
#                                         round, before a release)
#
# The commands are the ones CI runs (.github/workflows/ci.yml): the repo gates
# come from scripts/ci-gates.sh, analyze has CI's scope, and the tests run the
# same files with the same tag excludes. CI keeps the full suite per dev push;
# the push tier makes sure a red test is found before that push, not by it.
#
# "Tests the range can break" (tool/affected_tests.dart): changed tests, tests
# that import a changed Dart file transitively, and guard tests that read a
# changed path. Selected tests that branch on the host platform also run on
# Windows, because a Linux run cannot see their Windows branch.
#
# Where tests run: through ~/.claude/infrastructure/test-dispatch/wp-test.sh
# when it exists (maintainer machines: test-lab VMs, never a bare
# `flutter test` on the Mac), otherwise plain `flutter test` (contributors).
#
# The push tier is the fast lane and never holds a push up for long:
#   WP_PUSH_TEST_BUDGET   total seconds incl. waiting (300); what does not
#                         fit is listed and left to CI, no block
#   WP_PUSH_MAX_DISTANCE  import distance of the tests run (1: changed tests,
#                         guards, direct importers); farther ones are left
#                         to CI
#   WP_PUSH_UBU_WAIT      seconds to wait for a lab ubu guest (default: the
#                         rest of the budget), then a warning listing the
#                         unverified tests; never a Dart test run on the Mac
#   WP_PUSH_WIN_WAIT      seconds to wait for the lab's Windows guest (60)
#                         for the platform-branching files, then a warning
#                         listing them
#   WP_PUSH_CHUNK         test files per run (40), nearest first, so a
#                         budget stop loses only the running chunk
# Only red tests block (exit 10). A busy lab, a timeout or a broken run of
# the test infrastructure warns and lets the push through. WP_TEST overrides
# the dispatcher path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091  # scripts/sdk-env.sh: two wrapper functions
. "$ROOT/scripts/sdk-env.sh"

EXCLUDE_TAGS='canary,perf,ux-screens,store,capture'
WP_TEST="${WP_TEST:-$HOME/.claude/infrastructure/test-dispatch/wp-test.sh}"
ANALYZE_SCOPE=(lib test integration_test tool)

usage() { sed -n '2,12p' "$0"; exit 2; }

# run_tests <host|auto> <file...>: one test run, through the dispatcher when
# available. An empty file list means the whole suite.
run_tests() {
  local host="$1"; shift
  if [ -x "$WP_TEST" ]; then
    local host_args=()
    [ "$host" != auto ] && host_args=(--host "$host")
    "$WP_TEST" run "$ROOT" "${host_args[@]}" --exclude-tags="$EXCLUDE_TAGS" "$@"
  elif [ "$host" = auto ]; then
    flutter test --exclude-tags="$EXCLUDE_TAGS" "$@"
  else
    echo "check: no test dispatcher, the $host run is left to CI." >&2
  fi
}

tier_commit() {
  bash scripts/ci-gates.sh
  dart format --output=none --set-exit-if-changed lib test tool
  flutter analyze --fatal-infos --fatal-warnings "${ANALYZE_SCOPE[@]}"
}

tier_push() {
  bash scripts/ci-gates.sh
  tier_tests "$@"
}

# kill_tree <pid>: the dispatcher runs below a subshell; stop all of it so a
# lab job releases its lock (the dispatcher cleans up on SIGTERM).
kill_tree() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$child"; done
  kill -TERM "$1" 2>/dev/null || true
}

# capped <seconds> <cmd...>: run cmd, stop it after <seconds>; rc 124 then.
capped() {
  local secs="$1"; shift
  [ "$secs" -le 0 ] && return 124
  "$@" &
  local pid=$! end=$((SECONDS + secs))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$end" ]; then
      kill_tree "$pid"; wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 2
  done
  wait "$pid"
}

# main_run <file...>: the Linux-side run of one batch within the budget, on a
# lab ubu guest only: Dart tests never run on the Mac (maintainer rule), so a
# busy lab means waiting, up to WP_PUSH_UBU_WAIT or the rest of the budget.
# rc 75: no guest freed up, rc 124: budget used up.
main_run() {
  [ -x "$WP_TEST" ] || { capped "$(budget_left)" run_tests auto "$@"; return; }
  WP_QUEUE_TIMEOUT="${WP_PUSH_UBU_WAIT:-$(budget_left)}" capped "$(budget_left)" run_tests ubu "$@"
}

budget_left() { echo $((DEADLINE - SECONDS)); }

# Paths that no test reads: a range of only these skips the selection.
NO_TEST_PATHS='^(docs/|\internal-notes|website/|[^/]*\.md$|LICENSE$|\.gitignore$|\.ossallowlist$)'

# red_tests <log>: whether a failed run reports failing or unloadable tests,
# as opposed to a run the infrastructure broke off (lock, VM, network).
red_tests() { grep -qE 'Some tests failed|Failed to load|\[E\]' "$1"; }

# list_skipped <file...>: up to 40 files on stderr (no pipe: pipefail).
list_skipped() {
  local i=0 f
  for f in "$@"; do
    i=$((i + 1)); [ "$i" -gt 40 ] && break
    echo "  $f" >&2
  done
  [ "$#" -gt 40 ] && echo "  ... and $(($# - 40)) more" >&2
  return 0
}

tier_tests() {
  local range="${1:-origin/dev...HEAD}"
  # Total test time per push, waiting included (fast lane).
  DEADLINE=$((SECONDS + ${WP_PUSH_TEST_BUDGET:-300}))
  local max_d="${WP_PUSH_MAX_DISTANCE:-1}" chunk="${WP_PUSH_CHUNK:-40}"

  if ! git diff --name-only --no-renames "$range" | grep -qvE "$NO_TEST_PATHS"; then
    echo "check: $range changes only docs, website or metadata: no Flutter tests."
    return 0
  fi
  # The dispatcher ships the working tree, so it has to be the range's tip.
  local tip="${range##*.}"
  if [ "$(git rev-parse "${tip:-HEAD}")" != "$(git rev-parse HEAD)" ] ||
     ! git diff --quiet HEAD -- lib test tool integration_test; then
    echo "check: warning: the working tree is not $tip as committed; the tests see the working tree." >&2
  fi

  local selection
  if ! selection="$(dart tool/affected_tests.dart --with-distance "$range")"; then
    echo "check: warning: test selection failed; the tests are left to CI." >&2
    return 0
  fi
  if [ "$selection" = ALL ]; then
    # The whole suite does not fit the fast lane: CI and the integration
    # round run it; the push runs the changed tests.
    echo "check: $range changes what every test depends on (pubspec, test config)."
    echo "check: warning: the full suite is left to CI and 'bash scripts/check.sh full'." >&2
    selection="$(git diff --name-only "$range" -- 'test/*_test.dart' 'test/**/*_test.dart' |
      while IFS= read -r f; do [ -f "$f" ] && printf '0\t%s\n' "$f"; done)"
  fi

  local run=() far=0 platform=() d f
  while IFS=$'\t' read -r d f; do
    [ -z "$f" ] && continue
    if [ "$d" -gt "$max_d" ]; then far=$((far + 1)); continue; fi
    run+=("$f")
    grep -qE 'Platform\.is(Windows|MacOS|Linux)|Platform\.operatingSystem' "$f" && platform+=("$f")
  done <<<"$selection"
  if [ "${#run[@]}" -eq 0 ]; then
    echo "check: $range touches no test, no imported Dart file and no guarded path within distance $max_d."
    return 0
  fi
  echo "check: ${#run[@]} test file(s) within import distance $max_d of $range ($far farther ones left to CI), ${#platform[@]} with platform branches; budget $(budget_left) s."

  # Windows in parallel, for the platform-branching files only.
  local win_pid="" win_log=""
  if [ "${#platform[@]}" -gt 0 ] && [ -x "$WP_TEST" ]; then
    win_log="$(mktemp "${TMPDIR:-/tmp}/check-win.XXXXXX")"
    WP_QUEUE_TIMEOUT="${WP_PUSH_WIN_WAIT:-60}" capped "$(budget_left)" run_tests win "${platform[@]}" >"$win_log" 2>&1 &
    win_pid=$!
  fi

  # Chunks, nearest first: a red chunk blocks; a budget stop, no host or an
  # infrastructure failure leaves the rest unverified, with a warning.
  local rc=0 i=0 log reason="" skipped=()
  log="$(mktemp "${TMPDIR:-/tmp}/check-tests.XXXXXX")"
  while [ "$i" -lt "${#run[@]}" ]; do
    local part=("${run[@]:$i:$chunk}")
    rc=0
    main_run "${part[@]}" >"$log" 2>&1 || rc=$?
    grep -E '^check:|All tests passed|Some tests failed|\[E\]|Expected|Actual|Failed to load|wp-test\]' "$log" | tail -30 || true
    if [ "$rc" -ne 0 ]; then
      if [ "$rc" -ne 124 ] && [ "$rc" -ne 75 ] && red_tests "$log"; then
        echo "check: red tests, log $log"
        break
      fi
      case "$rc" in
        124) reason="test budget (${WP_PUSH_TEST_BUDGET:-300} s) used up" ;;
        75) reason="no lab ubu guest free within the wait (the Mac runs no Dart tests)" ;;
        *) reason="the test run broke off without a test result (rc $rc, log $log)" ;;
      esac
      skipped=("${run[@]:$i}")
      rc=0
      break
    fi
    i=$((i + chunk))
  done
  if [ "${#skipped[@]}" -gt 0 ]; then
    echo "check: warning: $reason; not verified before the push:" >&2
    list_skipped "${skipped[@]}"
    echo "  CI runs them after the push; locally: bash scripts/check.sh tests $range" >&2
  fi

  local rc_win=0
  if [ -n "$win_pid" ]; then
    wait "$win_pid" || rc_win=$?
    echo "── Windows (${#platform[@]} platform-branching files), log $win_log:"
    grep -E '\[E\]|Expected|Actual|All tests passed|Some tests failed|Failed to load' "$win_log" | tail -20 || true
    if [ "$rc_win" -ne 0 ] && { [ "$rc_win" -eq 75 ] || [ "$rc_win" -eq 124 ] || ! red_tests "$win_log"; }; then
      if [ "$rc_win" -eq 75 ]; then
        echo "check: warning: no Windows guest within ${WP_PUSH_WIN_WAIT:-60} s; the Windows branches of these files are unchecked:" >&2
      else
        echo "check: warning: no Windows result within the budget (rc $rc_win); the Windows branches of these files are unchecked:" >&2
      fi
      list_skipped "${platform[@]}"
      rc_win=0
    fi
  fi
  # Exit 10 means red tests (the hook blocks only on that).
  [ "$rc" -eq 0 ] && [ "$rc_win" -eq 0 ] || return 10
}

tier_full() {
  if [ ! -x "$WP_TEST" ]; then
    run_tests auto
    return
  fi
  # wp-test full shards the suite over the free hosts; Windows additionally
  # runs every platform-branching file, as CI's Windows job does.
  local platform=() log rc_main rc_win
  while IFS= read -r f; do platform+=("$f"); done < <(
    grep -rlE 'Platform\.is(Windows|MacOS|Linux)|Platform\.operatingSystem' test |
      grep '_test\.dart$' | sort)
  log="$(mktemp "${TMPDIR:-/tmp}/check-win.XXXXXX")"
  run_tests win "${platform[@]}" >"$log" 2>&1 &
  local win_pid=$!
  rc_main=0; "$WP_TEST" full "$ROOT" || rc_main=$?
  rc_win=0; wait "$win_pid" || rc_win=$?
  echo "── Windows (${#platform[@]} platform-branching files), log $log:"
  grep -E '\[E\]|All tests passed|Some tests failed' "$log" | tail -20 || true
  [ "$rc_main" -eq 0 ] && [ "$rc_win" -eq 0 ]
}

# Sourced (scripts/check.test.sh): functions only.
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

case "${1:-}" in
  commit) tier_commit ;;
  push) shift; tier_push "$@" ;;
  tests) shift; tier_tests "$@" ;;
  full) tier_full ;;
  *) usage ;;
esac
