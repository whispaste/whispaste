#!/usr/bin/env bash
# Compiles and runs the hang watchdog decision test (#338,
# linux/runner/hang_watchdog_core_test.cc) and checks that the Windows runner
# carries the same core header. Platform-neutral C++17, runs on macOS too.
# On macOS it also runs the same cases against the Swift mirror
# (HangWatchdogCore in macos/Runner/HangWatchdogHost.swift).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if ! cmp -s "$ROOT/linux/runner/hang_watchdog_core.h" \
  "$ROOT/windows/runner/hang_watchdog_core.h"; then
  echo "FAIL: windows/runner/hang_watchdog_core.h drifted from linux/runner" >&2
  exit 1
fi
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/hang_watchdog_core_test.cc" -o "$OUT/hang_watchdog_core_test"
"$OUT/hang_watchdog_core_test"

if [ "$(uname -s)" = Darwin ] && command -v swiftc >/dev/null 2>&1; then
  # The struct runs from its declaration to the first closing brace in
  # column 0; it uses Swift only, so it compiles without Cocoa/Flutter.
  awk '/^struct HangWatchdogCore \{/{on=1} on{print} on&&/^\}/{exit}' \
    "$ROOT/macos/Runner/HangWatchdogHost.swift" >"$OUT/core.swift"
  if ! grep -q 'static func mayRestart' "$OUT/core.swift"; then
    echo "FAIL: HangWatchdogCore not found in HangWatchdogHost.swift" >&2
    exit 1
  fi
  cp "$ROOT/test/scripts/hang_watchdog_core_test.swift" "$OUT/main.swift"
  swiftc -module-cache-path "$OUT/mc" "$OUT/core.swift" "$OUT/main.swift" \
    -o "$OUT/hang_watchdog_core_test_swift"
  "$OUT/hang_watchdog_core_test_swift"
fi
