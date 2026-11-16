#!/usr/bin/env bash
# check.test.sh — scripts/check.sh runs the push tests on a lab ubu guest
# only: with a stub dispatcher
#   1. a free guest: one run, --host ubu, its result passed through
#   2. a busy lab (rc 75): no second run, never --host mac, rc 75 kept
#   3. the ubu wait defaults to the rest of the budget
#   4. win_busy: a locked or queued Windows guest is busy, a free one (also
#      listed as "lock win: free") or a missing labctl is not
#   5. the Windows run asks for no warm rebuild (LAB_NO_WARM=1)
#   6. skipped Windows files are noted once each, taken along by the next
#      Windows run and dropped once it is green (PAR-066)
#   7. a red test blocks even when the budget or a wait ended the run after
#      it; only a run without a test result is unverified
#   8. gate stamps: valid for tree, target and config only, checksum intact
#   9. a green prepush run with an unverified gate (warning, unchecked, aborted)
#      writes no stamp; a loam skip for a docs-only push is a verdict, and so
#      are WARNING lines in the raw output of the Linux native tests (#49)
#  10. a windows/runner change is built on win only: a compile error blocks
#      (exit 1), a busy guest is not waited for and stays unchecked (exit 3),
#      ubu counts as busy only with ubu and ubu2 locked; a noted runner build
#      stays in the Windows backlog until it ran (PAR-069); a linux/runner
#      change is built on ubu only, and each guest sees only its own runner
#      paths (#77)
#  11. a stamp run (WP_STAMP_RUN=1) queues for a lab guest with its own
#      limit on top of the budget, on ubu and on win, and never skips a busy
#      Windows guest; a push run keeps the budget-bound wait
#  12. a push whose hook ran the full path green stamps the pushed tree
#      (gate-stamp.sh from-push, #80): never with a warning, a working tree
#      other than HEAD, a ref other than HEAD, a moved HEAD or a tag
#  13. labctl is found the same way on every device (#460): LABCTL first,
#      then ~/.claude/bin/labctl, then PATH; none of them: nothing, and
#      native-compile-check exits 2 naming the places it looked
# Run: bash scripts/check.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/wp-test" <<'EOF'
#!/bin/sh
echo "$* wait=${WP_QUEUE_TIMEOUT:-} nowarm=${LAB_NO_WARM:-}" >>"$STUB_LOG"
exit "$STUB_RC"
EOF
chmod +x "$WORK/wp-test"

export WP_TEST="$WORK/wp-test" STUB_LOG="$WORK/calls"
# shellcheck disable=SC1091  # scripts/check.sh: functions only when sourced
. "$HERE/check.sh"
set +e

failures=0
ok() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1"
  sed 's/^/       /' "$STUB_LOG" 2>/dev/null
  failures=$((failures + 1))
}

# 1
: >"$STUB_LOG"
# shellcheck disable=SC2034  # read by budget_left
DEADLINE=$((SECONDS + 300))
rc=0; STUB_RC=0 main_run test/a_test.dart >/dev/null 2>&1 || rc=$?
if [ "$rc" = 0 ] && [ "$(wc -l <"$STUB_LOG")" -eq 1 ] && grep -q -- "--host ubu" "$STUB_LOG"; then
  ok "a free guest: one ubu run"
else
  fail "free guest (rc=$rc)"
fi

# 2 + 3
: >"$STUB_LOG"
# shellcheck disable=SC2034  # read by budget_left
DEADLINE=$((SECONDS + 300))
rc=0; STUB_RC=75 main_run test/a_test.dart >/dev/null 2>&1 || rc=$?
if [ "$rc" = 75 ] && [ "$(wc -l <"$STUB_LOG")" -eq 1 ] && ! grep -q -- "--host mac" "$STUB_LOG"; then
  ok "a busy lab: no Mac run, rc 75"
else
  fail "busy lab (rc=$rc)"
