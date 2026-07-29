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
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ OPT-IN ONLY. This phase lives on the SHARED "Runner" target, so it runs   │
# │ for EVERY build of the real app (Debug/Release/MAS, flutter/xcodebuild/   │
# │ fastlane). Smart-Mode-v2 is an unshipped prototype — its dylibs must      │
# │ NEVER land in the production app. Therefore this script is a hard no-op   │
# │ unless the builder explicitly opts in with WHISPASTE_SMART_MODE_PROTOTYPE │
# │ =1. A normal build touches nothing in Frameworks/ and does not grow the   │
# │ bundle by a single byte. Only the dedicated prototype build sets the var: │
# │                                                                            │
# │   WHISPASTE_SMART_MODE_PROTOTYPE=1 xcodebuild \                            │
# │     -workspace macos/Runner.xcworkspace -scheme "Runner (MAS)" \          │
# │     -configuration MAS build \                                            │
# │     PRODUCT_BUNDLE_IDENTIFIER=de.whispaste.smartmode.debug                │
# └──────────────────────────────────────────────────────────────────────────┘
#
# Source dylibs are produced by scripts/build-libllama-macos.sh +
# scripts/build-smartmode-shim-macos.sh (SHA-256 pinned, @loader_path-
# relocatable). If they are absent the phase is a no-op with a warning, so a
# checkout that has not built libllama still compiles.
set -euo pipefail

# --- Opt-in gate (see banner above). Default = no-op, protects the real app. --
if [[ "${WHISPASTE_SMART_MODE_PROTOTYPE:-}" != "1" ]]; then
  echo "note: [WP] Embed & Sign libllama skipped (Smart-Mode-v2 prototype not opted in; set WHISPASTE_SMART_MODE_PROTOTYPE=1 to embed). This is the normal, expected path for the real app."
  exit 0
fi

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
