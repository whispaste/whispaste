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
  if ! "${REPO_ROOT}/scripts/build-libllama-macos.sh" || ! "${REPO_ROOT}/scripts/build-smartmode-shim-macos.sh"; then
    echo "warning: libllama/smartmode-shim auto-build failed — see log above. Skipping embed; run scripts/build-libllama-macos.sh && scripts/build-smartmode-shim-macos.sh manually. Smart Mode will be unavailable in this build."
    exit 0
  fi
fi

if [[ ! -d "$STAGE_DIR" ]]; then
  echo "warning: libllama staging dir still not found after auto-build attempt — skipping embed. Smart Mode will be unavailable in this build."
  exit 0
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