fi
wait_s="$(sed -n 's/.* wait=\([0-9]*\).*/\1/p' "$STUB_LOG")"
if [ -n "$wait_s" ] && [ "$wait_s" -ge 290 ]; then
  ok "the ubu wait is the rest of the budget"
else
  fail "ubu wait ($wait_s)"
fi

# 5
: >"$STUB_LOG"
# shellcheck disable=SC2034  # read by budget_left
DEADLINE=$((SECONDS + 300))
STUB_RC=77 win_run test/a_test.dart >/dev/null 2>&1
if grep -q -- "--host win .*nowarm=1" "$STUB_LOG"; then
  ok "the Windows run sets LAB_NO_WARM=1"
else
  fail "Windows run without LAB_NO_WARM"
fi

# 4
cat >"$WORK/labctl" <<'EOF'
#!/bin/sh
cat "$STUB_STATUS"
EOF
chmod +x "$WORK/labctl"
# shellcheck disable=SC2034  # read by win_busy
LABCTL="$WORK/labctl"
export STUB_STATUS="$WORK/status"
printf '%s\n' 'lock win: warm win whispaste pid=1 since=x by=whispaste' 'lock ubu: test ubu' >"$STUB_STATUS"
why="$(win_busy)"
case "$why" in
  "lock win: warm"*) ok "win_busy: a warm build is busy" ;;
  *) fail "win_busy lock: '$why'" ;;
esac
printf '%s\n' 'lock ubu: test ubu' '  waiting (win) PRIO: 1-2 for win test win whispaste' >"$STUB_STATUS"
if win_busy >/dev/null; then ok "win_busy: a queue is busy"; else fail "win_busy: queue not seen"; fi
printf '%s\n' 'lock ubu: test ubu' '  waiting (ubu) PRIO: 1-2 for ubu,ubu2' 'win (110): running' >"$STUB_STATUS"
if win_busy >/dev/null; then fail "win_busy: a free guest counted as busy"; else ok "win_busy: a free guest is free"; fi
printf '%s\n' 'lock win: free' 'lock ubu: free' 'lock ubu2: free' >"$STUB_STATUS"
if win_busy >/dev/null; then fail "win_busy: 'lock win: free' counted as busy"; else ok "win_busy: a lock line reading free is free"; fi
# shellcheck disable=SC2034  # read by win_busy
LABCTL="$WORK/none"
if win_busy >/dev/null; then fail "win_busy: no labctl counted as busy"; else ok "win_busy: without labctl the run is tried"; fi

# 6
export WP_PENDING_WIN="$WORK/pending/pending-win.txt"
cd "$WORK" && mkdir -p test && touch test/a_test.dart test/b_test.dart
pending_win_add test/a_test.dart test/b_test.dart 2>/dev/null
pending_win_add test/a_test.dart 2>/dev/null
if [ "$(cut -f1 "$WP_PENDING_WIN" | tr '\n' ' ')" = "test/a_test.dart test/b_test.dart " ] &&
  [ "$(awk -F'\t' '{print NF}' "$WP_PENDING_WIN" | sort -u)" = 3 ]; then
  ok "skipped Windows files are noted once, with SHA and date"
else
  fail "pending list: $(cat "$WP_PENDING_WIN")"
fi
rm test/b_test.dart
merged="$(pending_win_merge test/c_test.dart test/a_test.dart | tr '\n' ' ')"
if [ "$merged" = "test/c_test.dart test/a_test.dart " ]; then
  ok "the next Windows run takes the pending files along, once, if they exist"
else
  fail "merge: '$merged'"
fi
: >"$STUB_LOG"
rc=0; STUB_RC=1 tier_pending_win >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && [ -s "$WP_PENDING_WIN" ] && grep -q -- "--host win" "$STUB_LOG"; then
  ok "a red backlog run keeps the list"
else
  fail "red backlog (rc=$rc)"
fi
rc=0; STUB_RC=0 tier_pending_win >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$WP_PENDING_WIN" ]; then
  ok "a green backlog run empties the list"
