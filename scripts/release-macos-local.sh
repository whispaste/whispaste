#!/usr/bin/env bash
#
# release-macos-local.sh — macOS release built and published on the Mac.
#
# GitHub-hosted macOS runners bill at 10x minutes, so the former `build-macos`,
# `publish-appcast` and `promote-beta-to-stable` jobs of
# .github/workflows/release.yml run here instead. The steps, helper scripts and
# artifact names are the same as in the workflow (see the step comments below).
#
# Exactly one mode is required; a bare call refuses:
#   --dry-run <tag>               Build, sign and smoke-test locally. No
#                                 notarization, no upload, no appcast.
#   --upload <tag>                Full release: Sentry dSYM upload, notarization,
#                                 staple, upload of the macOS assets to the DRAFT
#                                 release that the tag run created (create-release),
#                                 signed appcast, publish.
#   --promote <beta-tag> <ver>    Promote a validated beta to stable without a
#                                 rebuild (verbatim copy, same EdDSA signature).
#
# Tag form: vX.Y.Z or vX.Y.Z-beta.N (the `v` is optional).
#
# Env, read from ~/.config/whispaste/release.env (or $WHISPASTE_RELEASE_ENV) and/or
# exported in the shell. Values are never printed:
#   SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY,
#   WHISPASTE_MATOMO_URL, WHISPASTE_MATOMO_SITE_ID   build-time values (required)
#   ASC_KEY_ID, ASC_ISSUER_ID                        App Store Connect key (--upload)
#   APPLE_TEAM_ID                                    default Q7V3X27S2U
#   SENTRY_AUTH_TOKEN                                optional, dSYM upload
#   SPARKLE_SIGNING_KEY                              44-char seed (--upload/--promote);
#                                                    falls back to
#                                                    ~/.config/whispaste-sparkle/sparkle_private.pem
#   REPO                                             default whispaste/whispaste
#
# Signing uses the Developer ID identity from the login keychain. This script
# never calls `security` and never overrides HOME.

set -euo pipefail

REPO="${REPO:-whispaste/whispaste}"
SIGN_IDENTITY="Developer ID Application: Silvio Lindstedt (Q7V3X27S2U)"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-Q7V3X27S2U}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${WHISPASTE_RELEASE_ENV:-$HOME/.config/whispaste/release.env}"
SPARKLE_KEY_FILE="$HOME/.config/whispaste-sparkle/sparkle_private.pem"
ARTIFACT_DIR="$REPO_ROOT/release-artifacts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MODE=""
ARGS=()

die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }
step() { echo; echo "── $*"; }

usage() {
  sed -n '3,33p' "$0" | sed 's/^# \{0,1\}//'
}

set_mode() {
  [[ -z "$MODE" ]] || die "only one mode allowed (already: --$MODE)"
  MODE="$1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) set_mode dry-run; shift ;;
    --upload) set_mode upload; shift ;;
    --promote) set_mode promote; shift ;;
    -h|--help) usage; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if [[ -z "$MODE" ]]; then
  usage >&2
  die "no mode given: use --dry-run <tag>, --upload <tag> or --promote <beta-tag> <version>"
fi

# Build-time values and signing/notarization settings. Sourced, never printed.
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

clean() { printf '%s' "$1" | tr -d '\r\n'; }

require_tools() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || die "required tool not found: $t"
  done
}

require_var() {
  [[ -n "${!1:-}" ]] || die "$1 is not set (see the header of this script)"
}

