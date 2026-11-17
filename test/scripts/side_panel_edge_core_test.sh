#!/usr/bin/env bash
# Compiles and runs the side panel edge-trigger test (#1782,
# linux/runner/side_panel_edge_core_test.cc) and checks that the Windows
# runner carries the same core header. Platform-neutral C++17, runs on macOS
# too. On macOS it also runs the same cases against the Swift mirror
# (SidePanelEdgeCore in macos/Runner/SidePanelWindow.swift).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if ! cmp -s "$ROOT/linux/runner/side_panel_edge_core.h" \
  "$ROOT/windows/runner/side_panel_edge_core.h"; then
  echo "FAIL: windows/runner/side_panel_edge_core.h drifted from linux/runner" >&2
  exit 1
fi
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/side_panel_edge_core_test.cc" -o "$OUT/side_panel_edge_core_test"
"$OUT/side_panel_edge_core_test"

if [ "$(uname -s)" = Darwin ] && command -v swiftc >/dev/null 2>&1; then
  # The struct runs from its declaration to the first closing brace in
  # column 0; it uses Swift only, so it compiles without Cocoa/Flutter.
  awk '/^struct SidePanelEdgeCore \{/{on=1} on{print} on&&/^\}/{exit}' \
    "$ROOT/macos/Runner/SidePanelWindow.swift" >"$OUT/core.swift"
  if ! grep -q 'mutating func update' "$OUT/core.swift"; then
    echo "FAIL: SidePanelEdgeCore not found in SidePanelWindow.swift" >&2
    exit 1
  fi
  cp "$ROOT/test/scripts/side_panel_edge_core_test.swift" "$OUT/main.swift"
  swiftc -module-cache-path "$OUT/mc" "$OUT/core.swift" "$OUT/main.swift" \
    -o "$OUT/side_panel_edge_core_test_swift"
  "$OUT/side_panel_edge_core_test_swift"
fi
