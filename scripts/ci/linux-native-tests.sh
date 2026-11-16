#!/usr/bin/env bash
# linux-native-tests.sh — the C++ unit and runtime tests of the Linux runner,
# the vendored hotkey_manager_linux and the Win32-free helpers of the Windows
# runner (raw_key_side), in one list for CI and the pre-push
# (PAR-067). Each test compiles its sources and runs them, the runtime ones on
# a private Xvfb display. Linux only.
#
# Usage: bash scripts/ci/linux-native-tests.sh [--install-deps]
#        bash scripts/ci/linux-native-tests.sh --inputs
#   --install-deps  apt-get the missing build and display packages (sudo)
#   --inputs        print the paths whose change makes the pre-push run this
# Exit: 0 all green, 1 a test failed, 2 missing packages.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TESTS=(
  diagnose_launch
  autorepeat_filter
  modifier_release
  desktop_entry
  window_manager_kind
  menu_mask
  raw_key_side
  clipboard_hint
  x11_window
  clipboard_receipt
  clipboard_snapshot
  keybinder_raw
  hang_watchdog_core
  message_clock
  uinput_access
  undo_policy
  video_audio_decode
)

# Debian packages the tests need: compiler, GTK/X11/keybinder headers, Xvfb
# and setxkbmap (keybinder_raw switches the layout).
PACKAGES=(g++ pkg-config libgtk-3-dev libx11-dev libxtst-dev
  libkeybinder-3.0-dev xvfb x11-xkb-utils)

if [ "${1:-}" = --inputs ]; then
  # raw_key_side: a Win32-free helper of the Windows runner, tested here
  # because it is plain C++ (#263).
  printf '%s\n' linux/runner/ packages/hotkey_manager_linux/linux/ \
    windows/runner/raw_key_side.h windows/runner/raw_key_side_test.cc \
    scripts/ci/linux-native-tests.sh scripts/build-video-decoder.py \
    test/fixtures/video_import/ test/scripts/video_audio_decode_test.py \
    test/scripts/video_decoder_download_test.py \
    windows/runner/undo_policy.h \
    windows/runner/undo_policy_test.cc windows/runner/message_clock.h \
    windows/runner/message_clock_test.cc windows/runner/hang_watchdog_core.h
  for t in "${TESTS[@]}"; do printf 'test/scripts/%s_test.sh\n' "$t"; done
  exit 0
fi

missing_pkgs() {
  local p
  for p in "${PACKAGES[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || echo "$p"
  done
}

PKGS="$(missing_pkgs | tr '\n' ' ')"
if [ -n "$PKGS" ] && [ "${1:-}" = --install-deps ]; then
  # Bounded and retried like packaging-validate.sh: a dead mirror must not
  # hold the gate.
  for attempt in 1 2 3; do
    timeout 120 sudo apt-get update -qq && break
    if [ "$attempt" -eq 3 ]; then
      echo "linux-native-tests: apt-get update failed after 3 attempts." >&2
      exit 2
    fi
    sleep 15
  done
  # shellcheck disable=SC2086 # one word per package
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $PKGS >/dev/null || exit 2
  PKGS="$(missing_pkgs | tr '\n' ' ')"
fi
if [ -n "$PKGS" ]; then
  echo "linux-native-tests: missing packages: ${PKGS% }; rerun with --install-deps" >&2
  exit 2
fi

failed=()
for t in "${TESTS[@]}"; do
  echo "── $t"
  if ! bash "$ROOT/test/scripts/${t}_test.sh"; then
    failed+=("$t")
  fi
done
if [ "${#failed[@]}" -gt 0 ]; then
  echo "linux-native-tests: failed: ${failed[*]}" >&2
  exit 1
fi
echo "linux-native-tests: ${#TESTS[@]} passed"
