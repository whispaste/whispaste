#!/usr/bin/env bash
# End-to-end check against the real Klipper (PAR-012): on a private Xvfb with
# its own D-Bus session, start the Plasma clipboard applet (Klipper), put a
# plain control text and a hinted text (clipboard_hint.cc) on the clipboard,
# then read Klipper's history over D-Bus. Passes when Klipper kept the plain
# texts and skipped the hinted one.
#
# Manual check, not in CI: needs plasma-workspace (plasmawindowed, qdbus6),
# libgtk-3-dev and xvfb. Never touches the running desktop session.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for tool in plasmawindowed qdbus6 xvfb-run dbus-run-session; do
  command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 2; }
done
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
# shellcheck disable=SC2046  # pkg-config prints separate flags on purpose
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/clipboard_hint.cc" \
  "$ROOT/linux/runner/clipboard_hint_hold.cc" \
  $(pkg-config --cflags --libs gtk+-3.0) -o "$OUT/hold"

cat >"$OUT/inner.sh" <<'INNER'
set -u
OUT="$1"
export QT_QPA_PLATFORM=xcb GDK_BACKEND=x11
unset WAYLAND_DISPLAY
# Fresh Klipper config and history, so an earlier run cannot fake a pass and
# the user's own Klipper data stays untouched.
export XDG_CONFIG_HOME="$OUT/config" XDG_DATA_HOME="$OUT/data" \
  XDG_CACHE_HOME="$OUT/cache" XDG_STATE_HOME="$OUT/state"
plasmawindowed org.kde.plasma.clipboard >"$OUT/klipper.log" 2>&1 &
klipper=$!
for _ in $(seq 1 40); do
  qdbus6 org.kde.klipper /klipper >/dev/null 2>&1 && break
  sleep 0.5
done
"$OUT/hold" plain "whispaste-plain-before"; sleep 1
"$OUT/hold" hint "whispaste-hinted"; sleep 1
"$OUT/hold" plain "whispaste-plain-after"; sleep 1
for i in 0 1 2 3; do
  qdbus6 org.kde.klipper /klipper \
    org.kde.klipper.klipper.getClipboardHistoryItem "$i" 2>/dev/null || true
done >"$OUT/history.txt"
kill "$klipper" 2>/dev/null || true
wait "$klipper" 2>/dev/null || true
INNER

timeout 120 xvfb-run -a dbus-run-session -- bash "$OUT/inner.sh" "$OUT" \
  >/dev/null 2>&1 || true

echo "Klipper history:"
sed 's/^/  /' "$OUT/history.txt"
grep -qx "whispaste-plain-before" "$OUT/history.txt" ||
  { echo "FAIL: Klipper did not record the plain control (not running?)"; exit 1; }
grep -qx "whispaste-plain-after" "$OUT/history.txt" ||
  { echo "FAIL: Klipper did not record the second plain control"; exit 1; }
if grep -qx "whispaste-hinted" "$OUT/history.txt"; then
  echo "FAIL: Klipper recorded the hinted text"
  exit 1
fi
echo "klipper_hint_e2e: Klipper skipped the hinted text"
