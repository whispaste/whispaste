# shellcheck shell=bash
# sherpa-stage-libs.sh — sourced by build-sherpa-onnx.sh (and its test).
# Bash 3.2 compatible (macOS system bash).
#
# sherpa_stage_libs <macos|linux> <build-dir>
#   Prints, one per line, the shared libraries to stage from a sherpa-onnx
#   build: the C API library and onnxruntime, in this platform's format only
#   (.dylib on macOS, .so* on Linux). Fails with a message on stderr when
#   either is missing, so a broken build never stages a partial set.

sherpa_stage_libs() {
  local platform="$1" build="$2"
  local capi_glob ort_glob
  case "$platform" in
    macos) capi_glob="libsherpa-onnx-c-api.dylib"; ort_glob="libonnxruntime*.dylib" ;;
    linux) capi_glob="libsherpa-onnx-c-api.so*"; ort_glob="libonnxruntime.so*" ;;
    *) echo "error: no staging rule for platform '$platform'" >&2; return 1 ;;
  esac

  local had_nullglob=0
  shopt -q nullglob && had_nullglob=1
  shopt -s nullglob
  # onnxruntime is fetched by sherpa into _deps/onnxruntime-src/lib, not lib/.
  # shellcheck disable=SC2206  # the globs are meant to expand here
  local capi=("$build"/lib/$capi_glob)
  # shellcheck disable=SC2206
  local ort=("$build"/_deps/onnxruntime-src/lib/$ort_glob)
  [[ $had_nullglob -eq 1 ]] || shopt -u nullglob

  if [[ ${#capi[@]} -eq 0 ]]; then
    echo "error: no $capi_glob under $build/lib" >&2
    return 1
  fi
  if [[ ${#ort[@]} -eq 0 ]]; then
    echo "error: no $ort_glob (onnxruntime) under $build/_deps/onnxruntime-src/lib" >&2
    return 1
  fi
  printf '%s\n' "${capi[@]}" "${ort[@]}"
}
