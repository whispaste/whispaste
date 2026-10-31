#!/usr/bin/env bash
# V1 Wayland: GNOME custom keybinding fallback against the real gsettings and
# dconf. Runs test/services/linux_desktop_shortcut_e2e_test.dart in its own
# D-Bus session with a throwaway XDG_CONFIG_HOME, and checks that the user's
# own dconf keybindings did not change.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KEYS=/org/gnome/settings-daemon/plugins/media-keys/
before="$(dconf dump "$KEYS" 2>/dev/null || true)"
RUN="$(mktemp -d)"
trap 'rm -rf "$RUN"' EXIT
mkdir -p "$RUN/config"

L="$HOME/.cache/whispaste-flutter.lock"
until (set -C; echo "gnome-shortcut-e2e-$$" >"$L") 2>/dev/null; do sleep 5; done
# shellcheck disable=SC2064  # expand now: the lock owner is this run
trap "grep -qx 'gnome-shortcut-e2e-$$' '$L' && rm -f '$L'; rm -rf '$RUN'" EXIT

cd "$ROOT"
env XDG_CONFIG_HOME="$RUN/config" WP_GNOME_SHORTCUT_E2E=1 \
  timeout 600 dbus-run-session -- \
  flutter test test/services/linux_desktop_shortcut_e2e_test.dart

after="$(dconf dump "$KEYS" 2>/dev/null || true)"
if [ "$before" != "$after" ]; then
  echo "FAIL: the user's own dconf keybindings changed" >&2
  exit 1
fi
echo "PASS: GNOME shortcut end to end; user dconf untouched"
