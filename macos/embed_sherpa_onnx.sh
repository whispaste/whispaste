#!/usr/bin/env bash
# embed_sherpa_onnx.sh — Xcode build phase that replaces the sherpa_onnx pub
# package's prebuilt C API (which statically contains espeak-ng, GPL-3.0) with
# WhisPaste's own build from the pinned tag with TTS=OFF, in the app bundle's
# Frameworks/, and code-signs it with the SAME identity Xcode is using.
#
# It runs after "[CP] Embed Pods Frameworks" (which copies the pub originals)
# and before the final app signature, so the replacement is what gets sealed.
# Same pattern as embed_libllama.sh / embed_libwhisper.sh.
#
# Source: .build/sherpa-onnx/macos, produced by scripts/build-sherpa-onnx.sh
# macos (universal arm64 + x86_64). Missing staging = self-heal by building it
# (about 6 minutes, once). A failed build is an error in every configuration:
# shipping the pub original would silently re-introduce espeak-ng.
set -euo pipefail

REPO_ROOT="${SRCROOT}/.."
STAGE_DIR="${REPO_ROOT}/.build/sherpa-onnx/macos"
DEST_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [[ ! -f "$STAGE_DIR/libsherpa-onnx-c-api.dylib" ]]; then
  # CI debug builds (ci.yml, on every push) must not pay a 6-minute build, and
  # a debug bundle is never released. Release/profile builds and local builds
  # must have the TTS-free library; CI release jobs stage it before building.
  if [[ "${CI:-}" == "true" ]]; then
    if [[ "${CONFIGURATION:-}" == "Debug" ]]; then
      echo "warning: sherpa-onnx TTS-free staging missing; keeping the pub original in this CI debug bundle (never released)."
      exit 0
    fi
    echo "error: sherpa-onnx TTS-free staging missing in CI ($STAGE_DIR). Stage it with scripts/build-sherpa-onnx.sh macos first." >&2
    exit 1
  fi
  echo "note: sherpa-onnx staging missing ($STAGE_DIR) — building it now (about 6 min, once)."
  if ! bash "${REPO_ROOT}/scripts/build-sherpa-onnx.sh" macos; then
    echo "error: sherpa-onnx TTS-free build failed — see log above. Refusing to embed the pub original (contains espeak-ng)." >&2
    exit 1
  fi
fi

# A stage built from another pin, or before a sherpa_onnx bump in pubspec.lock,
# must not be embedded: the ABI would not match the Dart bindings. Xcode's PATH
# lacks Homebrew, so look there too.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake not found; it is needed to verify the sherpa-onnx stage." >&2
  exit 1
fi
if ! cmake -DSTAGE_DIR="$STAGE_DIR" -DREPO_ROOT="$REPO_ROOT" -P "${REPO_ROOT}/scripts/check-sherpa-stage.cmake"; then
  echo "error: sherpa-onnx stage in $STAGE_DIR does not match the pins. Rebuild it: bash scripts/build-sherpa-onnx.sh macos" >&2
  exit 1
fi

shopt -s nullglob
libs=("$STAGE_DIR"/libsherpa-onnx-c-api.dylib "$STAGE_DIR"/libonnxruntime*.dylib)
shopt -u nullglob
if [[ ${#libs[@]} -eq 0 ]]; then
  echo "error: no sherpa-onnx dylibs in $STAGE_DIR." >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

for src in "${libs[@]}"; do
  name="$(basename "$src")"
  dest="$DEST_DIR/$name"
  echo "Embedding $name (sherpa-onnx, TTS=OFF) → Frameworks/"
  ditto "$src" "$dest"

  if [[ "${CODE_SIGNING_REQUIRED:-}" != "NO" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
    # OTHER_CODE_SIGN_FLAGS is a word list on purpose (same as embed_libllama.sh).
    # shellcheck disable=SC2086
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
      ${OTHER_CODE_SIGN_FLAGS:-} \
      --timestamp=none "$dest"
  fi
done

# Belt and braces: the copied set must never carry espeak-ng.
bash "${REPO_ROOT}/scripts/check-no-espeak.sh" "${libs[@]}"

echo "sherpa-onnx embed complete (${#libs[@]} dylibs)."