else
  fail "green backlog (rc=$rc): $(cat "$WP_PENDING_WIN")"
fi

# 7
red_log="$WORK/red.log" none_log="$WORK/none.log" green_log="$WORK/green.log"
printf '%s\n' '00:06 +119 -1: a_test.dart: guard [E]' '[wp-test] Abbruch (Signal 15)' >"$red_log"
printf '%s\n' '[wp-test] warte auf freien Host' >"$none_log"
printf '%s\n' '00:01 +9: All tests passed!' \
  '[wp-test] ubu: rc=0, Fehlerzahl unbekannt (kein JSON-Report, siehe "Failing tests"/[E] im Log)' \
  >"$green_log"
for rc in 124 75 77 1 0; do
  got="$(run_outcome "$rc" "$red_log")"
  if [ "$got" = red ]; then ok "rc $rc after a red test blocks"; else fail "rc $rc after a red test: $got"; fi
done
for rc in 124 75 77 1; do
  got="$(run_outcome "$rc" "$none_log")"
  if [ "$got" = unverified ]; then ok "rc $rc without a result is unverified"; else fail "rc $rc without a result: $got"; fi
done
got="$(run_outcome 0 "$green_log")"
if [ "$got" = green ]; then ok "a passed run is green"; else fail "passed run: $got"; fi

# 8. gate stamps (scripts/gate-stamp.sh, read by the pre-push fast path): a
#    stamp counts for the same tree, target and gate config, and only with an
#    intact checksum; a rebase with the same tree keeps it
STAMP_REPO="$WORK/stamp-repo"
mkdir -p "$STAMP_REPO/scripts/ci" "$STAMP_REPO/.githooks" "$STAMP_REPO/lib"
cp "$HERE/gate-stamp.sh" "$STAMP_REPO/scripts/gate-stamp.sh"
printf 'gates v1\n' >"$STAMP_REPO/scripts/ci-gates.sh"
printf 'one\n' >"$STAMP_REPO/lib/a.txt"
gitc() { (cd "$STAMP_REPO" && git -c core.hooksPath=/dev/null -c user.name=test -c user.email=test "$@"); }
gs() { bash "$STAMP_REPO/scripts/gate-stamp.sh" "$@"; }
gitc init -q
gitc add -A
gitc commit -q -m base
tree1="$(gitc rev-parse 'HEAD^{tree}')"
gs write "$tree1" "$(gitc rev-parse HEAD)" dev

if gs check "$tree1" dev; then ok "stamp: valid for tree, target and config"; else fail "stamp: valid stamp refused"; fi

sha1="$(gitc rev-parse HEAD)"
gitc commit -q --amend -m "base, rebased"
if [ "$(gitc rev-parse HEAD)" != "$sha1" ] && gs check "$tree1" dev; then
  ok "stamp: rebase without content change (same tree, new SHA) stays valid"
else
  fail "stamp: rebase with the same tree refused"
fi

printf 'two\n' >"$STAMP_REPO/lib/a.txt"
gitc add -A
gitc commit -q -m change
tree2="$(gitc rev-parse 'HEAD^{tree}')"
if ! gs check "$tree2" dev; then ok "stamp: changed tree has no stamp, full path"; else fail "stamp: unstamped tree passed"; fi

gs write "$tree2" "$(gitc rev-parse HEAD)" dev
if ! gs check "$tree2" main; then ok "stamp: other target branch is no stamp"; else fail "stamp: wrong target passed"; fi
if ! gs check "" dev; then ok "stamp: empty tree is refused"; else fail "stamp: empty tree passed"; fi

printf 'gates v2\n' >"$STAMP_REPO/scripts/ci-gates.sh"
if ! gs check "$tree2" dev; then ok "stamp: changed gate config invalidates the stamp"; else fail "stamp: changed config passed"; fi
printf 'gates v1\n' >"$STAMP_REPO/scripts/ci-gates.sh"
gs write "$tree2" "$(gitc rev-parse HEAD)" dev

