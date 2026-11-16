#!/usr/bin/env bash
#
# build-whisper-server-metal-local.sh — Metal whisper-server for macOS ARM64, built
# on the Mac. Replaces the former `build-metal-macos` job of
# .github/workflows/build-whisper-server.yml (GitHub macOS runners bill 10x).
#
# Usage:
#   scripts/build-whisper-server-metal-local.sh <whisper-tag> [release-tag] [--upload]
#     <whisper-tag>   whisper.cpp tag, e.g. v1.8.4
#     [release-tag]  whisper-server release tag (whisper-server-<tag>[-rN]) that the
#                    workflow created as a DRAFT; required with --upload
#     --upload       attach whisper-server-metal-arm64.zip to that draft, regenerate
#                    the manifest with all variants, and publish the release
#
# Without --upload the zip is only built into .build/whisper-server/.
# The workflow's publish-release job must create the release as a draft so that
# the upload is possible (GitHub immutable releases reject uploads after publish).

set -euo pipefail

REPO="${REPO:-whispaste/whispaste}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER_TAG=""
RELEASE_TAG=""
UPLOAD=0

die() { echo "ERROR: $*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --upload) UPLOAD=1 ;;
    -h|--help) sed -n '3,20p' "$0"; exit 0 ;;
    *)
      if [[ -z "$WHISPER_TAG" ]]; then WHISPER_TAG="$arg"
      elif [[ -z "$RELEASE_TAG" ]]; then RELEASE_TAG="$arg"
      else die "too many arguments"
      fi ;;
  esac
done

[[ -n "$WHISPER_TAG" ]] || die "usage: $0 <whisper-tag> [release-tag] [--upload]"
if [[ $UPLOAD -eq 1 ]]; then
  [[ -n "$RELEASE_TAG" ]] || die "--upload needs the whisper-server release tag"
  command -v gh >/dev/null 2>&1 || die "gh not found"
  is_draft="$(gh release view "$RELEASE_TAG" --repo "$REPO" --json isDraft -q .isDraft 2>/dev/null)" \
    || die "release $RELEASE_TAG not found (the workflow must create it as a draft first)"
  [[ "$is_draft" == "true" ]] || die "release $RELEASE_TAG is already published; refusing to upload"
fi

WORK="$REPO_ROOT/.build/whisper-server"
STAGE="$WORK/whisper-server-metal-arm64"
ZIP="$WORK/whisper-server-metal-arm64.zip"
rm -rf "$WORK"
mkdir -p "$WORK"

# Same steps as the former workflow job.
git clone --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp.git "$WORK/whisper.cpp"
cmake -S "$WORK/whisper.cpp" -B "$WORK/whisper.cpp/build" \
  -DGGML_METAL=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$WORK/whisper.cpp/build" --config Release -j "$(sysctl -n hw.ncpu)"

SERVER_BIN="$(find "$WORK/whisper.cpp/build" -type f \( -name whisper-server -o -name server \) ! -name '*.o' | head -1)"
[[ -n "$SERVER_BIN" ]] || die "whisper-server not found in build output"

mkdir -p "$STAGE"
cp "$SERVER_BIN" "$STAGE/whisper-server"
chmod +x "$STAGE/whisper-server"
cp "$(dirname "$SERVER_BIN")"/*.dylib "$STAGE/" 2>/dev/null || true
find "$WORK/whisper.cpp/build" -name '*.metallib' -exec cp {} "$STAGE/" \; 2>/dev/null || true

(cd "$STAGE" && zip -r -q "$ZIP" .)
echo "Built $ZIP"
ls -lh "$ZIP"

if [[ $UPLOAD -eq 0 ]]; then
  echo "No upload (run with --upload <whisper-tag> <release-tag> to publish)."
  exit 0
fi

# Manifest: all variants of the draft plus this Metal zip, the same generator as CI.
ASSETS="$WORK/assets"
mkdir -p "$ASSETS"
gh release download "$RELEASE_TAG" --repo "$REPO" --pattern '*.zip' --dir "$ASSETS" --clobber \
  || die "could not download the existing zips of $RELEASE_TAG"
cp "$ZIP" "$ASSETS/"
bash "$REPO_ROOT/scripts/generate-whisper-server-manifest.sh" "$RELEASE_TAG" "$WHISPER_TAG" "$ASSETS" \
  > "$ASSETS/whisper-server-manifest.json"

gh release upload "$RELEASE_TAG" "$ZIP" "$ASSETS/whisper-server-manifest.json" --repo "$REPO" --clobber
gh release edit "$RELEASE_TAG" --repo "$REPO" --draft=false
echo "Published $RELEASE_TAG with the Metal variant."
echo "NOTE: the manifest committed to main by the workflow does not contain the Metal entry; update it by hand if the download service reads it from main."
