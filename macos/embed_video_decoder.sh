#!/usr/bin/env bash
# Xcode build phase: a local helper with no startup work or network support.
set -euo pipefail
ROOT="${SRCROOT}/.."
python3 "${ROOT}/scripts/build-video-decoder.py" --platform macos
STAGE="${ROOT}/.build/video-decoder/macos"
DEST="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
mkdir -p "$DEST"
cp "$STAGE/ffmpeg" "$DEST/"
SOURCES="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/video-decoder"
mkdir -p "$SOURCES"
cp "$STAGE/COPYING.LGPLv2.1" "$STAGE/SOURCE.txt" \
  "$STAGE/build-video-decoder.py" "$STAGE"/*.tar.xz "$SOURCES/"
# A Mac App Store child inherits the application's sandbox. Signing the
# helper separately is required before Xcode seals the outer app.
ARGS=(--force --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}")
if [[ "${CODE_SIGN_ENTITLEMENTS:-}" == *AppStore* ]]; then
  ARGS+=(--entitlements "${SRCROOT}/Runner/VideoDecoder.entitlements")
fi
/usr/bin/codesign "${ARGS[@]}" "$DEST/ffmpeg"
