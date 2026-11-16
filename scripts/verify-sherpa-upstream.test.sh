#!/usr/bin/env bash
# Tests for verify-sherpa-upstream.sh with a synthetic repo root, pin and pub cache.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/verify-sherpa-upstream.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
failures=0
sum() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
expect() { # name want-exit cmd...
  local name="$1" want="$2"; shift 2
  "$@" >"$T/out" 2>&1; local rc=$?
  if [[ $rc -eq $want ]]; then echo "ok   $name"; else echo "FAIL $name (exit $rc, want $want)"; sed 's/^/    /' "$T/out"; failures=$((failures + 1)); fi
}

mkdir -p "$T/root" "$T/cache/hosted/pub.dev/sherpa_onnx_linux-2.0.1/linux/x64" "$T/bundle/lib"
printf 'capi' >"$T/cache/hosted/pub.dev/sherpa_onnx_linux-2.0.1/linux/x64/libsherpa-onnx-c-api.so"
printf 'ort' >"$T/cache/hosted/pub.dev/sherpa_onnx_linux-2.0.1/linux/x64/libonnxruntime.so"
A="$(sum "$T/cache/hosted/pub.dev/sherpa_onnx_linux-2.0.1/linux/x64/libsherpa-onnx-c-api.so")"
O="$(sum "$T/cache/hosted/pub.dev/sherpa_onnx_linux-2.0.1/linux/x64/libonnxruntime.so")"
ARCH="$(printf '%064d' 7)"
write_pin() {
  cat >"$T/pin" <<EOP
UPSTREAM_VERSION=2.0.1
UPSTREAM_ARCHIVE_SHA256_LINUX=$ARCH
UPSTREAM_FILE=linux|linux/x64/libsherpa-onnx-c-api.so|$1
UPSTREAM_FILE=linux|linux/x64/libonnxruntime.so|$O
EOP
}
write_lock() {
  cat >"$T/root/pubspec.lock" <<EOL
packages:
  sherpa_onnx_linux:
    dependency: transitive
    description:
      name: sherpa_onnx_linux
      sha256: "$1"
    source: hosted
    version: "$2"
  other:
    version: "9"
EOL
}
run() { SHERPA_UPSTREAM_ROOT="$T/root" SHERPA_UPSTREAM_PIN="$T/pin" bash "$SCRIPT" linux --pub-cache "$T/cache" "$@"; }

write_pin "$A"; write_lock "$ARCH" 2.0.1
expect "matching pin passes" 0 run
write_pin "$(printf '%064d' 1)"
expect "wrong file hash fails" 1 run
write_pin "$A"; write_lock "$(printf '%064d' 2)" 2.0.1
expect "wrong lock archive hash fails" 1 run
write_lock "$ARCH" 2.0.0
expect "wrong lock version fails" 1 run
write_lock "$ARCH" 2.0.1; rm "$T/cache/hosted/pub.dev/sherpa_onnx_linux-2.0.1/linux/x64/libonnxruntime.so"
expect "missing file fails" 1 run
printf 'ort' >"$T/cache/hosted/pub.dev/sherpa_onnx_linux-2.0.1/linux/x64/libonnxruntime.so"
cp "$T/cache/hosted/pub.dev/sherpa_onnx_linux-2.0.1/linux/x64/"*.so "$T/bundle/lib/"
expect "identical bundle passes" 0 run --bundle "$T/bundle"
printf 'x' >>"$T/bundle/lib/libonnxruntime.so"
expect "modified bundle file fails" 1 run --bundle "$T/bundle"
rm "$T/bundle/lib/libonnxruntime.so"
expect "bundle without a pinned file fails" 1 run --bundle "$T/bundle"
expect "unknown platform fails" 1 bash "$SCRIPT" plan9

# The committed pin and lock must agree for every platform (real repo files, no cache needed beyond lock).
for p in linux windows macos; do
  expect "real lock matches pin ($p)" 0 bash -c "bash '$SCRIPT' $p >/dev/null 2>&1 || bash '$SCRIPT' $p 2>&1 | grep -q 'not in the pub cache'"
done
[[ $failures -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "all passed"
