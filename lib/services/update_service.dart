/// App update service — checks GitHub Releases for newer versions and handles
/// the update flow based on deploy channel.
///
/// - **Installer channel**: Downloads `WhisPaste-Setup.exe`, launches it, exits app.
/// - **Portable channel**: Shows download link to the user.
/// - **Store channel**: No-op (Store handles updates).
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sentry_dio/sentry_dio.dart';

import '../core/app_info.dart';
import '../core/logging/app_logger.dart';
import 'deploy_channel_service.dart';

final _log = AppLogger('Update');

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _githubOwner = 'whispaste';
const _githubRepo = 'whispaste';
const _releasesApiUrl =
    'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest';

/// Returns the platform-specific installer asset name to search for.
String get _setupAssetName {
  if (Platform.isMacOS) return 'WhisPaste-macos-arm64.dmg';
  if (Platform.isLinux) return 'WhisPaste-linux-x64.tar.gz';
  return 'WhisPaste-Setup.exe'; // Windows
}

// ---------------------------------------------------------------------------
// Update state
// ---------------------------------------------------------------------------

/// Lifecycle phases for the update check + download flow.
enum UpdatePhase {
  /// No check performed yet.
  idle,

  /// Querying GitHub Releases API.
  checking,

  /// A newer version is available.
  available,

  /// Downloading the installer asset.
  downloading,

  /// Download complete, ready to install.
  readyToInstall,

  /// No update available — already on latest.
  upToDate,

  /// Something went wrong (see [UpdateState.errorMessage]).
  error,
}

