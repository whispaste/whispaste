#!/usr/bin/env bash
# strip_mas_incompatible_frameworks.sh — Xcode build phase (MAS configuration
# only) that removes frameworks from the built app bundle which cannot be
# sandboxed and are never used in the MAS build anyway.
#
# Sparkle (pulled in transitively via the `auto_updater` plugin) ships helper
# executables (Autoupdate, Updater.app, Downloader.xpc, Installer.xpc) that
# lack the com.apple.security.app-sandbox entitlement. Apple's Transporter
# rejects any MAS submission containing them (error 90296), regardless of
# whether the app ever calls into Sparkle at runtime. It doesn't: the Dart
# side already skips Sparkle registration/init for the MAS build via
# `isExternallyManaged(DeployChannel.store)` (see lib/main.dart,
# lib/services/deploy_channel_service.dart) — the App Store handles updates
# instead. This script removes the now-genuinely-unused framework from the
# bundle so the MAS package passes Apple's sandboxing check. The
# Developer-ID build (CONFIGURATION != "MAS") is untouched — it still ships
# and uses Sparkle for self-updates.
set -euo pipefail

if [[ "${CONFIGURATION:-}" != "MAS" ]]; then
  exit 0
fi

FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
SPARKLE="${FRAMEWORKS_DIR}/Sparkle.framework"

if [[ -d "$SPARKLE" ]]; then
  echo "Removing Sparkle.framework from MAS build (not sandboxable, unused — App Store handles updates)"
  rm -rf "$SPARKLE"
else
  echo "Sparkle.framework not present — nothing to strip."
fi
