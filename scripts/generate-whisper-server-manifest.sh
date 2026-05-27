#!/usr/bin/env bash
# Builds assets/whisper-server-manifest.json from:
#   - WHISPER_SERVER_TAG   (e.g. whisper-server-v1.8.4.1)   — produced by build-whisper-server.yml
#   - WHISPER_CPP_RELEASE  (e.g. v1.8.4)                     — upstream tag that supplied CUDA/CPU
#
# Uses `gh api` so the call runs against the workflow's GITHUB_TOKEN
# (5k/h authenticated quota) rather than the 60/h unauthenticated one.
# The script downloads asset metadata only — no archive bytes.
#
# Outputs the manifest to stdout. Caller redirects into
# assets/whisper-server-manifest.json and commits.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <whisper-server-tag> <whisper-cpp-release>" >&2
  echo "  e.g. $0 whisper-server-v1.8.4.1 v1.8.4" >&2
  exit 2
fi

WHISPER_SERVER_TAG="$1"
WHISPER_CPP_RELEASE="$2"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Asset name → (platform, arch, backend) projection. Tuples in this map
# must stay in sync with the lookup keys used by WhisperBinarySelector.
#
# WhisPaste-built assets (one per CI matrix entry).
WHISPASTE_ASSETS=$(gh api \
  "/repos/whispaste/whispaste/releases/tags/${WHISPER_SERVER_TAG}" \
  --jq '.assets // [] | map({name: .name, size_bytes: .size, url: .browser_download_url})')

# Upstream whisper.cpp assets.
UPSTREAM_ASSETS=$(gh api \
  "/repos/ggml-org/whisper.cpp/releases/tags/${WHISPER_CPP_RELEASE}" \
  --jq '.assets // [] | map({name: .name, size_bytes: .size, url: .browser_download_url})')

# Classify each asset name into platform/arch/backend. The naming
# conventions are stable enough across releases that a substring scan
# works; if upstream renames anything, this script fails loudly and the
# CI run aborts before the manifest gets committed.
classify() {
  local name="$1"
  local source="$2"
  local lower
  lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')

  local platform=""
  local arch=""
  local backend=""

  case "$lower" in
    *metal*arm64*) platform=macos;  arch=arm64; backend=metal   ;;
    *vulkan*x64*)  platform=windows; arch=x64;  backend=vulkan  ;;
    *cublas-12*x64*) platform=windows; arch=x64; backend=cuda12 ;;
    *cublas-11*x64*) ;; # legacy CUDA 11 — skip, app expects cuda12
    *blas-bin*x64*)  platform=windows; arch=x64; backend=cpu    ;;
    *blas-bin*win32*) ;; # 32-bit — skip
    *bin-x64*) ;;        # plain CPU build — skip, blas-bin variant wins
    *bin-win32*) ;;
    *xcframework*) ;;  # iOS, not desktop
    whispercpp.jar*) ;; # Java/Android, not desktop
    *) return 1 ;;     # unrecognised name → caller decides to fail
  esac

  if [[ -z "$platform" ]]; then
    return 1
  fi
  printf '%s\t%s\t%s\t%s\n' "$platform" "$arch" "$backend" "$source"
}

# Render the binaries array. Each line of the input arrives as
# "<source>\t<name>\t<size>\t<url>".
{
  echo "$WHISPASTE_ASSETS" | jq -r '.[] | "whispaste\t\(.name)\t\(.size_bytes)\t\(.url)"'
  echo "$UPSTREAM_ASSETS"  | jq -r '.[] | "upstream\t\(.name)\t\(.size_bytes)\t\(.url)"'
} | while IFS=$'\t' read -r source name size url; do
  if classified=$(classify "$name" "$source"); then
    IFS=$'\t' read -r platform arch backend _ <<< "$classified"
    jq -n \
      --arg platform "$platform" \
      --arg arch "$arch" \
      --arg backend "$backend" \
      --arg url "$url" \
      --argjson size "$size" \
      --arg source "$source" \
      '{platform: $platform, arch: $arch, backend: $backend, url: $url, size_bytes: $size, source: $source}'
  fi
done | jq -s --arg tag "$WHISPER_SERVER_TAG" \
              --arg cpp "$WHISPER_CPP_RELEASE" \
              --arg ts  "$GENERATED_AT" '
{
  schema_version: 1,
  whisper_server_tag: $tag,
  whisper_cpp_release: $cpp,
  generated_at: $ts,
  binaries: .
}'
