/// Channel-specific self-updater (Sparkle on macOS, WinSparkle on Windows) via
/// the `auto_updater` package.
///
/// Two independent "channel" concepts converge here:
/// - **Deploy channel** (`DeployChannel`, PRD Säule E) gates *whether* the
///   self-updater runs at all:
///   - **store** (MSIX): no-op — the Microsoft Store auto-updates; a parallel
///     check would be redundant and a policy grey zone (10.2.2).
///   - **installer / portable** on Windows & macOS: run Sparkle/WinSparkle.
///   - **Linux**: no Sparkle/WinSparkle backend — the GitHub-API
///     [UpdateNotifier] (`update_service.dart`) keeps handling Linux.
/// - **Update channel** (`UpdateChannel`, PRD Säule *Beta- & Stable-Release-
///   Kanäle*) decides *which feed* is polled once the updater runs:
///   `stable` (`appcast.xml`) or `beta` (`appcast-beta.xml`).
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
import 'update_channel_service.dart';

final _log = AppLogger('AutoUpdater');

/// The stable appcast feed — GitHub-natively resolves to the newest
/// non-prerelease. Built from [kGitHubRepoUrl] to keep external URLs
/// single-source.
const String _stableAppcastFeedUrl =
    '$kGitHubRepoUrl/releases/latest/download/appcast.xml';

/// The beta appcast feed — served from a dedicated `beta-appcast-pointer` git
/// branch that CI force-pushes on every beta release (PRD §5.3, Issue 08 fix
/// v2). Deliberately NOT a `releases/download/...` URL: GitHub's
/// immutable-releases feature (GA 2025-10) permanently locks a release's
/// tag_name once published, which made the previous "reused beta-latest
/// Release object" pointer permanently unusable — a branch carries no such
/// restriction, so raw.githubusercontent.com can serve it indefinitely.
const String _betaAppcastFeedUrl =
    'https://raw.githubusercontent.com/whispaste/whispaste/beta-appcast-pointer/appcast-beta.xml';

/// Resolves the appcast feed URL for [channel] at runtime (PRD §5.3):
/// - [UpdateChannel.stable] → [_stableAppcastFeedUrl]
/// - [UpdateChannel.beta]    → [_betaAppcastFeedUrl]
///
/// Overridable at build time via `--dart-define=WP_APPCAST_URL=…` for the
/// local E2E self-update test (served from `http://localhost:PORT/`): when the
/// define is non-empty it wins for both channels, since the local harness
/// serves a single appcast regardless of channel. Replaces the former
/// compile-time `kAppcastFeedUrl` const so the feed is now derived from the
/// persisted update channel.
String appcastFeedUrl(UpdateChannel channel) {
  const override = String.fromEnvironment('WP_APPCAST_URL');
  if (override.isNotEmpty) return override;
  return switch (channel) {
    UpdateChannel.stable => _stableAppcastFeedUrl,
    UpdateChannel.beta => _betaAppcastFeedUrl,
  };
}

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

/// Seam over [autoUpdater.addListener]. Lazily defaults to the real plugin
/// call; tests overwrite it before [registerSparkleListener] so the native
/// singleton is never touched.
@visibleForTesting
void Function(UpdaterListener listener) addUpdaterListenerFn =
    autoUpdater.addListener;

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
/// Sparkle/WinSparkle at the appcast feed derived from [updateChannel]
/// (`stable`/`beta`), registers a periodic background check, and triggers one
/// silent check on startup. Failures are logged, never thrown — a broken
/// updater must not block app startup.
Future<void> initAutoUpdater(
  DeployChannel channel,
  UpdateChannel updateChannel,
) async {
  if (!shouldUseAutoUpdater(channel)) {
    _log.info('Self-updater disabled for channel=$channel — no-op');
    return;
  }
  try {
    await setFeedUrlFn(appcastFeedUrl(updateChannel));
    await setIntervalFn(_checkIntervalSeconds);
    await checkForUpdatesFn(inBackground: true);
    _log.info(
      'Self-updater initialized (deploy=$channel, update=$updateChannel)',
    );
  } on Exception catch (e) {
    _log.warning('Self-updater init failed: $e');
  }
}

/// Presents Sparkle/WinSparkle's native update window immediately.
///
/// This is the in-app entry point for the status-bar "update available" chip:
/// tapping it opens the platform-native "A new version is available — install
/// now?" dialog, which performs the download + in-place swap + relaunch.
///
/// Must only be called when [shouldUseAutoUpdater] is `true` (the caller in
/// `app.dart` routes on it). Re-asserts the [updateChannel]-derived feed URL
/// first so a foreground check works even if the startup init race hasn't
/// completed yet. Failures are logged, never thrown — a broken present must
/// not crash the tap handler.
Future<void> presentSparkleUpdate(UpdateChannel updateChannel) async {
  try {
    await setFeedUrlFn(appcastFeedUrl(updateChannel));
    await checkForUpdatesFn(inBackground: false);
    _log.info('Sparkle foreground update check presented');
  } on Exception catch (e) {
    _log.warning('Sparkle foreground check failed: $e');
  }
}

// ---------------------------------------------------------------------------
// Mirroring native events into the app's own update state
// ---------------------------------------------------------------------------

/// Translates native Sparkle/WinSparkle events into plain callbacks.
///
/// Before this existed, the native self-updater's "update available" state
/// was invisible to the rest of the app — the status bar chip, About page,
/// and Settings all read `updateProvider` (`update_service.dart`), which
/// only the GitHub-API mechanism ever populated, and that mechanism only ran
/// automatically on Linux. On macOS/Windows the native 24h background check
/// found updates that no UI surface ever reflected (fix target: PRD Bug 1).
class _SparkleUpdaterListener with UpdaterListener {
  _SparkleUpdaterListener({
    required this.onChecking,
    required this.onAvailable,
    required this.onUpToDate,
    required this.onError,
  });

  final void Function() onChecking;
  final void Function(String version, String? releaseNotesUrl) onAvailable;
  final void Function() onUpToDate;
  final void Function(String message) onError;

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) => onChecking();

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    final version =
        appcastItem?.displayVersionString ?? appcastItem?.versionString;
    if (version == null) return;
    onAvailable(version, appcastItem?.releaseNotesURL);
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) => onUpToDate();

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    // Sparkle/WinSparkle take over the download + install prompt natively
    // from here; [UpdateState] has no downloading/readyToInstall
    // representation for the native path, so there is nothing to mirror.
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {}

  @override
  void onUpdaterError(UpdaterError? error) =>
      onError(error?.message ?? 'Unknown updater error');
}

/// Registers a listener that mirrors native Sparkle/WinSparkle events via
/// [onChecking]/[onAvailable]/[onUpToDate]/[onError]. No-op on platforms
/// without a Sparkle/WinSparkle backend. Call once, before [initAutoUpdater],
/// from `main.dart` — the caller wires the callbacks to the shared
/// `UpdateNotifier` mutators (`markCheckingNative` et al. in
/// `update_service.dart`) so every UI surface shares one source of truth.
void registerSparkleListener({
  required void Function() onChecking,
  required void Function(String version, String? releaseNotesUrl) onAvailable,
  required void Function() onUpToDate,
  required void Function(String message) onError,
}) {
  if (!platformSupportsSparkle()) return;
  addUpdaterListenerFn(
    _SparkleUpdaterListener(
      onChecking: onChecking,
      onAvailable: onAvailable,
      onUpToDate: onUpToDate,
      onError: onError,
    ),
  );
}
