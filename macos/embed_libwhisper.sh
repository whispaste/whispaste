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

REPO_ROOT="${SRCROOT}/.."
STAGE_DIR="${REPO_ROOT}/.build/libwhisper/macos"
DEST_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

# Self-heal: a fresh worktree checkout (git worktree, not a full clone) never
# inherits .build/ — it's gitignored, per-checkout build cache. Rather than
# silently skipping (which used to leave transcription broken with no signal
# until someone noticed at runtime), build it now if the pinned whisper.cpp
# source is already present. Only skip-with-warning if even that is missing,
# so CI/lint-only checkouts without the source tree still compile.
if [[ ! -d "$STAGE_DIR" ]]; then
  echo "note: libwhisper staging dir not found ($STAGE_DIR) — attempting to build it now."
  # Invoked via `bash` (not exec'd directly) so a lost +x bit on the script
  # (silently reverted to it once — see git history of this file, mode 100644
  # committed accidentally) can never again turn a real build failure into a
  # silent "skip embed" — the real MAS archive that shipped that way had NO
  # on-device Whisper engine at all, with the build still reporting success.
  if ! bash "${REPO_ROOT}/scripts/build-libwhisper-macos.sh"; then
    echo "warning: libwhisper auto-build failed — see log above. Skipping embed; run scripts/build-libwhisper-macos.sh manually."
    exit 0
  fi
fi

if [[ ! -d "$STAGE_DIR" ]]; then
  echo "warning: libwhisper staging dir still not found after auto-build attempt — skipping embed."
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
# dylib, so it isn't in $STAGE_DIR/*.dylib above. It still needs a signature:
# the outer app's whole-bundle CodeSign step scans every item under
# Frameworks/ as a nested code object, and fails the build ("code object is
# not signed at all") on an unsigned one — `codesign` happily signs a flat
# non-Mach-O file (Format=generic), so sign it exactly like the dylibs above.
VAD_MODEL_SRC="${SRCROOT}/../assets/models/vad/ggml-silero-v5.1.2.bin"
if [[ -f "$VAD_MODEL_SRC" ]]; then
  VAD_MODEL_DEST="$DEST_DIR/ggml-silero-v5.1.2.bin"
  ditto "$VAD_MODEL_SRC" "$VAD_MODEL_DEST"
  if [[ "${CODE_SIGNING_REQUIRED:-}" != "NO" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
      ${OTHER_CODE_SIGN_FLAGS:-} \
      --timestamp=none "$VAD_MODEL_DEST"
  fi
  echo "Embedded ggml-silero-v5.1.2.bin (VAD model) → Frameworks/"
else
  echo "warning: VAD model not found ($VAD_MODEL_SRC) — VAD stays unavailable at runtime."
fi