stamp_file="$(ls "$STAMP_REPO/.git/wp-gate-stamps/$tree2.dev."* 2>/dev/null | head -1)"
printf 'forged=1\n' >>"$stamp_file"
if ! gs check "$tree2" dev; then ok "stamp: edited stamp fails its checksum"; else fail "stamp: edited stamp passed"; fi
: >"$stamp_file"
if ! gs check "$tree2" dev; then ok "stamp: empty stamp file is refused"; else fail "stamp: empty stamp passed"; fi

rm -rf "$STAMP_REPO/.git/wp-gate-stamps"
if ! gs check "$tree2" dev; then ok "stamp: missing stamp, full path"; else fail "stamp: missing stamp passed"; fi

# native compile gates are part of the gate config: a new or changed one
# invalidates the stamp (agent3's Windows gate, PAR-069)
printf 'native v1\n' >"$STAMP_REPO/scripts/native-compile-check.sh"
gs write "$tree2" "$(gitc rev-parse HEAD)" dev
if gs check "$tree2" dev; then ok "stamp: native-compile gate in the config, stamp valid"; else fail "stamp: native-compile file not hashed"; fi
printf 'native v2\n' >"$STAMP_REPO/scripts/native-compile-check.sh"
if ! gs check "$tree2" dev; then ok "stamp: changed native-compile gate invalidates the stamp"; else fail "stamp: changed native-compile gate passed"; fi

# 9. a green prepush run with an unverified gate writes no stamp: warnings,
#    rc 3 "unchecked", a used-up test budget, an aborted run; a loam skip for
#    a push without Dart changes is a verdict, not a warning
warn_log="$WORK/warn.log" verdict_log="$WORK/verdict.log"
printf '%s\n' 'check: warning: test budget (300 s) used up; not verified before the push:' >"$warn_log"
printf '%s\n' '[win] UNCHECKED: no compile result (rc=3; lab busy or the VM run broke off), last lines:' >"$WORK/unchecked.log"
printf '%s\n' '[wp-test] Abbruch (Signal 15)' >"$WORK/abort.log"
printf '%s\n' 'Loam ratchet gate: übersprungen (Push ändert keine Dart-Dateien).' \
  'check: 18 test file(s) within import distance 1 of a..b (155 farther ones left to CI), 0 with platform branches; budget 1199 s.' \
  '⚠ llama.cpp v0.9.0 verfügbar (seit 6 Tagen) – Update-Paket einplanen (gepinnt: v0.8.0, scripts/llama-cpp.pin)' \
  'Repo-Gates (wie CI)...' >"$verdict_log"
if prepush_warned "$warn_log" && prepush_warned "$WORK/unchecked.log" && prepush_warned "$WORK/abort.log"; then
  ok "prepush: warnings, unchecked and aborted runs write no stamp"
else
  fail "prepush: an unverified gate would be stamped"
fi
if ! prepush_warned "$verdict_log"; then ok "prepush: loam skip, distance-limited tests and upstream-pin notice are verdicts, no warning"; else fail "prepush: a verdict line counted as warning"; fi
# Each own report form counts, also behind host prefixes and indentation.
own_ok=1
for line in '⚠ gitleaks nicht installiert — Secret-Scan übersprungen.' \
  '  ⚠ macOS-Plugin-Prüfung ohne Ergebnis: x' \
  '[ubu]   LAB-WARN no output for 2 min; the watchdog stops the run after 5 min of silence' \
  'native-compile-check: warning: not checked on win; run it again when the lab is free.'; do
  printf '%s\n' "$line" >"$WORK/own.log"
  prepush_warned "$WORK/own.log" || { own_ok=0; fail "prepush: own report line not seen: $line"; }
