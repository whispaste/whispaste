#!/usr/bin/env bash
# check.sh — local protection checks and explicit diagnostic helpers.
#
#   prepush [<target>]  run the push hook without pushing (default dev)
#   push [<target>]     alias for prepush; no tests, builds or gate stamps
#   commit              repo guards, format and analysis by hand
#   tests [<range>]     legacy affected-test diagnostic helper
#   full                legacy full-suite diagnostic helper
#   pending-win         inspect/run the legacy Windows backlog
#   note-win <entry...> add a legacy backlog entry
#
# gate/nas is a quick check (guards, gitleaks, format, shellcheck); flutter
# analyze, tests and builds run only in the existing lab workflows on dev
# after merge; no local stamp replaces CI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091  # scripts/sdk-env.sh: two wrapper functions
. "$ROOT/scripts/sdk-env.sh"

EXCLUDE_TAGS='canary,perf,ux-screens,store,capture'
WP_TEST="${WP_TEST:-$HOME/.claude/infrastructure/test-dispatch/wp-test.sh}"
# shellcheck disable=SC1091  # scripts/labctl-path.sh: labctl_find
. "$ROOT/scripts/labctl-path.sh"
LABCTL="$(labctl_find)"
ANALYZE_SCOPE=(lib test integration_test tool generators benchmarks)
_common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$ROOT/.git")"
if [ -z "${WP_PENDING_WIN:-}" ]; then
  WP_PENDING_WIN="$_common/wp-pending-win.txt"
  # One-time move of a list kept at the former default in the main checkout,
  # so no device loses its Windows backlog with the new default (#497).
  _old_pending="$(dirname "$_common")/internal-notes"
  if [ ! -e "$WP_PENDING_WIN" ] && [ -f "$_old_pending" ]; then
    mv "$_old_pending" "$WP_PENDING_WIN" 2>/dev/null || true
  fi
fi

usage() { sed -n '2,18p' "$0"; exit 2; }

# run_tests <host|auto> <file...>: one test run, through the dispatcher when
# available. An empty file list means the whole suite.
run_tests() {
  local host="$1"; shift
  if [ -x "$WP_TEST" ]; then
    local host_args=()
    [ "$host" != auto ] && host_args=(--host "$host")
    WP_STALL_LIMIT="${WP_STALL_LIMIT:-20}" WP_JOB_TIMEOUT="${WP_JOB_TIMEOUT:-180}" \
      "$WP_TEST" run "$ROOT" "${host_args[@]}" --exclude-tags="$EXCLUDE_TAGS" "$@"
  elif [ "$host" = auto ]; then
    dart "$ROOT/tool/test_guard.dart" -- --exclude-tags="$EXCLUDE_TAGS" "$@"
  else
    echo "check: no test dispatcher, the $host run is left to CI." >&2
  fi
}

tier_commit() {
  bash scripts/ci-gates.sh
  dart format --output=none --set-exit-if-changed lib test tool generators benchmarks
  flutter analyze --fatal-infos --fatal-warnings "${ANALYZE_SCOPE[@]}"
}

tier_push() {
  tier_prepush "$@"
}

# kill_tree <pid>: the dispatcher runs below a subshell; stop all of it so a
# lab job releases its lock (the dispatcher cleans up on SIGTERM).
kill_tree() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$child"; done
  kill -TERM "$1" 2>/dev/null || true
}

# capped <seconds> <cmd...>: run cmd, stop it after <seconds>; rc 124 then.
# In a stamp run it reports on fd 9 (the terminal, see tier_tests) once a
# minute, since its own output goes to a log; CAPPED_LABEL names the run.
capped() {
  local secs="$1"; shift
  [ "$secs" -le 0 ] && return 124
  "$@" &
  local pid=$! start=$SECONDS end=$((SECONDS + secs)) next=$((SECONDS + 60))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$end" ]; then
      kill_tree "$pid"; wait "$pid" 2>/dev/null || true
      return 124
    fi
    if stamp_run && [ "$SECONDS" -ge "$next" ]; then
      { echo "check: lab run${CAPPED_LABEL:+ ($CAPPED_LABEL)} in progress for $((SECONDS - start)) s (limit $secs s)" >&9; } 2>/dev/null || true
      next=$((SECONDS + 60))
    fi
    sleep 2
  done
  wait "$pid"
}

