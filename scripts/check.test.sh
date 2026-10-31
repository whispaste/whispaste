#!/usr/bin/env bash
# check.test.sh — scripts/check.sh runs the push tests on a lab ubu guest
# only: with a stub dispatcher
#   1. a free guest: one run, --host ubu, its result passed through
#   2. a busy lab (rc 75): no second run, never --host mac, rc 75 kept
#   3. the ubu wait defaults to the rest of the budget
# Run: bash scripts/check.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/wp-test" <<'EOF'
#!/bin/sh
echo "$* wait=${WP_QUEUE_TIMEOUT:-}" >>"$STUB_LOG"
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
wait_s="$(sed -n 's/.* wait=//p' "$STUB_LOG")"
if [ -n "$wait_s" ] && [ "$wait_s" -ge 290 ]; then
  ok "the ubu wait is the rest of the budget"
else
  fail "ubu wait ($wait_s)"
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
