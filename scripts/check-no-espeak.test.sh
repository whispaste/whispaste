#!/usr/bin/env bash
# check-no-espeak.test.sh — negative test for scripts/check-no-espeak.sh.
# Generates tiny fixtures at runtime (no GPL code, no committed marker bytes):
#   1. an ELF-looking file carrying an espeak-ng marker  -> guard must FAIL
#   2. a renamed espeak file (name only, no marker)      -> guard must FAIL
#   3. a real clean shared library (compiled here)       -> guard must PASS
#   4. a directory without native files                  -> guard must FAIL
#   5. a real shared library exporting an espeak-named
#      symbol that no byte marker covers                 -> symbol check must FAIL (GS-009)
#   6. a native-looking file whose symbols cannot be read -> guard must FAIL (fail closed)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-no-espeak.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-no-espeak.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

failures=0
expect() { # expect <wanted-exit: 0|nonzero> <label> <path>
  local want="$1" label="$2" path="$3" rc
  bash "$GUARD" "$path" >"$WORK/out.txt" 2>&1
  rc=$?
  if [[ "$want" == "0" && $rc -eq 0 ]] || [[ "$want" == "nonzero" && $rc -ne 0 ]]; then
    echo "ok   - $label (exit $rc)"
  else
    echo "FAIL - $label: wanted $want, got exit $rc"
    cat "$WORK/out.txt"
    failures=$((failures + 1))
  fi
}

mkdir -p "$WORK/bad" "$WORK/renamed" "$WORK/clean" "$WORK/empty"

# 1. ELF magic followed by the espeak-ng symbol name.
printf '\177ELF\002\001\001\000espeak_ng_Initialize\000' > "$WORK/bad/libfixture.so"
expect nonzero "espeak-ng marker in a native file" "$WORK/bad"

# 2. A file whose name says espeak (no marker needed to fail).
printf 'plain text, no marker\n' > "$WORK/renamed/espeak-ng-data.txt"
expect nonzero "espeak in a file name" "$WORK/renamed"

# 3. A real shared library without any espeak name.
if ! command -v cc >/dev/null 2>&1; then
  echo "error: cc is required for the symbol-check cases" >&2
  exit 2
fi
printf 'int sherpa_onnx_create_recognizer(void) { return 0; }\n' > "$WORK/clean.c"
cc -shared -fPIC -o "$WORK/clean/libclean.so" "$WORK/clean.c"
expect 0 "real clean shared library passes" "$WORK/clean"

# 5. A real shared library whose exported symbol carries no marker string: only
#    the symbol check can catch it. The name avoids every byte marker.
mkdir -p "$WORK/symbol"
printf 'int espeak_xyz_probe(void) { return 0; }\n' > "$WORK/symbol.c"
cc -shared -fPIC -o "$WORK/symbol/libprobe.so" "$WORK/symbol.c"
expect nonzero "espeak-named exported symbol without a marker" "$WORK/symbol"
if ! grep -q "symbol table" "$WORK/out.txt"; then
  echo "FAIL - the symbol-table failure message was not printed"
  failures=$((failures + 1))
fi

# 6. A native magic that nm cannot read as an object: fail closed.
mkdir -p "$WORK/unreadable"
printf '\177ELF\002\001\001\000not really an object\000' > "$WORK/unreadable/libfake.so"
expect nonzero "native file with unreadable symbols fails" "$WORK/unreadable"

# 4. Nothing native to scan is an error, not a silent pass.
printf 'notes\n' > "$WORK/empty/README.txt"
expect nonzero "no native files at all is an error" "$WORK/empty"

if [[ $failures -ne 0 ]]; then
  echo "check-no-espeak.test: $failures case(s) failed"
  exit 1
fi
echo "check-no-espeak.test: all cases passed"