# stamp_run: whether this is check.sh prepush (.githooks/pre-push with
# WP_STAMP_RUN=1), which writes the gate stamp and holds no push up.
stamp_run() { [ "${WP_STAMP_RUN:-0}" = 1 ]; }

# lab_wait: seconds a run may queue for a lab guest on top of the budget.
lab_wait() { if stamp_run; then echo "${WP_STAMP_LAB_WAIT:-2700}"; else echo 0; fi; }

# win_run <file...>: the push's Windows run of the platform-branching files.
# LAB_NO_WARM: a stale warm snapshot ends the run (rc 77) instead of a
# rebuild of up to two hours that every later push would queue behind.
win_run() {
  local wait="${WP_PUSH_WIN_WAIT:-60}"
  stamp_run && wait="$(lab_wait)"
  LAB_NO_WARM=1 WP_QUEUE_TIMEOUT="$wait" CAPPED_LABEL=win capped "$(budget_left)" run_tests win "$@"
}

# main_run <file...>: the Linux-side run of one batch within the budget, on a
# lab ubu guest only: Dart tests never run on the Mac (maintainer rule), so a
# busy lab means waiting, up to WP_PUSH_UBU_WAIT or the rest of the budget.
# rc 75: no guest freed up, rc 124: budget used up.
main_run() {
  [ -x "$WP_TEST" ] || { capped "$(budget_left)" run_tests auto "$@"; return; }
  local wait="${WP_PUSH_UBU_WAIT:-$(budget_left)}"
  stamp_run && wait="$(lab_wait)"
  WP_QUEUE_TIMEOUT="$wait" CAPPED_LABEL=ubu capped "$(budget_left)" run_tests ubu "$@"
}

budget_left() { echo $((DEADLINE - SECONDS)); }

# win_busy: prints why the lab's Windows guest is not free for a push run
# (a lock, e.g. a warm build, or callers waiting for it). Without labctl or
# its status the run is tried as before.
win_busy() {
  local st
  [ -x "$LABCTL" ] || return 1
  st="$(capped 30 "$LABCTL" status 2>/dev/null)" || return 1
  # labctl lists every guest's lock, a free one as "lock win: free".
  st="$(printf '%s\n' "$st" | grep -E '^lock win:|^[[:space:]]*waiting \(win\)' |
    grep -vE '^lock win: free[[:space:]]*$' | head -n 1)" || true
  [ -n "$st" ] || return 1
  printf '%s\n' "$st" | sed 's/^[[:space:]]*//'
}

# win_skip: like win_busy, the reason a push skips its Windows run; a stamp
# run never skips, it waits for the guest (lab_wait).
win_skip() { ! stamp_run && win_busy; }

# Paths that no test reads: a range of only these skips the selection.
NO_TEST_PATHS='^(docs/|website/|[^/]*\.md$|LICENSE$|\.gitignore$|\.ossallowlist$)'

# red_tests <log>: whether a run reports failing or unloadable tests, as
# opposed to a run the infrastructure broke off (lock, VM, network). A failed
# test line ends in [E]; the dispatcher's own summary names "[E]" mid-line.
red_tests() { grep -qE 'Some tests failed|Failed to load|\[E\][[:space:]]*$' "$1"; }

# run_outcome <rc> <log>: green, red or unverified. A red test blocks even
# when the budget or a wait stopped the run after it; only a run without a
# test result counts as unverified.
run_outcome() {
  if red_tests "$2"; then
    echo red
  elif [ "$1" -eq 0 ]; then
    echo green
  else
    echo unverified
  fi
}

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

# pending_win_add <file...>: remembers Windows runs a push had to skip,
# one line per file (path, SHA, date); a file already listed keeps its line.
pending_win_add() {
  local f sha now
  sha="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  now="$(date '+%Y-%m-%d %H:%M')"
  mkdir -p "$(dirname "$WP_PENDING_WIN")"
  touch "$WP_PENDING_WIN"
  for f in "$@"; do
    cut -f1 "$WP_PENDING_WIN" | grep -qxF -- "$f" ||
      printf '%s\t%s\t%s\n' "$f" "$sha" "$now" >>"$WP_PENDING_WIN"
  done
  echo "check: noted for the next Windows run in $WP_PENDING_WIN" >&2
}

