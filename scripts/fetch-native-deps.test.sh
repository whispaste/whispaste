#!/usr/bin/env bash
# fetch-native-deps.test.sh — tests for scripts/fetch-native-deps.sh against
# throw-away local repos (no network, the real .build/deps is never touched):
#   1. first run fetches the pinned tag into <lib>/<tag>
#   2. second run is idempotent ("present")
#   3. a pin whose commit differs from the tag fails and leaves no tree
#   4. an existing tree at the wrong commit fails and stays untouched
#   5. a stale lock (dead pid) is taken over; a live one times out; one
#      left without a pid is taken over after the orphan grace
#   6. an unknown name exits 2 before anything is fetched
# Run: bash scripts/fetch-native-deps.test.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/fetch-native-deps.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/fetch-native-deps.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

failures=0
ok() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1"
  [[ -n "${2:-}" ]] && sed 's/^/       /' "$2"
  failures=$((failures + 1))
}

g() { git -c user.name=test -c user.email=test "$@"; }

# upstream <dir> <tag> — a repo with one commit tagged <tag>; prints its sha.
upstream() {
  g init -q "$1"
  g -C "$1" commit -q --allow-empty -m "release $2"
  g -C "$1" tag "$2"
  g -C "$1" rev-parse HEAD
}

W_SHA="$(upstream "$WORK/up/whisper" v1.0.0)"
mkdir -p "$WORK/pins"
printf 'WHISPER_TAG=v1.0.0\nWHISPER_COMMIT=%s\n' "$W_SHA" >"$WORK/pins/whisper-cpp.pin"

export NATIVE_DEPS_DIR="$WORK/deps"
export NATIVE_DEPS_PIN_DIR="$WORK/pins"
export NATIVE_DEPS_URL_WHISPER="$WORK/up/whisper"
export NATIVE_DEPS_LOCK_TIMEOUT=2
TARGET="$WORK/deps/whisper.cpp/v1.0.0"

# 1
if bash "$SCRIPT" whisper >"$WORK/out" 2>&1 && [[ "$(git -C "$TARGET" rev-parse HEAD)" == "$W_SHA" ]]; then
  ok "first run fetches the pinned tag"
else
  fail "first run" "$WORK/out"
fi

# 2
if bash "$SCRIPT" whisper >"$WORK/out" 2>&1 && grep -q "present" "$WORK/out"; then
  ok "second run is idempotent"
else
  fail "second run" "$WORK/out"
fi

# 3
rm -rf "$TARGET"
printf 'WHISPER_TAG=v1.0.0\nWHISPER_COMMIT=%s\n' 0123456789abcdef0123456789abcdef01234567 >"$WORK/pins/whisper-cpp.pin"
if ! bash "$SCRIPT" whisper >"$WORK/out" 2>&1 && [[ ! -e "$TARGET" ]] &&
  [[ -z "$(find "$WORK/deps/whisper.cpp" -name '.tmp.*' 2>/dev/null)" ]]; then
  ok "a commit mismatch fails and leaves no tree"
else
  fail "commit mismatch" "$WORK/out"
fi

# 4
printf 'WHISPER_TAG=v1.0.0\nWHISPER_COMMIT=%s\n' "$W_SHA" >"$WORK/pins/whisper-cpp.pin"
mkdir -p "$TARGET"
echo foreign >"$TARGET/marker"
if ! bash "$SCRIPT" whisper >"$WORK/out" 2>&1 && [[ -f "$TARGET/marker" ]]; then
  ok "a foreign tree fails and stays untouched"
else
  fail "foreign tree" "$WORK/out"
fi
rm -rf "$TARGET"

# 5
mkdir -p "$WORK/deps/.fetch.lock"
sh -c 'exit 0' &
dead=$!
wait "$dead"
echo "$dead" >"$WORK/deps/.fetch.lock/pid"
if bash "$SCRIPT" whisper >"$WORK/out" 2>&1 && [[ ! -e "$WORK/deps/.fetch.lock" ]]; then
  ok "a stale lock is taken over and released"
else
  fail "stale lock" "$WORK/out"
fi
mkdir -p "$WORK/deps/.fetch.lock"
echo $$ >"$WORK/deps/.fetch.lock/pid"
if ! bash "$SCRIPT" whisper >"$WORK/out" 2>&1 && grep -q "still held" "$WORK/out"; then
  ok "a live lock times out"
else
  fail "live lock" "$WORK/out"
fi
rm -rf "$WORK/deps/.fetch.lock"
mkdir -p "$WORK/deps/.fetch.lock"
if NATIVE_DEPS_LOCK_ORPHAN=1 bash "$SCRIPT" whisper >"$WORK/out" 2>&1 &&
  [[ ! -e "$WORK/deps/.fetch.lock" ]]; then
  ok "a lock without a pid is taken over and released"
else
  fail "ownerless lock" "$WORK/out"
fi
rm -rf "$WORK/deps/.fetch.lock"

# 6
rm -rf "$TARGET"
bash "$SCRIPT" whisper nope >"$WORK/out" 2>&1
rc=$?
if [[ "$rc" == 2 && ! -e "$TARGET" ]]; then
  ok "an unknown name exits 2 before fetching"
else
  fail "unknown name (rc=$rc)" "$WORK/out"
fi

echo
if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