done
[ "$own_ok" = 1 ] && ok "prepush: every own report form counts as a warning"
# Raw output of a green Linux native run: GLib/Gdk warnings are expected.
printf '%s\n' '── keybinder_raw_test' \
  "(keybinder_raw_test:4711): WARNING **: 12:00:01.000: Binding '<Alt>F10' failed!" \
  'must fail: ok' \
  '(x11_window_test:4712): Gdk-WARNING **: 12:00:02.000: XSetErrorHandler() called with a GDK error trap pushed.' \
  'warning: unused variable in a vendored helper' \
  'linux-native-tests: 6 passed' \
  '  Linux native: OK' >"$WORK/native.log"
if ! prepush_warned "$WORK/native.log"; then ok "prepush: WARNING lines of the native tests are no gate warning (#49)"; else fail "prepush: raw native test output blocks the stamp"; fi

# 10
# A guest without a global git identity (lab win) cannot commit in the temp repos.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test
repo="$WORK/repo"
git init -q "$repo"
git -C "$repo" commit -q --allow-empty -m base
mkdir -p "$repo/windows/runner"
echo 'int x;' >"$repo/windows/runner/main.cpp"
git -C "$repo" add windows && git -C "$repo" commit -q -m runner
cat >"$WORK/labctl-nc" <<'EOF'
#!/bin/sh
case "$1" in
  status) printf '%s\n' "$FAKE_STATUS" ;;
  test) echo "test $2" >>"$FAKE_CALLS"; echo "$FAKE_OUT"; exit "$FAKE_RC" ;;
esac
EOF
chmod +x "$WORK/labctl-nc"
nc() { (cd "$repo" && LABCTL="$WORK/labctl-nc" bash "$HERE/native-compile-check.sh" "$@" 2>&1); }
export FAKE_CALLS="$WORK/fake-calls"
free=$'lock win: free\nlock ubu: free\nlock ubu2: free'

: >"$FAKE_CALLS"
out="$(FAKE_STATUS="$free" FAKE_OUT='native-compile: windows_runner ok' FAKE_RC=0 nc --no-wait HEAD~1..HEAD)"; rc=$?
if [ "$rc" = 0 ] && [ "$(cat "$FAKE_CALLS")" = "test win" ]; then ok "a runner-only range builds on win alone"; else fail "runner green (rc=$rc): $out $(cat "$FAKE_CALLS")"; fi

: >"$FAKE_CALLS"
out="$(FAKE_STATUS="$free" FAKE_OUT='native-compile: windows_runner FAILED' FAKE_RC=1 nc --no-wait HEAD~1..HEAD)"; rc=$?
if [ "$rc" = 1 ]; then ok "a runner compile error blocks"; else fail "runner red (rc=$rc): $out"; fi

: >"$FAKE_CALLS"
out="$(FAKE_STATUS=$'lock win: warm win whispaste pid=1\nlock ubu: free' FAKE_OUT='' FAKE_RC=0 nc --no-wait HEAD~1..HEAD)"; rc=$?
if [ "$rc" = 3 ] && [ ! -s "$FAKE_CALLS" ] && printf '%s' "$out" | grep -qi unchecked; then
  ok "a busy win is not waited for and stays unchecked"
else
  fail "busy win (rc=$rc): $out $(cat "$FAKE_CALLS")"
fi

: >"$FAKE_CALLS"
out="$(FAKE_STATUS="$free" FAKE_OUT='[labctl] no warm state' FAKE_RC=2 nc --no-wait HEAD~1..HEAD)"; rc=$?
if [ "$rc" = 3 ]; then ok "a run without a build result stays unchecked"; else fail "no result (rc=$rc): $out"; fi

if ( export LABCTL="$WORK/labctl-nc"
  # shellcheck disable=SC1090
  eval "$(sed -n '/^lock_held()/,/^}/p' "$HERE/native-compile-check.sh")"
  FAKE_STATUS=$'lock ubu: test ubu x pid=1\nlock ubu2: free'; export FAKE_STATUS
  lock_held ubu && exit 1
  FAKE_STATUS=$'lock ubu: test ubu x pid=1\nlock ubu2: test ubu y pid=2'; export FAKE_STATUS
  lock_held ubu || exit 1
  exit 0 ); then
  ok "ubu is busy only with ubu and ubu2 locked"
