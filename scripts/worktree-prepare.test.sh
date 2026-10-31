#!/usr/bin/env bash
# worktree-prepare.test.sh — shell test for scripts/worktree-prepare.sh and the
# syntax of scripts/mac-build-smoke.sh. Uses a throw-away git repo with a real
# worktree and a fake pub cache (PUB_CACHE), so ~/.pub-cache and the real
# .build directories are never touched. The mac smoke itself needs a Mac GUI
# session and is verified by running it, not here.
#   1. first run copies the missing deps            -> copied 2
#   2. second run is idempotent                     -> copied 0, present 2
#   3. foreign flutter_soloud cmake_build is removed
#   4. own flutter_soloud cmake_build is kept
#   5. usage and non-worktree errors exit 2
#   6. bash -n passes for both scripts
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREPARE="$REPO_ROOT/scripts/worktree-prepare.sh"
SMOKE="$REPO_ROOT/scripts/mac-build-smoke.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/worktree-prepare.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

failures=0
ok() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1"
  [[ -n "${2:-}" ]] && sed 's/^/       /' "$2"
  failures=$((failures + 1))
}

MAIN="$WORK/main"
WT="$WORK/wt"
PUB="$WORK/pub"
mkdir -p "$MAIN/.build/deps/llama.cpp/b10150" "$MAIN/.build/deps/sherpa-onnx/v1.13.4"
echo marker >"$MAIN/.build/deps/llama.cpp/b10150/marker.txt"
echo marker >"$MAIN/.build/deps/sherpa-onnx/v1.13.4/marker.txt"
git -C "$MAIN" init -q
git -C "$MAIN" -c user.name=test -c user.email=test commit -q --no-verify --allow-empty -m init
git -C "$MAIN" worktree add -q -b prepare-test "$WT" >/dev/null 2>&1 || {
  echo "FAIL - fixture: could not create worktree"
  exit 1
}
WT="$(cd "$WT" && pwd)"
EXPECTED_HOME="$WT/macos/Flutter/ephemeral/.symlinks/plugins/flutter_soloud/macos"
SOLOUD="$PUB/hosted/pub.dev/flutter_soloud-4.0.13/macos/cmake_build"

run_prepare() { # run_prepare <outfile>; sets rc
  PUB_CACHE="$PUB" bash "$PREPARE" "$WT" >"$1" 2>&1
  rc=$?
}

# 1. first run copies the missing deps
run_prepare "$WORK/out1.txt"
if [[ $rc -eq 0 && -f "$WT/.build/deps/llama.cpp/b10150/marker.txt" \
  && -f "$WT/.build/deps/sherpa-onnx/v1.13.4/marker.txt" ]] \
  && grep -q "deps: copied 2, already present 0" "$WORK/out1.txt"; then
  ok "first run copies missing deps"
else
  fail "first run copies missing deps (rc=$rc)" "$WORK/out1.txt"
fi

# 2. second run is idempotent
run_prepare "$WORK/out2.txt"
if [[ $rc -eq 0 ]] && grep -q "deps: copied 0, already present 2" "$WORK/out2.txt"; then
  ok "second run is idempotent"
else
  fail "second run is idempotent (rc=$rc)" "$WORK/out2.txt"
fi

# 3. foreign flutter_soloud cmake_build is removed
mkdir -p "$SOLOUD/macosx"
printf 'CMAKE_HOME_DIRECTORY:INTERNAL=/elsewhere/other-worktree/macos\n' >"$SOLOUD/macosx/CMakeCache.txt"
run_prepare "$WORK/out3.txt"
if [[ $rc -eq 0 && ! -e "$SOLOUD" ]] && grep -q "removed foreign cmake_build" "$WORK/out3.txt"; then
  ok "foreign cmake_build is removed"
else
  fail "foreign cmake_build is removed (rc=$rc)" "$WORK/out3.txt"
fi

# 4. own flutter_soloud cmake_build is kept
mkdir -p "$SOLOUD/macosx"
printf 'CMAKE_HOME_DIRECTORY:INTERNAL=%s\n' "$EXPECTED_HOME" >"$SOLOUD/macosx/CMakeCache.txt"
run_prepare "$WORK/out4.txt"
if [[ $rc -eq 0 && -f "$SOLOUD/macosx/CMakeCache.txt" ]] && grep -q "soloud: ok" "$WORK/out4.txt"; then
  ok "own cmake_build is kept"
else
  fail "own cmake_build is kept (rc=$rc)" "$WORK/out4.txt"
fi

# 5. usage and non-worktree errors exit 2
bash "$PREPARE" >/dev/null 2>&1
if [[ $? -eq 2 ]]; then ok "no argument exits 2"; else fail "no argument exits 2"; fi
PUB_CACHE="$PUB" bash "$PREPARE" "$WORK" >/dev/null 2>&1
if [[ $? -eq 2 ]]; then ok "non-worktree directory exits 2"; else fail "non-worktree directory exits 2"; fi
bash "$SMOKE" >/dev/null 2>&1
if [[ $? -eq 2 ]]; then ok "mac-build-smoke without argument exits 2"; else fail "mac-build-smoke without argument exits 2"; fi

# 6. syntax
for s in "$PREPARE" "$SMOKE" "$0"; do
  if bash -n "$s" 2>"$WORK/syntax.txt"; then
    ok "bash -n $(basename "$s")"
  else
    fail "bash -n $(basename "$s")" "$WORK/syntax.txt"
  fi
done

if (( failures > 0 )); then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
