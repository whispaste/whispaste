#!/usr/bin/env bash
# embed_libllama.sh — Xcode build phase that embeds the prebuilt `libllama` +
# `libsmartmode_shim` shared libraries (Smart Mode) into the app bundle's
# Frameworks/ and code-signs each with the SAME identity Xcode is using for
# this build pass — the exact same pattern as embed_libwhisper.sh, just
# against a separate staging dir. Because these two engines' dylibs are fully
# namespaced apart (see build-libllama-macos.sh's ggml `-llama` suffix
# rename), copying both sets into the same Frameworks/ directory is safe: no
# install-name collides between libwhisper's and libllama's own ggml copies.
#
# Runs unconditionally for every build of the "Runner" target (Debug/Release/
# MAS) — Smart Mode ships in the real app now, the same way libwhisper does.
# Signed with ${EXPANDED_CODE_SIGN_IDENTITY} exactly like embed_libwhisper.sh,
# so the outer app signature seals over these dylibs with matching team
# identity and macOS Library Validation accepts them under the sandboxed
# "Runner (MAS)" build too, without needing the
# `com.apple.security.cs.disable-library-validation` entitlement (verified via
# main_smart_mode_debug.dart's "Runner (MAS)" prototype build).
#
# Source dylibs are produced by scripts/build-libllama-macos.sh +
# scripts/build-smartmode-shim-macos.sh (SHA-256 pinned, @loader_path-
# relocatable). Self-heals like embed_libwhisper.sh: a fresh checkout that
# has not built libllama yet gets it built here, on first build, rather than
# silently shipping without Smart Mode until someone notices at runtime.
set -euo pipefail

REPO_ROOT="${SRCROOT}/.."
STAGE_DIR="${REPO_ROOT}/.build/libllama/macos"
DEST_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [[ ! -d "$STAGE_DIR" ]]; then
  echo "note: libllama staging dir not found ($STAGE_DIR) — attempting to build it now."
  # bash-invoked (not exec'd) for the same reason as embed_libwhisper.sh: a
  # lost +x bit must never silently degrade to "skip embed" without at least
  # running the script.
  if ! bash "${REPO_ROOT}/scripts/build-libllama-macos.sh" || ! bash "${REPO_ROOT}/scripts/build-smartmode-shim-macos.sh"; then
    echo "warning: libllama/smartmode-shim auto-build failed — see log above. Skipping embed; run scripts/build-libllama-macos.sh && scripts/build-smartmode-shim-macos.sh manually. Smart Mode will be unavailable in this build."
    exit 0
  fi
fi

if [[ ! -d "$STAGE_DIR" ]]; then
  echo "warning: libllama staging dir still not found after auto-build attempt — skipping embed. Smart Mode will be unavailable in this build."
  exit 0
fi

# The shim is WhisPaste's own code and changes independently of the pinned
# libllama build: an already-staged dylib older than its source would ship
# without newly added exports (e.g. smart_mode_load/generate/unload), and
# the Dart side would fail its symbol lookup at runtime. Rebuild just the
# shim (fast, single translation unit) whenever its source is newer.
SHIM_DYLIB="$STAGE_DIR/libsmartmode_shim.dylib"
SHIM_SRC_DIR="${REPO_ROOT}/native/smart_mode"
if [[ ! -f "$SHIM_DYLIB" || "$SHIM_SRC_DIR/smart_mode_shim.cpp" -nt "$SHIM_DYLIB" || "$SHIM_SRC_DIR/smart_mode_shim.h" -nt "$SHIM_DYLIB" ]]; then
  echo "note: libsmartmode_shim missing or older than its source — rebuilding it."
  if ! bash "${REPO_ROOT}/scripts/build-smartmode-shim-macos.sh"; then
    echo "warning: smartmode-shim rebuild failed — see log above. Smart Mode may be unavailable in this build."
  fi
fi

shopt -s nullglob
dylibs=("$STAGE_DIR"/*.dylib)
if [[ ${#dylibs[@]} -eq 0 ]]; then
  echo "warning: no dylibs in $STAGE_DIR — skipping libllama embed."
  exit 0
fi

mkdir -p "$DEST_DIR"

for src in "${dylibs[@]}"; do
  name="$(basename "$src")"
  dest="$DEST_DIR/$name"
  echo "Embedding $name → Frameworks/"
  ditto "$src" "$dest"

  if [[ "${CODE_SIGNING_REQUIRED:-}" != "NO" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
      ${OTHER_CODE_SIGN_FLAGS:-} \
      --timestamp=none "$dest"
  fi
done

echo "libllama embed complete (${#dylibs[@]} dylibs)."
