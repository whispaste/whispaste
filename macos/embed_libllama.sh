#!/usr/bin/env bash
# embed_libllama.sh — Xcode build phase that embeds the prebuilt `libllama` +
# `libsmartmode_shim` shared libraries (Smart-Mode-v2 prototype) into the app
# bundle's Frameworks/ and code-signs each with the SAME identity Xcode is
# using for this build pass — the exact same pattern as embed_libwhisper.sh,
# just against a separate staging dir. Because these two engines' dylibs are
# fully namespaced apart (see build-libllama-macos.sh's ggml `-llama` suffix
# rename), copying both sets into the same Frameworks/ directory is safe: no
# install-name collides between libwhisper's and libllama's own ggml copies.
#
# Source dylibs are produced by scripts/build-libllama-macos.sh +
# scripts/build-smartmode-shim-macos.sh (SHA-256 pinned, @loader_path-
# relocatable). If they are absent the phase is a no-op with a warning, so a
# checkout that has not built libllama still compiles.
set -euo pipefail

STAGE_DIR="${SRCROOT}/../.build/libllama/macos"
DEST_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [[ ! -d "$STAGE_DIR" ]]; then
  echo "warning: libllama staging dir not found ($STAGE_DIR) — run scripts/build-libllama-macos.sh && scripts/build-smartmode-shim-macos.sh. Skipping embed."
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