# pending_win_files: the listed files that still exist, one per line.
pending_win_files() {
  [ -f "$WP_PENDING_WIN" ] || return 0
  local f
  while IFS=$'\t' read -r f _; do
    [ -n "$f" ] && [ -f "$f" ] && printf '%s\n' "$f"
  done <"$WP_PENDING_WIN"
  return 0
}

# pending_win_merge <file...>: the given files plus the pending ones, once
# each, in that order.
pending_win_merge() {
  local f seen=" "
  while IFS= read -r f; do
    case "$seen" in *" $f "*) continue ;; esac
    seen="$seen$f "
    printf '%s\n' "$f"
  done < <(printf '%s\n' "$@"; pending_win_files)
}

# The backlog entry for a Windows runner build a push could not run
# (.githooks/pre-push §8, PAR-069); not a file, so pending_win_files skips it.
PENDING_WIN_RUNNER="windows/runner"

# pending_win_runner: whether a Windows runner build is pending.
pending_win_runner() {
  [ -f "$WP_PENDING_WIN" ] && cut -f1 "$WP_PENDING_WIN" | grep -qxF "$PENDING_WIN_RUNNER"
}

# pending_win_drop <entry>: removes one entry from the backlog.
pending_win_drop() {
  local rest
  rest="$(grep -vF "$1"$'\t' "$WP_PENDING_WIN" || true)"
  printf '%s' "${rest:+$rest$'\n'}" >"$WP_PENDING_WIN"
}

tier_pending_win() {
  local files=() f
  if pending_win_runner; then
    echo "check: pending Windows runner build"
    bash "$ROOT/scripts/native-compile-check.sh" --runner --host win HEAD
    case $? in
      0) pending_win_drop "$PENDING_WIN_RUNNER" ;;
      1) echo "check: the Windows runner does not build; the list stays." >&2; return 10 ;;
      *) echo "check: warning: Windows runner build unchecked; the list stays." >&2 ;;
    esac
  fi
  while IFS= read -r f; do files+=("$f"); done < <(pending_win_files)
  if [ "${#files[@]}" -eq 0 ]; then
    echo "check: no Windows test run pending."
    pending_win_runner || { : >"$WP_PENDING_WIN" 2>/dev/null || true; }
    return 0
  fi
  echo "check: ${#files[@]} pending Windows file(s) from $WP_PENDING_WIN"
  if ! run_tests win "${files[@]}"; then
    echo "check: the Windows backlog is not green; the list stays." >&2
    return 10
  fi
  if pending_win_runner; then
    printf '%s\n' "$(grep -F "$PENDING_WIN_RUNNER"$'\t' "$WP_PENDING_WIN")" >"$WP_PENDING_WIN.tmp"
    mv "$WP_PENDING_WIN.tmp" "$WP_PENDING_WIN"
    echo "check: the Windows test backlog ran green; the runner build stays listed."
    return 0
  fi
  : >"$WP_PENDING_WIN"
  echo "check: the Windows backlog ran green; list emptied."
}