/// Immutable snapshot of the update lifecycle.
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.latestVersion,
    this.downloadUrl,
    this.releaseNotesUrl,
    this.downloadedPath,
    this.progressPercent = 0,
    this.errorMessage,
  });

  final UpdatePhase phase;
  final String? latestVersion;
  final String? downloadUrl;
  final String? releaseNotesUrl;
  final String? downloadedPath;
  final double progressPercent;
  final String? errorMessage;

  bool get isBusy =>
      phase == UpdatePhase.checking || phase == UpdatePhase.downloading;

  UpdateState copyWith({
    UpdatePhase? phase,
    String? latestVersion,
    String? downloadUrl,
    String? releaseNotesUrl,
    String? downloadedPath,
    double? progressPercent,
    String? errorMessage,
  }) {
    return UpdateState(
      phase: phase ?? this.phase,
      latestVersion: latestVersion ?? this.latestVersion,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      releaseNotesUrl: releaseNotesUrl ?? this.releaseNotesUrl,
      downloadedPath: downloadedPath ?? this.downloadedPath,
      progressPercent: progressPercent ?? this.progressPercent,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class UpdateNotifier extends Notifier<UpdateState> {
  CancelToken? _cancelToken;
  late final Dio _dio;

  /// Test-only override for the Dio client. When set BEFORE the notifier is
  /// first observed, `build()` uses this instance instead of constructing a
  /// real one. Lets tests inject a mock adapter (e.g. for the
  /// "network-error must not capture to Sentry" contract from the reliability
  /// sprint Modul 6).
  @visibleForTesting
  static Dio? dioOverrideForTesting;

  @override
  UpdateState build() {
    final override = dioOverrideForTesting;
    if (override != null) {
      _dio = override;
    } else {
      _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(minutes: 5),
          headers: {'User-Agent': appUserAgent},
        ),
      );
      // Sentry MUST be the last interceptor added — see notes in
      // http_model_fetcher.dart. Spans piggy-back on the active transaction's
      // sample decision and respect the global `tracesSampleRate`.
      _dio.addSentry();
    }
    ref.onDispose(() {
      _cancelToken?.cancel('disposed');
      _dio.close();
    });
    return const UpdateState();
  }

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Check GitHub Releases for a newer version.
  ///
  /// No-op if already busy, or if the deploy channel is [DeployChannel.store].
  Future<void> checkForUpdate() async {
    final channel = ref.read(deployChannelProvider);
    if (channel == DeployChannel.store) {
      _log.info('Store channel — skipping update check');
      state = const UpdateState(phase: UpdatePhase.upToDate);
      return;
    }
    if (state.isBusy) return;

    state = const UpdateState(phase: UpdatePhase.checking);
    _log.info('Checking for updates...');

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _releasesApiUrl,
        options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
      );

      final data = response.data;
      if (data == null) {
        state = const UpdateState(
          phase: UpdatePhase.error,
          errorMessage: 'Empty response from GitHub',
        );
        return;
      }

      final tagName = (data['tag_name'] as String?) ?? '';
      final latestVersion = tagName.startsWith('v')
          ? tagName.substring(1)
          : tagName;

      if (latestVersion.isEmpty) {
        state = const UpdateState(
          phase: UpdatePhase.error,
          errorMessage: 'Could not parse version from release',
        );
        return;
      }

      // Compare versions.
      if (!isNewer(latestVersion, appVersion)) {
        _log.info('Up to date (current=$appVersion, latest=$latestVersion)');
        state = UpdateState(
          phase: UpdatePhase.upToDate,
          latestVersion: latestVersion,
        );
        return;
      }

      // Find the setup asset download URL.
      final assets = (data['assets'] as List<dynamic>?) ?? [];
      String? setupUrl;
      for (final asset in assets) {
        final assetMap = asset as Map<String, dynamic>;
        final name = (assetMap['name'] as String?) ?? '';
        if (name == _setupAssetName) {
          setupUrl = assetMap['browser_download_url'] as String?;
          break;
        }
      }

      final htmlUrl = data['html_url'] as String?;

      _log.info('Update available: $latestVersion (current=$appVersion)');
      state = UpdateState(
        phase: UpdatePhase.available,
        latestVersion: latestVersion,
        downloadUrl: setupUrl,
        releaseNotesUrl: htmlUrl,
      );
    } on DioException catch (e) {
      // Update-check network failures are deliberately NOT escalated to
      // Sentry — they are expected (laptop on a plane, GitHub rate limit,
      // captive WiFi) and were burning Free-Tier quota for zero diagnostic
      // value. See `.scratch/reliability-sprint/prd.md` — Modul 6.
      // `_log.warning` stays a Sentry breadcrumb but NOT a captured event.
      final statusCode = e.response?.statusCode;
      _log.warning('Update check failed (status=$statusCode): ${e.message}');
      state = UpdateState(
        phase: UpdatePhase.error,
        errorMessage: statusCode == 403
            ? 'GitHub rate limit exceeded. Try again later.'
            : 'Could not reach GitHub (${e.message})',
      );
    } catch (e, st) {
      // Non-Dio path (e.g. malformed JSON from a captive-portal HTML page).
      // Same rationale as the DioException branch above: log-only, no
      // Sentry capture.
      _log.warning('Update check failed: $e\n$st');
      state = UpdateState(phase: UpdatePhase.error, errorMessage: e.toString());
    }
  }

  /// Download the installer and prepare for installation.
  ///
  /// Only works when [state.phase] is [UpdatePhase.available] and
  /// [state.downloadUrl] is non-null.
  Future<void> downloadUpdate() async {
    if (state.phase != UpdatePhase.available || state.downloadUrl == null) {
      return;
    }

    final channel = ref.read(deployChannelProvider);
    if (channel != DeployChannel.installer && !Platform.isMacOS) {
      // Portable channel can't auto-install; just open the release page.
      // macOS always downloads the DMG regardless of deploy channel.
      return;
    }

    _cancelToken = CancelToken();

    // Validate the download URL comes from GitHub (defense-in-depth).
    final uri = Uri.parse(state.downloadUrl!);
    if (!uri.host.endsWith('github.com') &&
        !uri.host.endsWith('githubusercontent.com')) {
      state = state.copyWith(
        phase: UpdatePhase.error,
        errorMessage: 'Download URL is not from GitHub',
      );
      return;
    }

    state = state.copyWith(phase: UpdatePhase.downloading, progressPercent: 0);

    final tempDir = Directory.systemTemp;
    final targetPath = p.join(tempDir.path, _setupAssetName);

    try {
      await _dio.download(
        state.downloadUrl!,
        targetPath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            state = state.copyWith(progressPercent: received / total);
          }
        },
      );

      _log.info('Downloaded update to $targetPath');
      state = state.copyWith(
        phase: UpdatePhase.readyToInstall,
        downloadedPath: targetPath,
        progressPercent: 1.0,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = const UpdateState(phase: UpdatePhase.idle);
        return;
      }
      _log.error('Download failed', e);
      state = state.copyWith(
        phase: UpdatePhase.error,
        errorMessage: 'Download failed: ${e.message}',
      );
    } catch (e, st) {
      _log.error('Download failed', e, st);
      state = state.copyWith(
        phase: UpdatePhase.error,
        errorMessage: 'Download failed: $e',
      );
    }
  }

  /// Launch the downloaded installer and exit the app.
  ///
  /// The NSIS installer will kill the running process, overwrite files,
  /// and optionally restart the app from its Finish page.
  Future<void> installUpdate() async {
    if (state.phase != UpdatePhase.readyToInstall ||
        state.downloadedPath == null) {
      return;
    }

    final installerPath = state.downloadedPath!;

    // Verify the file still exists before trying to launch it.
    final installerFile = File(installerPath);
    if (!installerFile.existsSync()) {
      _log.error('Installer file not found: $installerPath');
      state = const UpdateState(
        phase: UpdatePhase.error,
        errorMessage: 'Installer file not found. Please download again.',
      );
      return;
    }

    _log.info('Launching installer: $installerPath');

    try {
      if (Platform.isMacOS) {
        // Open the DMG — macOS mounts it and the user drags to Applications.
        // Don't exit: user needs to complete drag-install manually.
        await Process.start('open', [
          installerPath,
        ], mode: ProcessStartMode.detached);
        state = state.copyWith(phase: UpdatePhase.idle);
        return;
      } else {
        // Windows: launch the NSIS installer which handles everything.
        await Process.start(
          installerPath,
          [], // interactive mode — user sees the wizard
          mode: ProcessStartMode.detached,
        );
      }

      // Give the installer a moment to start before we exit.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    } catch (e, st) {
      _log.error('Failed to launch installer', e, st);
      state = state.copyWith(
        phase: UpdatePhase.error,
        errorMessage: 'Could not launch installer: $e',
      );
    }
  }

  /// Cancel an in-progress download.
  void cancelDownload() {
    _cancelToken?.cancel('user cancelled');
    state = const UpdateState(phase: UpdatePhase.idle);
  }

  /// Reset to idle state (e.g. dismiss an error or "up to date" notice).
  void dismiss() {
    state = const UpdateState(phase: UpdatePhase.idle);
  }

  // -----------------------------------------------------------------------
  // Semver comparison
  // -----------------------------------------------------------------------

  /// Returns `true` if [candidate] is strictly newer than [current].
  ///
  /// Only compares major.minor.patch — pre-release tags are ignored.
  @visibleForTesting
  static bool isNewer(String candidate, String current) {
    final candidateParts = parseSemver(candidate);
    final currentParts = parseSemver(current);
    if (candidateParts == null || currentParts == null) return false;

    for (var i = 0; i < 3; i++) {
      if (candidateParts[i] > currentParts[i]) return true;
      if (candidateParts[i] < currentParts[i]) return false;
    }
    return false; // equal
  }

  /// Parse "X.Y.Z" into [major, minor, patch]. Returns null on failure.
  @visibleForTesting
  static List<int>? parseSemver(String version) {
    // Strip leading 'v' if present.
    final clean = version.startsWith('v') ? version.substring(1) : version;
    // Strip build metadata (e.g. "+4") and pre-release suffix (e.g. "-beta.1").
    final noBuild = clean.split('+').first;
    final base = noBuild.split('-').first;
    final parts = base.split('.');
    if (parts.length < 3) return null;
    try {
      return [int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])];
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);
