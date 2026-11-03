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
#
# auto_updater_macos.framework (the Flutter plugin wrapping Sparkle) is
# stripped alongside it. It's not itself unsandboxable, but its own compiled
# binary references Sparkle's SPUStandardUserDriver class via eager
# Objective-C class binding — dyld resolves this at *load* time, not at
# call time, so weaken_dylib_links.py's weak-linking (applied to the main
# executable's own references, see below) cannot save it: as soon as
# auto_updater_macos.framework itself is loaded, it independently crashes
# with "Symbol not found: _OBJC_CLASS_$_SPUStandardUserDriver" even though
# nothing ever calls .register() on it (GeneratedPluginRegistrant.swift
# guards that call with `#if !MAS_BUILD` too, but that alone is not
# sufficient — confirmed by actually launching a local MAS test build).
# Removing the file entirely means dyld never maps it into memory at all.
set -euo pipefail

if [[ "${CONFIGURATION:-}" != "MAS" ]]; then
  exit 0
fi

FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

for FRAMEWORK_NAME in Sparkle auto_updater_macos; do
  FRAMEWORK_PATH="${FRAMEWORKS_DIR}/${FRAMEWORK_NAME}.framework"
  if [[ -d "$FRAMEWORK_PATH" ]]; then
    echo "Removing ${FRAMEWORK_NAME}.framework from MAS build (not sandboxable or Sparkle-dependent, unused — App Store handles updates)"
    rm -rf "$FRAMEWORK_PATH"
  else
    echo "${FRAMEWORK_NAME}.framework not present — nothing to strip."
  fi
done

# Weak-link the main executable's own references to the frameworks just
# removed, so dyld skips them silently instead of refusing to launch the
# process (see weaken_dylib_links.py's module docstring for the full
# root-cause explanation).
python3 "${SRCROOT}/weaken_dylib_links.py" "${BUILT_PRODUCTS_DIR}/${EXECUTABLE_PATH}"