else
  fail "ubu lock rule"
fi

WP_PENDING_WIN="$WORK/pending-runner.txt"
: >"$WP_PENDING_WIN"
pending_win_add windows/runner 2>/dev/null
pending_win_add windows/runner 2>/dev/null
if pending_win_runner && [ "$(wc -l <"$WP_PENDING_WIN")" -eq 1 ] && [ -z "$(pending_win_files)" ]; then
  ok "a noted runner build is listed once and is no test file"
else
  fail "runner note: $(cat "$WP_PENDING_WIN")"
fi
pending_win_drop windows/runner
if ! pending_win_runner; then ok "a built runner leaves the backlog"; else fail "runner drop: $(cat "$WP_PENDING_WIN")"; fi

mkdir -p "$repo/linux/runner"
echo 'int y;' >"$repo/linux/runner/main.cc"
git -C "$repo" add linux && git -C "$repo" commit -q -m linux-runner
: >"$FAKE_CALLS"
out="$(FAKE_STATUS="$free" FAKE_OUT='native-compile: linux_runner ok' FAKE_RC=0 nc --no-wait HEAD~1..HEAD)"; rc=$?
if [ "$rc" = 0 ] && [ "$(cat "$FAKE_CALLS")" = "test ubu" ]; then ok "a linux/runner range builds on ubu alone"; else fail "linux runner (rc=$rc): $out $(cat "$FAKE_CALLS")"; fi
if nc --touches-runner --host ubu HEAD~1..HEAD >/dev/null && ! nc --touches-runner --host win HEAD~1..HEAD >/dev/null \
   && nc --touches-runner --host win HEAD~2..HEAD~1 >/dev/null && ! nc --touches-runner --host ubu HEAD~2..HEAD~1 >/dev/null; then
  ok "each guest sees only its own runner paths"
else
  fail "runner paths per guest"
fi
: >"$FAKE_CALLS"
out="$(FAKE_STATUS="$free" FAKE_OUT='native-compile: linux_runner FAILED' FAKE_RC=1 nc --no-wait --host both HEAD~2..HEAD)"; rc=$?
if [ "$rc" = 1 ] && [ "$(sort "$FAKE_CALLS" | tr '\n' ' ')" = "test ubu test win " ]; then ok "both runners touched: both guests build, a red one blocks"; else fail "both runners (rc=$rc): $(cat "$FAKE_CALLS")"; fi

# 11
: >"$STUB_LOG"
# shellcheck disable=SC2034  # read by budget_left
DEADLINE=$((SECONDS + 300))
STUB_RC=0 main_run test/a_test.dart >/dev/null 2>&1
if grep -q "wait=29[0-9] " "$STUB_LOG" || grep -q "wait=300 " "$STUB_LOG"; then ok "a push run waits within the budget"; else fail "push wait"; fi
: >"$STUB_LOG"
export WP_STAMP_RUN=1
# shellcheck disable=SC2034  # read by budget_left
DEADLINE=$((SECONDS + 300 + $(lab_wait)))
STUB_RC=0 main_run test/a_test.dart >/dev/null 2>&1
STUB_RC=0 win_run test/a_test.dart >/dev/null 2>&1
if [ "$(grep -c "wait=2700 " "$STUB_LOG")" = 2 ] && grep -q -- "--host win.*nowarm=1" "$STUB_LOG" &&
  [ "$(budget_left)" -ge 2990 ]; then
  ok "a stamp run queues up to its own limit on ubu and win, the budget kept"
else
  fail "stamp wait (budget left $(budget_left))"
fi
printf '%s\n' 'lock win: warm win whispaste pid=1 since=x by=whispaste' >"$STUB_STATUS"
# shellcheck disable=SC2034  # read by win_busy
LABCTL="$WORK/labctl"
if ! win_skip >/dev/null; then ok "a stamp run waits for a busy Windows guest"; else fail "stamp run skipped win"; fi
unset WP_STAMP_RUN
if win_skip >/dev/null; then ok "a push run skips a busy Windows guest"; else fail "push run waited for win"; fi

