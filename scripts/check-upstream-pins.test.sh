#!/usr/bin/env bash
# check-upstream-pins.test.sh — logic tests for check-upstream-pins.sh without
# network: fixture pins plus a prepared cache, UPSTREAM_PINS_OFFLINE=1.
# Run: bash scripts/check-upstream-pins.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-upstream-pins.sh"
NOW=1800000000
DAY=86400

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail=0

# fixture <name> <whisper_tag> <sherpa_tag> [hold_reason hold_check]
fixture() {
  local d="$WORK/$1"
  mkdir -p "$d/scripts"
  printf 'WHISPER_TAG=%s\nWHISPER_COMMIT=abc\nUPSTREAM_HOLD_REASON=%s\nUPSTREAM_HOLD_CHECK=%s\n' \
    "$2" "${4:-}" "${5:-}" >"$d/scripts/whisper-cpp.pin"
  printf 'SHERPA_TAG=%s\nUPSTREAM_HOLD_REASON=\nUPSTREAM_HOLD_CHECK=\n' "$3" >"$d/scripts/sherpa-onnx.pin"
  llama_pin "$d" "${LLAMA_PIN:-v0.8.0}"
  echo "$d"
}

# llama_pin <dir> <tag> [hold_reason hold_check]
llama_pin() {
  printf 'LLAMA_TAG=%s\nLLAMA_COMMIT=abc\nUPSTREAM_HOLD_REASON=%s\nUPSTREAM_HOLD_CHECK=%s\n' \
    "$2" "${3:-}" "${4:-}" >"$1/scripts/llama-cpp.pin"
}

# cache <dir> <whisper_latest> <sherpa_latest> <fetched_epoch> [llama_latest]
cache() {
  printf 'ggml-org/whisper.cpp %s %s %s\nk2-fsa/sherpa-onnx %s %s %s\nggml-org/llama.cpp %s %s %s\n' \
    "$2" $((NOW - 3 * DAY)) "$4" "$3" $((NOW - DAY)) "$4" "${5:-v0.8.0}" $((NOW - 2 * DAY)) "$4" >"$1/cache"
}

# expect <label> <want_rc> <want_output_regex|-> <dir> [--strict]
expect() {
  local label="$1" want_rc="$2" want_out="$3" dir="$4" out rc
  shift 4
  out="$(UPSTREAM_PINS_ROOT="$dir" UPSTREAM_PINS_CACHE="$dir/cache" \
    UPSTREAM_PINS_OFFLINE=1 UPSTREAM_PINS_NOW=$NOW bash "$CHECK" "$@" 2>&1)"
  rc=$?
  if [[ "$rc" != "$want_rc" ]]; then
    echo "FAIL $label: rc=$rc, want $want_rc; output: $out"; fail=1; return
  fi
  if [[ "$want_out" == - ]]; then
    [[ -z "$out" ]] || { echo "FAIL $label: want no output, got: $out"; fail=1; return; }
  elif ! grep -Eq "$want_out" <<<"$out"; then
    echo "FAIL $label: output does not match /$want_out/: $out"; fail=1; return
  fi
  echo "ok   $label"
}

d="$(fixture current v1.9.5 v1.13.4)"; cache "$d" v1.9.5 v1.13.4 $NOW
expect "pins current: silent" 0 - "$d"
expect "pins current, strict: passes" 0 - "$d" --strict

d="$(fixture newer v1.9.5 v1.13.4)"; cache "$d" v1.9.6 v1.13.4 $NOW
expect "newer whisper.cpp: warns with age" 0 'whisper\.cpp v1\.9\.6 verfügbar \(seit 3 Tagen\)' "$d"
expect "newer whisper.cpp, strict: fails" 1 'vor dem Release anheben' "$d" --strict

d="$(fixture minor v1.9.5 v1.13.4)"; cache "$d" v1.10.0 v1.13.4 $NOW
expect "v1.10.0 is newer than v1.9.5" 0 'v1\.10\.0 verfügbar' "$d"

d="$(fixture ahead v1.9.6 v1.13.4)"; cache "$d" v1.9.5 v1.13.4 $NOW
expect "pin ahead of upstream: silent" 0 - "$d"

d="$(fixture hold v1.9.5 v1.13.4 "'regression (v1.9.6)'" "'upstream issue closed'")"
cache "$d" v1.9.6 v1.13.4 $NOW
expect "documented hold, strict: passes with note" 0 'gehalten: regression \(v1\.9\.6\) \(aufheben' "$d" --strict
( set -e; . "$d/scripts/whisper-cpp.pin" ) && echo "ok   quoted hold sources cleanly" || { echo "FAIL quoted hold does not source"; fail=1; }

d="$(fixture halfhold v1.9.5 v1.13.4 'reason only' '')"; cache "$d" v1.9.6 v1.13.4 $NOW
expect "hold without its check, strict: fails" 1 'Ausnahme' "$d" --strict

d="$(fixture stale v1.9.5 v1.13.4)"; cache "$d" v1.9.6 v1.13.4 $((NOW - 2 * DAY))
expect "cache older than 24 h and offline: silent" 0 - "$d"
expect "offline, strict: fails as not checkable" 1 'not checkable' "$d" --strict

d="$(LLAMA_PIN=b10150 fixture btag v1.9.5 v1.13.4)"; cache "$d" v1.9.5 v1.13.4 $NOW b10200
expect "build tags compare by number (b10150 < b10200)" 0 'llama\.cpp b10200 verfügbar' "$d"

d="$(LLAMA_PIN=b10150 fixture btag2 v1.9.5 v1.13.4)"; cache "$d" v1.9.5 v1.13.4 $NOW b9999
expect "b10150 is newer than b9999: silent" 0 - "$d"

d="$(LLAMA_PIN=b10150 fixture scheme v1.9.5 v1.13.4)"; cache "$d" v1.9.5 v1.13.4 $NOW v0.8.0
expect "b-tag against a v-release is reported, never silent" 0 'llama\.cpp v0\.8\.0 verfügbar' "$d"
expect "b-tag against a v-release, strict: fails without hold" 1 'llama\.cpp v0\.8\.0 verfügbar.*anheben' "$d" --strict
llama_pin "$d" b10150 "'shim API changes'" "'shim builds on v0.8.0'"
expect "b-tag against a v-release, strict: passes with hold" 0 'gehalten: shim API changes' "$d" --strict


exit "$fail"
