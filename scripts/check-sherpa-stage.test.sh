#!/usr/bin/env bash
# check-sherpa-stage.test.sh — negative and positive tests for
# check-sherpa-stage.cmake, using fixture repos built at runtime (no real
# binaries). Run: bash scripts/check-sherpa-stage.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-sherpa-stage.cmake"
PIN_TAG=v1.13.4
PIN_COMMIT=142807252687d81b40d6315f23470a1512a00de3

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake is required for this test" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail=0

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# SHA-256 of the fixture library content written by make_fixture (GS-013 pin).
printf 'fixture library\n' > "$WORK/fixture-lib"
FIXTURE_LIB_SHA="$(sha256_of "$WORK/fixture-lib")"

# make_fixture <name> <pin_tag> <pin_commit> <lock_version> <info_tag> <info_commit> <with_info> <with_lib> [macos_repo_pin]
make_fixture() {
  local dir="$WORK/$1"
  mkdir -p "$dir/repo/scripts" "$dir/stage"
  printf 'SHERPA_TAG=%s\nSHERPA_COMMIT=%s\nSHERPA_C_API_SHA256_MACOS=%s\nSHERPA_C_API_SHA256_WINDOWS_X64=\nSHERPA_C_API_SHA256_LINUX_X64=\nSHERPA_C_API_SHA256_LINUX_AARCH64=\n' \
    "$2" "$3" "${9:-}" > "$dir/repo/scripts/sherpa-onnx.pin"
  cat > "$dir/repo/pubspec.lock" <<LOCK
packages:
  sherpa_onnx:
    dependency: "direct main"
    description:
      name: sherpa_onnx
    source: hosted
    version: "$4"
  other_pkg:
    dependency: transitive
    version: "9.9.9"
sdks:
  dart: ">=3.0.0"
LOCK
  if [[ "$7" == "1" ]]; then
    printf 'sherpa-onnx %s (%s)\nplatform: test\n' "$5" "$6" > "$dir/stage/BUILD_INFO"
  fi
  if [[ "$8" == "1" ]]; then
    printf 'fixture library\n' > "$dir/stage/libsherpa-onnx-c-api.dylib"
    # GS-007: the build records the SHA-256 of every staged file.
    if [[ "$7" == "1" ]]; then
      printf 'sha256 libsherpa-onnx-c-api.dylib %s\n' "$(sha256_of "$dir/stage/libsherpa-onnx-c-api.dylib")" >> "$dir/stage/BUILD_INFO"
    fi
  fi
  echo "$dir"
}

# expect <label> pass|fail <needle-or-empty> <fixture-dir> [extra cmake -D args...]
expect() {
  local label="$1" want="$2" needle="$3" dir="$4" out rc
  shift 4
  out="$(cmake -DSTAGE_DIR="$dir/stage" -DREPO_ROOT="$dir/repo" "$@" -P "$CHECK" 2>&1)"
  rc=$?
  if [[ "$want" == "pass" && $rc -eq 0 && ( -z "$needle" || "$out" == *"$needle"* ) ]] || [[ "$want" == "fail" && $rc -ne 0 && "$out" == *"$needle"* ]]; then
    echo "ok   - $label"
  else
    echo "FAIL - $label (rc=$rc, want $want, needle '$needle')"
    printf '%s\n' "$out" | sed 's/^/       /'
    fail=1
  fi
}

expect "matching stage passes" pass "" \
  "$(make_fixture match "$PIN_TAG" "$PIN_COMMIT" 1.13.4 "$PIN_TAG" "$PIN_COMMIT" 1 1)"
tampered="$(make_fixture tampered "$PIN_TAG" "$PIN_COMMIT" 1.13.4 "$PIN_TAG" "$PIN_COMMIT" 1 1)"
printf 'changed after staging\n' >> "$tampered/stage/libsherpa-onnx-c-api.dylib"
expect "library changed after staging fails (GS-007)" fail "changed after staging" "$tampered"
unlisted="$(make_fixture unlisted "$PIN_TAG" "$PIN_COMMIT" 1.13.4 "$PIN_TAG" "$PIN_COMMIT" 1 1)"
printf 'extra\n' > "$unlisted/stage/libonnxruntime.so"
expect "unlisted staged file fails (GS-007)" fail "no sha256 line" "$unlisted"
crlf="$(make_fixture crlf "$PIN_TAG" "$PIN_COMMIT" 1.13.4 "$PIN_TAG" "$PIN_COMMIT" 1 1)"
sed -i.bak 's/$/\r/' "$crlf/stage/BUILD_INFO" "$crlf/repo/pubspec.lock" "$crlf/repo/scripts/sherpa-onnx.pin" && rm -f "$crlf"/stage/BUILD_INFO.bak "$crlf"/repo/*.bak "$crlf"/repo/scripts/*.bak
expect "CRLF files (Windows) pass" pass "" "$crlf"
expect "stage built from another commit fails" fail "stage commit" \
  "$(make_fixture commit "$PIN_TAG" "$PIN_COMMIT" 1.13.4 "$PIN_TAG" 0000000000000000000000000000000000000000 1 1)"
expect "pubspec.lock bumped without rebuild fails" fail "pubspec.lock sherpa_onnx 1.13.8" \
  "$(make_fixture lock "$PIN_TAG" "$PIN_COMMIT" 1.13.8 "$PIN_TAG" "$PIN_COMMIT" 1 1)"
expect "pin moved without rebuild fails" fail "stage tag" \
  "$(make_fixture pin v1.13.5 "$PIN_COMMIT" 1.13.5 "$PIN_TAG" "$PIN_COMMIT" 1 1)"
expect "missing BUILD_INFO fails" fail "BUILD_INFO" \
  "$(make_fixture noinfo "$PIN_TAG" "$PIN_COMMIT" 1.13.4 "$PIN_TAG" "$PIN_COMMIT" 0 1)"
expect "missing C API library fails" fail "C API library" \
  "$(make_fixture nolib "$PIN_TAG" "$PIN_COMMIT" 1.13.4 "$PIN_TAG" "$PIN_COMMIT" 1 0)"

# GS-013 (reference only): a repo pin mismatch warns, it does not fail. Release
# builds are not gated on it because the hash depends on the checkout path.
expect "matching reference pin passes (GS-013)" pass "" \
  "$(make_fixture pinok "$PIN_TAG" "$PIN_COMMIT" 1.13.4 "$PIN_TAG" "$PIN_COMMIT" 1 1 "$FIXTURE_LIB_SHA")"
expect "reference pin differing from the staged library warns, passes (GS-013)" pass "CMake Warning" \
  "$(make_fixture pinbad "$PIN_TAG" "$PIN_COMMIT" 1.13.4 "$PIN_TAG" "$PIN_COMMIT" 1 1 0000000000000000000000000000000000000000000000000000000000000000)"
expect "stage without any reference pin passes (GS-013)" pass "" \
  "$(make_fixture pinnone "$PIN_TAG" "$PIN_COMMIT" 1.13.4 "$PIN_TAG" "$PIN_COMMIT" 1 1)"

if [[ $fail -ne 0 ]]; then
  echo "check-sherpa-stage.test: FAILED" >&2
  exit 1
fi
echo "check-sherpa-stage.test: all cases passed."
