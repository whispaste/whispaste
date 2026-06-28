/// Channel-specific self-updater (Sparkle on macOS, WinSparkle on Windows) via
/// the `auto_updater` package.
///
/// Staffed by deploy channel (PRD Säule E):
/// - **store** (MSIX): no-op — the Microsoft Store auto-updates; a parallel
///   check would be redundant and a policy grey zone (10.2.2).
/// - **installer / portable** on Windows & macOS: point Sparkle/WinSparkle at
///   the GitHub Releases `appcast.xml` feed and schedule periodic background
///   checks.
/// - **Linux**: no Sparkle/WinSparkle backend — the GitHub-API
///   [UpdateNotifier] (`update_service.dart`) keeps handling Linux.
///
/// Updates must be EdDSA-signed; Sparkle/WinSparkle reject unsigned feeds. The
/// public key is embedded in the platform runner (see
/// `docs/signing-key-setup.md`); signing happens in CI, never in the repo.
library;

import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/app_urls.dart';
import '../core/logging/app_logger.dart';
import 'deploy_channel_service.dart';

final _log = AppLogger('AutoUpdater');

/// Appcast feed — CI publishes `appcast.xml` as a release asset per tag, so the
/// `latest/download` path always resolves to the newest release's feed. Built
/// from [kGitHubRepoUrl] to keep external URLs single-source.
const String kAppcastFeedUrl =
    '$kGitHubRepoUrl/releases/latest/download/appcast.xml';

/// Scheduled background check interval (24 h). Sparkle/WinSparkle enforce a
/// 3600 s minimum.
const int _checkIntervalSeconds = 86400;

// ---------------------------------------------------------------------------
// Test seams
// ---------------------------------------------------------------------------

/// Whether the current platform has a Sparkle/WinSparkle backend. Overridable
/// in tests to exercise the Linux/mobile (false) branch on any host.
@visibleForTesting
bool Function() platformSupportsSparkle = () =>
    Platform.isWindows || Platform.isMacOS;

/// Seam over [autoUpdater.setFeedURL]. Lazily defaults to the real plugin call;
/// tests overwrite it before [initAutoUpdater] so the native singleton is never
/// touched.
@visibleForTesting
Future<void> Function(String feedUrl) setFeedUrlFn = autoUpdater.setFeedURL;

/// Seam over [autoUpdater.setScheduledCheckInterval].
@visibleForTesting
Future<void> Function(int seconds) setIntervalFn =
    autoUpdater.setScheduledCheckInterval;

/// Seam over [autoUpdater.checkForUpdates].
@visibleForTesting
Future<void> Function({bool? inBackground}) checkForUpdatesFn =
    autoUpdater.checkForUpdates;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Whether [channel] uses the Sparkle/WinSparkle self-updater on this platform.
///
/// `false` for the store channel (Store auto-updates) and for platforms without
/// a Sparkle/WinSparkle backend (Linux, mobile).
bool shouldUseAutoUpdater(DeployChannel channel) {
  if (channel == DeployChannel.store) return false;
  if (!platformSupportsSparkle()) return false;
  return true;
}

/// Initializes the channel-specific self-updater.
///
/// No-op when [shouldUseAutoUpdater] is `false`. Otherwise points
/// Sparkle/WinSparkle at the GitHub Releases appcast, registers a periodic
/// background check, and triggers one silent check on startup. Failures are
/// logged, never thrown — a broken updater must not block app startup.
Future<void> initAutoUpdater(DeployChannel channel) async {
  if (!shouldUseAutoUpdater(channel)) {
    _log.info('Self-updater disabled for channel=$channel — no-op');
    return;
  }
  try {
    await setFeedUrlFn(kAppcastFeedUrl);
    await setIntervalFn(_checkIntervalSeconds);
    await checkForUpdatesFn(inBackground: true);
    _log.info('Self-updater initialized (channel=$channel)');
  } on Exception catch (e) {
    _log.warning('Self-updater init failed: $e');
  }
}