# 12. a push whose hook ran the full path green stamps the pushed tree
#     (gate-stamp.sh from-push, #80), under the conditions of a stamp run:
#     no warning, the working tree exactly HEAD, every pushed ref HEAD
mkdir -p "$STAMP_REPO/.githooks"
cp "$HERE/../.githooks/push-scope.sh" "$STAMP_REPO/.githooks/push-scope.sh"
cp "$HERE/gate-stamp.sh" "$STAMP_REPO/scripts/gate-stamp.sh"
gitc add -A
gitc commit -q -m "push scope"
rm -rf "$STAMP_REPO/.git/wp-gate-stamps"
head3="$(gitc rev-parse HEAD)" tree3="$(gitc rev-parse 'HEAD^{tree}')"
z=0000000000000000000000000000000000000000
green_log="$WORK/green.log"
printf '%s\n' 'Repo-Gates (wie CI)...' '  Linux native: OK' >"$green_log"
fp() { printf '%s\n' "$1" | gs from-push "$2" "$3" 2>/dev/null; }

fp "refs/heads/fix/x $head3 refs/heads/fix/x $z" "$green_log" "$head3"
if gs check "$tree3" dev; then ok "from-push: green full run stamps the PR's tree for dev"; else fail "from-push: green run wrote no stamp"; fi
fp "refs/heads/hotfix/y $head3 refs/heads/hotfix/y $z" "$green_log" "$head3"
if gs check "$tree3" main; then ok "from-push: a hotfix push is stamped for main"; else fail "from-push: hotfix target"; fi

rm -rf "$STAMP_REPO/.git/wp-gate-stamps"
fp "refs/heads/fix/x $head3 refs/heads/fix/x $z" "$warn_log" "$head3"
if ! gs check "$tree3" dev; then ok "from-push: a warning in the run writes no stamp"; else fail "from-push: warned run stamped"; fi
fp "refs/heads/fix/x $head3 refs/heads/fix/x $z" "$WORK/missing.log" "$head3"
if ! gs check "$tree3" dev; then ok "from-push: no log, no stamp"; else fail "from-push: missing log stamped"; fi

printf 'dirty\n' >>"$STAMP_REPO/lib/a.txt"
fp "refs/heads/fix/x $head3 refs/heads/fix/x $z" "$green_log" "$head3"
gitc checkout -q -- lib/a.txt
if ! gs check "$tree3" dev; then ok "from-push: a modified working tree writes no stamp"; else fail "from-push: dirty tree stamped"; fi
printf 'new\n' >"$STAMP_REPO/lib/untracked.txt"
fp "refs/heads/fix/x $head3 refs/heads/fix/x $z" "$green_log" "$head3"
rm -f "$STAMP_REPO/lib/untracked.txt"
if ! gs check "$tree3" dev; then ok "from-push: an untracked file writes no stamp"; else fail "from-push: untracked file stamped"; fi

base_sha="$(gitc rev-parse HEAD~1)"
fp "refs/heads/fix/x $base_sha refs/heads/fix/x $z" "$green_log" "$head3"
if ! gs check "$(gitc rev-parse "$base_sha^{tree}")" dev && ! gs check "$tree3" dev; then
  ok "from-push: a push of another commit than HEAD writes no stamp"
else
  fail "from-push: a commit other than the checked-out one was stamped"
fi
fp "refs/heads/fix/x $head3 refs/heads/fix/x $z" "$green_log" "$base_sha"
if ! gs check "$tree3" dev; then ok "from-push: HEAD moved during the run, no stamp"; else fail "from-push: moved HEAD stamped"; fi
fp "refs/tags/v1 $head3 refs/tags/v1 $z" "$green_log" "$head3"
if ! gs check "$tree3" dev; then ok "from-push: a tag push writes no stamp"; else fail "from-push: tag stamped"; fi
printf '%s\n%s\n' "refs/heads/fix/x $head3 refs/heads/fix/x $z" "refs/heads/fix/old $base_sha refs/heads/fix/old $z" \
  | gs from-push "$green_log" "$head3" 2>/dev/null
