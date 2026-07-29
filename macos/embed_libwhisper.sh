#!/usr/bin/env bash
# embed_libwhisper.sh — Xcode build phase that embeds the prebuilt `libwhisper`
# shared libraries into the app bundle's Frameworks/ and code-signs each with the
# SAME identity Xcode is using for this build pass (mirrors CocoaPods'
# `code_sign_if_enabled` in Pods-Runner-frameworks.sh).
#
# Because these dylibs are copied in and signed with ${EXPANDED_CODE_SIGN_IDENTITY}
# during the normal build, the outer app signature seals over them with matching
# team identity — so macOS Library Validation accepts them WITHOUT needing the
# `com.apple.security.cs.disable-library-validation` entitlement (Issue 11 AC4).
#
# Source dylibs are produced by scripts/build-libwhisper-macos.sh (SHA-256 pinned,
# @loader_path-relocatable). If they are absent the phase is a no-op with a
# warning, so a checkout that has not built libwhisper still compiles.
set -euo pipefail

STAGE_DIR="${SRCROOT}/../.build/libwhisper/macos"
DEST_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [[ ! -d "$STAGE_DIR" ]]; then
  echo "warning: libwhisper staging dir not found ($STAGE_DIR) — run scripts/build-libwhisper-macos.sh. Skipping embed."
  exit 0
fi

shopt -s nullglob
dylibs=("$STAGE_DIR"/*.dylib)
if [[ ${#dylibs[@]} -eq 0 ]]; then
  echo "warning: no dylibs in $STAGE_DIR — skipping libwhisper embed."
  exit 0
fi

mkdir -p "$DEST_DIR"

for src in "${dylibs[@]}"; do
  name="$(basename "$src")"
  dest="$DEST_DIR/$name"
  echo "Embedding $name → Frameworks/"
  # -c preserves symlinks-as-files; we stage real files so this is a plain copy.
  ditto "$src" "$dest"

  # Sign with the build's identity, unless signing is disabled (e.g. some CI
  # archive steps). Ad-hoc ("-") for local/dev builds is fine and still proves
  # the same-identity nested-signing structure.
  if [[ "${CODE_SIGNING_REQUIRED:-}" != "NO" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
      ${OTHER_CODE_SIGN_FLAGS:-} \
      --timestamp=none "$dest"
  fi
done

echo "libwhisper embed complete (${#dylibs[@]} dylibs)."

# Bundle the Silero-VAD model alongside libwhisper (see
# assets/models/vad/NOTICE.md) — a fixed, tiny (<1MB) data file, not a
# dylib, so it isn't in $STAGE_DIR/*.dylib above and doesn't need signing.
VAD_MODEL_SRC="${SRCROOT}/../assets/models/vad/ggml-silero-v5.1.2.bin"
if [[ -f "$VAD_MODEL_SRC" ]]; then
  ditto "$VAD_MODEL_SRC" "$DEST_DIR/ggml-silero-v5.1.2.bin"
  echo "Embedded ggml-silero-v5.1.2.bin (VAD model) → Frameworks/"
else
  echo "warning: VAD model not found ($VAD_MODEL_SRC) — VAD stays unavailable at runtime."
fi