load_sparkle_key() {
  local key="${SPARKLE_SIGNING_KEY:-}"
  if [[ -z "$key" && -f "$SPARKLE_KEY_FILE" ]]; then
    key="$(tr -d '\r\n' < "$SPARKLE_KEY_FILE")"
  fi
  [[ ${#key} -eq 44 ]] || die "SPARKLE_SIGNING_KEY missing or not the 44-char seed (checked env and $SPARKLE_KEY_FILE; contents not printed)"
  printf '%s' "$key"
}

# Stamp = hash of the inputs that pin a native build (same idea as the CI cache keys).
hash_paths() {
  find "$@" -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1
}

stamp_matches() {
  [[ -f "$1" && "$(cat "$1")" == "$2" ]]
}

# ── Native libraries (CI steps "Build + stage …" and their cache keys) ───────
build_native() {
  local key
  cd "$REPO_ROOT"

  local whisper_tag
  whisper_tag="$(sed -n 's/^WHISPER_TAG=//p' scripts/whisper-cpp.pin)"
  step "libwhisper (pinned whisper.cpp $whisper_tag)"
  key="$(hash_paths scripts/build-libwhisper-macos.sh scripts/whisper-cpp.pin native/ffi_guard)"
  if ! stamp_matches .build/libwhisper/macos.stamp "$key"; then
    mkdir -p .build/deps/whisper.cpp .build/libwhisper
    [[ -d ".build/deps/whisper.cpp/$whisper_tag" ]] || git clone --depth 1 --branch "$whisper_tag" \
      https://github.com/ggml-org/whisper.cpp ".build/deps/whisper.cpp/$whisper_tag"
    bash scripts/build-libwhisper-macos.sh
    printf '%s' "$key" > .build/libwhisper/macos.stamp
  fi
  bash scripts/check-libwhisper-guard.sh .build/libwhisper/macos

  local llama_tag
  llama_tag="$(sed -n 's/^LLAMA_TAG=//p' scripts/llama-cpp.pin)"
  step "libllama (pinned llama.cpp $llama_tag) + smartmode shim"
  key="$(hash_paths scripts/build-libllama-macos.sh scripts/build-smartmode-shim-macos.sh scripts/llama-cpp.pin native/smart_mode)"
  if ! stamp_matches .build/libllama/macos.stamp "$key"; then
    mkdir -p .build/deps/llama.cpp .build/libllama
    [[ -d ".build/deps/llama.cpp/$llama_tag" ]] || git clone --depth 1 --branch "$llama_tag" \
      https://github.com/ggml-org/llama.cpp ".build/deps/llama.cpp/$llama_tag"
    bash scripts/build-libllama-macos.sh
    bash scripts/build-smartmode-shim-macos.sh
    printf '%s' "$key" > .build/libllama/macos.stamp
  fi

  step "sherpa-onnx v2.0.1 without TTS"
  key="$(hash_paths scripts/build-sherpa-onnx.sh scripts/sherpa-stage-libs.sh \
    scripts/fetch-onnxruntime.sh scripts/check-no-espeak.sh macos/embed_sherpa_onnx.sh \
    scripts/sherpa-onnx.pin scripts/check-sherpa-stage.cmake)"
  if ! stamp_matches .build/sherpa-onnx/macos.stamp "$key"; then
    mkdir -p .build/sherpa-onnx
    bash scripts/build-sherpa-onnx.sh macos
    printf '%s' "$key" > .build/sherpa-onnx/macos.stamp
  fi
  # Runs on every call: a stage built from another pin must fail here.
  cmake -DSTAGE_DIR=.build/sherpa-onnx/macos -DREPO_ROOT=. -P scripts/check-sherpa-stage.cmake
}

# ── Flutter release build (CI step "Build macOS release") ───────────────────
build_app() {
  cd "$REPO_ROOT"
  step "flutter build macos --release ($VERSION)"
  flutter pub get
  flutter build macos --release --no-tree-shake-icons \
    "--dart-define=SUPABASE_URL=$(clean "$SUPABASE_URL")" \
    "--dart-define=SUPABASE_PUBLISHABLE_KEY=$(clean "$SUPABASE_PUBLISHABLE_KEY")" \
    "--dart-define=WHISPASTE_MATOMO_URL=$(clean "$WHISPASTE_MATOMO_URL")" \
    "--dart-define=WHISPASTE_MATOMO_SITE_ID=$(clean "$WHISPASTE_MATOMO_SITE_ID")" \
    "--dart-define=APP_VERSION=$VERSION"

  APP="$REPO_ROOT/build/macos/Build/Products/Release/WhisPaste.app"
  [[ -d "$APP" ]] || die "app bundle not found: $APP"

  step "embedded-library guards"
  [[ -f "$APP/Contents/Frameworks/libwhisper.dylib" ]] || die "libwhisper.dylib missing from the bundle"
  [[ -f "$APP/Contents/Frameworks/libsmartmode_shim.dylib" ]] || die "libsmartmode_shim.dylib missing from the bundle"
  bash scripts/check-no-espeak.sh "$APP"
  # Same build, not same bytes: embed_sherpa_onnx.sh re-signs the copy whenever
  # Xcode has a signing identity (always on the Mac, never on the old runner),
  # so compare the linker's per-arch LC_UUIDs instead of the files.
  local staged bundled
  staged="$(macho_uuids .build/sherpa-onnx/macos/libsherpa-onnx-c-api.dylib)"
  bundled="$(macho_uuids "$APP/Contents/Frameworks/libsherpa-onnx-c-api.dylib")"
  [[ -n "$staged" && "$staged" == "$bundled" ]] \
    || die "bundled libsherpa-onnx-c-api.dylib is not the TTS-free staged build"
}

macho_uuids() {
  otool -l "$1" | awk '$1 == "uuid" { print $2 }' | LC_ALL=C sort
}

upload_dsym() {
  step "Sentry dSYM upload"
  if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
    warn "SENTRY_AUTH_TOKEN not set: dSYM upload skipped"
    return 0
  fi
  (cd "$REPO_ROOT" && SENTRY_RELEASE="whispaste@$VERSION" dart run sentry_dart_plugin)
}

# ── Signing (CI step "Sign, notarize and staple .app") ──────────────────────
sign_app() {
  step "codesign (Developer ID, hardened runtime)"
  (cd "$REPO_ROOT" && codesign --deep --force --options runtime \
    --sign "$SIGN_IDENTITY" \
    --entitlements macos/Runner/Release.entitlements \
    "$APP")
  codesign --verify --deep --strict --verbose=2 "$APP"
  local sherpa
  sherpa="$(find "$APP/Contents" -name 'libsherpa-onnx-c-api.dylib' -print -quit)"
  [[ -n "$sherpa" ]] || die "libsherpa-onnx-c-api.dylib is not inside the signed bundle"
  codesign -dv "$sherpa" 2>&1 | head -5 || true
}

notarize_app() {
  step "notarytool submit --wait, staple, validate"
  require_var ASC_KEY_ID
  require_var ASC_ISSUER_ID
  local key="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
  [[ -f "$key" ]] || die "App Store Connect API key not found at the expected path (contents not read)"
  local zip="$TMP/whispaste-notarize.zip"
  ditto -c -k --keepParent "$APP" "$zip"
  xcrun notarytool submit "$zip" \
    --key "$key" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --wait \
    --verbose
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type exec --verbose "$APP"
}

# ── Artifacts (CI step "Prepare release artifacts") ─────────────────────────
package_artifacts() {
  step "artifacts in $ARTIFACT_DIR"
  mkdir -p "$ARTIFACT_DIR"
  ZIP="$ARTIFACT_DIR/WhisPaste-$VERSION-macos-arm64.zip"
  DMG="$ARTIFACT_DIR/WhisPaste-macos-arm64.dmg"
  DIAG_DMG="$ARTIFACT_DIR/WhisPaste-Diagnose-macOS.dmg"
  rm -f "$ZIP" "$DMG" "$DIAG_DMG"

  # ditto, not zip: plain zip flattens the Sparkle.framework symlinks.
  (cd "$REPO_ROOT/build/macos/Build/Products/Release" && ditto -c -k --keepParent WhisPaste.app "$ZIP")

  if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
      --volname "WhisPaste" \
      --window-size 500 320 \
      --icon-size 80 \
      --app-drop-link 380 170 \
      --icon "WhisPaste.app" 120 170 \
      "$DMG" \
      "$APP" || warn "create-dmg failed"
  else
    warn "create-dmg not installed (brew install create-dmg)"
  fi
  if [[ "$MODE" == upload && ! -f "$DMG" ]]; then
    die "DMG is required for the appcast and was not built (install create-dmg)"
  fi

  # WhisPaste-Diagnose: pure Dart .app bundle + DMG.
  (
    cd "$REPO_ROOT/packages/whispaste_diagnostics"
    dart pub get
    bash tool/build_app_bundle.sh
  )
  hdiutil create -volname "WhisPaste-Diagnose" \
    -srcfolder "$REPO_ROOT/packages/whispaste_diagnostics/dist/WhisPaste-Diagnose.app" \
    -ov -format UDZO \
    "$DIAG_DMG"

  ls -lh "$ARTIFACT_DIR"
}

smoke_test() {
  step "package smoke test"
  if [[ -f "$DMG" ]]; then
    (cd "$REPO_ROOT" && bash scripts/smoke/smoke-macos.sh "$DMG")
  else
    (cd "$REPO_ROOT" && bash scripts/smoke/smoke-macos.sh "$APP")
  fi
}

# ── Publishing (CI jobs create-release / publish-appcast / finalize-release) ─
require_draft() {
  local is_draft
  is_draft="$(gh release view "$TAG" --repo "$REPO" --json isDraft -q .isDraft 2>/dev/null)" \
    || die "release $TAG not found: the tag run must have created its draft (create-release) first"
  [[ "$is_draft" == "true" ]] || die "release $TAG is already published; its assets are immutable, refusing to upload"
}

upload_assets() {
  step "upload macOS assets to draft $TAG"
  gh release upload "$TAG" "$ZIP" "$DMG" "$DIAG_DMG" --repo "$REPO" --clobber
}

# Appcast: generate_appcast.sh signs the DMG (and Windows Setup.exe when present)
# into <feed>/appcast(-beta).xml. It uploads only when GITHUB_TOKEN is set, so
# the upload happens below with gh instead.
publish_appcast() {
  local channel=stable feed_name=appcast.xml
  if [[ "$TAG" == *-beta.* ]]; then channel=beta; feed_name=appcast-beta.xml; fi
  local feed="$TMP/feed"
  mkdir -p "$feed"
  cp "$DMG" "$feed/WhisPaste-macos-arm64.dmg"
  gh release download "$TAG" --repo "$REPO" --pattern 'WhisPaste-Setup.exe' --dir "$feed" --clobber \
    || die "could not download WhisPaste-Setup.exe from $TAG (the Windows job must have finished)"

  step "signed appcast ($channel)"
  env -u GITHUB_TOKEN SPARKLE_SIGNING_KEY="$(load_sparkle_key)" \
    bash "$REPO_ROOT/scripts/generate_appcast.sh" \
    --channel "$channel" \
    "$TAG" \
    "$feed" \
    "https://github.com/$REPO/releases/tag/${VERSION}"
  gh release upload "$TAG" "$feed/$feed_name" --repo "$REPO" --clobber

  if [[ "$channel" == stable ]]; then
    step "beta-channel fallback (non-fatal, as in CI)"
    if env -u GITHUB_TOKEN SPARKLE_SIGNING_KEY="$(load_sparkle_key)" \
      bash "$REPO_ROOT/scripts/publish_beta_fallback.sh" "$TAG" "$feed"; then
      if [[ -f "$feed/appcast-beta.xml" ]]; then
        gh release upload "$TAG" "$feed/appcast-beta.xml" --repo "$REPO" --clobber
      fi
    else
      warn "beta fallback refresh failed (non-fatal, as in CI)"
    fi
  else
    step "beta-appcast-pointer branch (force-push, as in CI)"
    local pdir
    pdir="$(mktemp -d "$TMP/pointer.XXXX")"
    cp "$feed/appcast-beta.xml" "$pdir/appcast-beta.xml"
    local origin
    origin="$(git -C "$REPO_ROOT" remote get-url origin)"
    (
      cd "$pdir"
      git init -q -b beta-appcast-pointer
      git add appcast-beta.xml
      # Same bot identity as publish_beta_fallback.sh (CI path).
      git -c user.name="github-actions[bot]" \
        -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
        commit -q -m "beta appcast pointer: $TAG"
      git remote add origin "$origin"
      git push -q --force origin beta-appcast-pointer
    )
  fi
}

publish_release() {
  step "publish $TAG (draft -> published)"
  gh release edit "$TAG" --repo "$REPO" --draft=false
  gh workflow run deploy-pages.yml --ref main --repo "$REPO" \
    || warn "website redeploy not triggered; run 'gh workflow run deploy-pages.yml --ref main' by hand"
}

# Gate: the published feed must be fetchable and every enclosure signed.
verify_published_feed() {
  local feed
  sleep 5
  if [[ "$TAG" == *-beta.* ]]; then
    feed="https://github.com/$REPO/releases/download/$TAG/appcast-beta.xml"
  else
    feed="https://github.com/$REPO/releases/latest/download/appcast.xml"
  fi
  curl -fsSL -o "$TMP/published-appcast.xml" "$feed"
  local enc sig
  enc="$(grep -c '<enclosure' "$TMP/published-appcast.xml" || true)"
  sig="$(grep -c 'sparkle:edSignature=' "$TMP/published-appcast.xml" || true)"
  echo "Published enclosures: ${sig}/${enc} signed ($feed)"
  [[ "$enc" -ge 1 && "$sig" -eq "$enc" ]] || die "published appcast is unsigned or empty; Sparkle would reject it"
}

# Stable only: the manifest bump runs on dev after the release is public, via the
# release workflow's manifest-only dispatch (it needs the published download URLs).
dispatch_manifest_bump() {
  if [[ "$TAG" == *-beta.* ]]; then return 0; fi
  step "manifest bump (Scoop, winget, Homebrew) via workflow_dispatch"
  gh workflow run release.yml --ref dev --repo "$REPO" -f bump-manifests=true -f tag="$TAG"
}

# ── Modes ────────────────────────────────────────────────────────────────────
run_promote() {
  local beta="v${1#v}" version="${2#v}" stable="v${2#v}"
  require_tools gh curl
  load_sparkle_key >/dev/null
  local dir="$TMP/promote"
  mkdir -p "$dir"

  step "promote $beta -> $stable (no rebuild)"
  gh release view "$beta" --repo "$REPO" >/dev/null || die "source beta release $beta not found"

  if gh release view "$stable" --repo "$REPO" >/dev/null 2>&1; then
    gh release delete "$stable" --repo "$REPO" --yes
    echo "deleted existing $stable (tag kept) for a clean re-promote"
  fi
  gh release create "$stable" --repo "$REPO" --draft \
    --title "WhisPaste v$version" \
    --notes "Stable release $version — promoted from $beta (same build, same EdDSA signature; PRD §7.2)."

  gh release download "$beta" --repo "$REPO" --dir "$dir" --clobber
  rm -f "$dir/appcast-beta.xml" "$dir/appcast.xml"
  gh release upload "$stable" "$dir"/* --repo "$REPO" --clobber

  env -u GITHUB_TOKEN SPARKLE_SIGNING_KEY="$(load_sparkle_key)" \
    bash "$REPO_ROOT/scripts/generate_appcast.sh" \
    --channel stable "$stable" "$dir" "https://github.com/$REPO/releases/tag/$version"
  gh release upload "$stable" "$dir/appcast.xml" --repo "$REPO" --clobber

  env -u GITHUB_TOKEN SPARKLE_SIGNING_KEY="$(load_sparkle_key)" \
    bash "$REPO_ROOT/scripts/publish_beta_fallback.sh" "$stable" "$dir" \
    || warn "beta fallback refresh failed (non-fatal, as in CI)"
  if [[ -f "$dir/appcast-beta.xml" ]]; then
    gh release upload "$stable" "$dir/appcast-beta.xml" --repo "$REPO" --clobber
  fi

  gh release edit "$stable" --repo "$REPO" --draft=false --latest
  TAG="$stable"
  verify_published_feed
  echo "Store submission stays an operator task (PRD §6.3): build and submit the stable MSIX locally."
}

run_build_mode() {
  TAG="v${1#v}"
  [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]] || die "tag must look like vX.Y.Z or vX.Y.Z-beta.N, got: $1"
  VERSION="${TAG#v}"
  require_tools flutter dart gh codesign xcrun ditto hdiutil cmake shasum curl

  require_var SUPABASE_URL
  require_var SUPABASE_PUBLISHABLE_KEY
  require_var WHISPASTE_MATOMO_URL
  require_var WHISPASTE_MATOMO_SITE_ID

  if [[ "$MODE" == upload ]]; then
    require_var ASC_KEY_ID
    require_var ASC_ISSUER_ID
    load_sparkle_key >/dev/null
    require_draft
  fi

  build_native
  build_app
  if [[ "$MODE" == upload ]]; then upload_dsym; fi
  sign_app
  if [[ "$MODE" == upload ]]; then notarize_app; fi
  package_artifacts
  smoke_test

  if [[ "$MODE" == dry-run ]]; then
    step "dry run finished — nothing uploaded, nothing notarized"
    echo "signed app:   $APP"
    echo "zip:          $ZIP"
    echo "dmg:          ${DMG:-missing}"
    echo "diagnose dmg: $DIAG_DMG"
    echo "notarized: no (dry run); codesign check above is the only signature gate"
    return 0
  fi

  upload_assets
  publish_appcast
  publish_release
  verify_published_feed
  dispatch_manifest_bump
  step "release $TAG done"
}

if [[ "$MODE" == promote ]]; then
  [[ ${#ARGS[@]} -eq 2 ]] || die "usage: --promote <beta-tag> <stable-version>"
  run_promote "${ARGS[0]}" "${ARGS[1]}"
else
  [[ ${#ARGS[@]} -eq 1 ]] || die "usage: --$MODE <tag>"
  run_build_mode "${ARGS[0]}"
fi