if ! gs check "$tree3" dev; then ok "from-push: one ref off HEAD, no stamp for any ref"; else fail "from-push: mixed push stamped"; fi

# 13
# shellcheck disable=SC1091  # scripts/labctl-path.sh: labctl_find
. "$HERE/labctl-path.sh"
lhome="$WORK/lhome"; mkdir -p "$lhome/.claude/bin" "$WORK/pathbin"
printf '#!/bin/sh\n' >"$lhome/.claude/bin/labctl"; chmod +x "$lhome/.claude/bin/labctl"
printf '#!/bin/sh\n' >"$WORK/pathbin/labctl"; chmod +x "$WORK/pathbin/labctl"
got="$(unset LABCTL; HOME="$lhome" PATH="$WORK/pathbin:$PATH" labctl_find)"
if [ "$got" = "$lhome/.claude/bin/labctl" ]; then ok "labctl_find: the shared ~/.claude/bin/labctl comes before PATH"; else fail "labctl_find shared: '$got'"; fi
got="$(LABCTL="$WORK/own" HOME="$lhome" labctl_find)"
if [ "$got" = "$WORK/own" ]; then ok "labctl_find: LABCTL wins"; else fail "labctl_find override: '$got'"; fi
rm "$lhome/.claude/bin/labctl"
got="$(unset LABCTL; HOME="$lhome" PATH="$WORK/pathbin:$PATH" labctl_find)"
if [ "$got" = "$WORK/pathbin/labctl" ]; then ok "labctl_find: falls back to PATH"; else fail "labctl_find PATH: '$got'"; fi
# Keep the host's Git (Git for Windows uses /mingw64/bin), hiding only
# labctl. Explicitly forward runtime dependencies through executable wrappers;
# symlinks/copying git.exe lose its DLL lookup paths on Windows.
no_lab_path="$WORK/no-lab-bin"
mkdir -p "$no_lab_path"
for tool in bash git dirname uname date; do
  tool_path="$(command -v "$tool")"
  printf '#!/bin/bash\nexec %q "$@"\n' "$tool_path" >"$no_lab_path/$tool"
  chmod +x "$no_lab_path/$tool"
done
got="$(unset LABCTL; HOME="$lhome" PATH="$no_lab_path:/usr/bin:/bin" labctl_find)"
if [ -z "$got" ]; then ok "labctl_find: nothing when labctl is missing"; else fail "labctl_find none: '$got'"; fi
out="$(cd "$repo" && unset LABCTL; HOME="$lhome" PATH="$no_lab_path:/usr/bin:/bin" bash "$HERE/native-compile-check.sh" --force --no-wait HEAD~1..HEAD 2>&1)"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'labctl not found'; then ok "native-compile-check: no labctl is closed with the reason (rc 2)"; else fail "no labctl (rc=$rc): $out"; fi
out="$(cd "$HERE/.." && unset LABCTL; HOME="$lhome" PATH="$no_lab_path:/usr/bin:/bin" bash "$HERE/release.sh" stage gate v9.9.9 --sha HEAD --dry-run 2>&1)"; rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'labctl not found'; then ok "release.sh: S1 without labctl aborts with a clear message"; else fail "release gate no labctl (rc=$rc): $out"; fi
out="$(cd "$HERE/.." && LABCTL="$WORK/missing" HOME="$lhome" bash "$HERE/release.sh" stage gate v9.9.9 --sha HEAD --dry-run 2>&1)"; rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'labctl not found'; then ok "release.sh: a LABCTL that does not exist aborts too"; else fail "release gate bad LABCTL (rc=$rc): $out"; fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
