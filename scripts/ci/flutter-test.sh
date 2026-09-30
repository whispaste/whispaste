#!/usr/bin/env bash
# flutter-test.sh — `flutter test "$@"`, retried ONLY on the one known
# transient flake: the sqlite3 native-asset build hook downloading its
# prebuilt library from GitHub Releases ("Connection closed before full
# header was received", run 31663460234).
#
# Any other failure fails on the first attempt. The previous blanket
# 3x retry reran the whole suite on genuine test failures too — tripling
# the time to a red signal (run 36697607161: 24 min instead of ~8) and
# pushing a loaded self-hosted job past its timeout.
#
# It also runs one test process per CPU core unless the caller passes
# -j/--concurrency: `flutter test` defaults to half the cores, which on the
# 3-core hosted macOS runner means every test file runs strictly serially.
set -uo pipefail

jobs=()
case " $* " in
  *" -j"*|*" --concurrency"*) ;;
  *) jobs=("--concurrency=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)") ;;
esac

log="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/flutter-test-$$.log"
for attempt in 1 2 3; do
  flutter test ${jobs[@]+"${jobs[@]}"} "$@" 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  [ "$rc" -eq 0 ] && exit 0
  if ! grep -qE 'Connection closed before full header was received|Failed host lookup: .(github\.com|objects\.githubusercontent\.com)' "$log"; then
    exit "$rc"
  fi
  if [ "$attempt" -lt 3 ]; then
    echo "::warning::flutter test hit the native-asset download flake (attempt $attempt/3) — retrying in 15s."
    sleep 15
  fi
done
echo "::error::flutter test still hit the native-asset download flake after 3 attempts."
exit 1