tier_tests() {
  local range="${1:-origin/dev...HEAD}"
  # Total test time per push, waiting included (fast lane); a stamp run
  # adds its lab wait, so queueing never eats the budget of the run itself.
  DEADLINE=$((SECONDS + ${WP_PUSH_TEST_BUDGET:-300} + $(lab_wait)))
  exec 9>&2
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
    echo "check: $range changes what every test depends on (pubspec, test config)."
    # A stamp run holds no push up, so it runs the whole suite, sharded over
    # the free hosts (tier_full); only a green run of every shard counts (#80).
    if stamp_run; then
      echo "check: stamp run: the full suite (check.sh full) instead of the push tier."
      tier_full || return 10
      return 0
    fi
    # The whole suite does not fit the fast lane of a push: CI and the
    # integration round run it; the push runs the changed tests.
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
  done < <(printf '%s\n' "$selection")
  if [ "${#run[@]}" -eq 0 ]; then
    echo "check: $range touches no test, no imported Dart file and no guarded path within distance $max_d."
    return 0
  fi
  echo "check: ${#run[@]} test file(s) within import distance $max_d of $range ($far farther ones left to CI), ${#platform[@]} with platform branches; budget $(budget_left) s."

  # Windows in parallel, for the platform-branching files only, plus what
  # earlier pushes had to skip.
  if [ "${#platform[@]}" -gt 0 ]; then
    local merged=()
    while IFS= read -r f; do merged+=("$f"); done < <(pending_win_merge "${platform[@]}")
    platform=("${merged[@]}")
  fi
  local win_pid="" win_log="" win_why=""
  if [ "${#platform[@]}" -gt 0 ] && [ -x "$WP_TEST" ] && win_why="$(win_skip)"; then
    echo "check: warning: the Windows guest is busy ($win_why); the Windows branches of these files are unchecked:" >&2
    list_skipped "${platform[@]}"
    pending_win_add "${platform[@]}"
  elif [ "${#platform[@]}" -gt 0 ] && [ -x "$WP_TEST" ]; then
    win_log="$(mktemp "${TMPDIR:-/tmp}/check-win.XXXXXX")"
    win_run "${platform[@]}" >"$win_log" 2>&1 &
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
    local outcome
    outcome="$(run_outcome "$rc" "$log")"
    if [ "$outcome" = red ]; then
      echo "check: red tests, log $log"
      rc=10
      break
    fi
    if [ "$outcome" = unverified ]; then
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
    local outcome_win
    outcome_win="$(run_outcome "$rc_win" "$win_log")"
    if [ "$outcome_win" = red ]; then
      rc_win=10
    elif [ "$outcome_win" = unverified ]; then
      if [ "$rc_win" -eq 77 ]; then
        echo "check: warning: the Windows guest's warm snapshot is stale and is not rebuilt for a push; the Windows branches of these files are unchecked:" >&2
      elif [ "$rc_win" -eq 75 ]; then
        echo "check: warning: no Windows guest within ${WP_PUSH_WIN_WAIT:-60} s; the Windows branches of these files are unchecked:" >&2
      else
        echo "check: warning: no Windows result within the budget (rc $rc_win); the Windows branches of these files are unchecked:" >&2
      fi
      list_skipped "${platform[@]}"
      pending_win_add "${platform[@]}"
      rc_win=0
    else
      : >"$WP_PENDING_WIN" 2>/dev/null || true
    fi
  fi
  # Exit 10 means red tests (the hook blocks only on that).
  [ "$rc" -eq 0 ] && [ "$rc_win" -eq 0 ] || return 10
}

# prepush_warned <log>: rc 0 when a prepush log reports a gate that did not
# reach a verdict; such a green run gets no stamp. The rule lives in
# scripts/gate-stamp.sh (warned), which the pre-push hook uses too (#80).
prepush_warned() { bash "$ROOT/scripts/gate-stamp.sh" warned "$1"; }

# Simulate the actual branch push, without stamps or helper test suites.
tier_prepush() {
  local target="${1:-dev}" branch head remote_sha url
  branch="$(git symbolic-ref --short -q HEAD)" \
    || { echo "check: prepush needs a branch, not a detached HEAD." >&2; return 2; }
  git rev-parse --verify -q "origin/$target" >/dev/null \
    || { echo "check: origin/$target missing; run git fetch." >&2; return 2; }
  head="$(git rev-parse HEAD)"
  remote_sha="$(git rev-parse --verify -q "refs/remotes/origin/$branch" || printf '%040d' 0)"
  url="$(git remote get-url origin)"
  printf 'refs/heads/%s %s refs/heads/%s %s\n' "$branch" "$head" "$branch" "$remote_sha" \
    | bash .githooks/pre-push origin "$url"
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
  prepush) shift; tier_prepush "$@" ;;
  pending-win) tier_pending_win ;;
  note-win) shift; pending_win_add "$@" ;;
  *) usage ;;
esac
