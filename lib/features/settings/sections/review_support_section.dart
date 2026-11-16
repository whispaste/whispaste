/// Where this install can be rated, for the overview's rate card.
///
/// Store installs (Mac App Store / Microsoft Store, per [DeployChannel]) open
/// their store review deep-link; every other channel (installer, portable,
/// package-managed) opens the GitHub repository, since no store listing
/// applies there. All URLs come from the single-source [kGitHubRepoUrl] /
/// [kWindowsStoreReviewUrl] / [kMacAppStoreReviewUrl] constants. The rating
/// and star rows themselves are on the support page (#395).
library;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_urls.dart';
import '../../../core/config/build_config.dart';
import '../../../services/deploy_channel_service.dart';

/// Whether a failed store page should be replaced by the GitHub repository.
///
/// Never in a Mac App Store build (growth review R-15 / decision 11c), and
/// never when the failed URL already is the GitHub repository. Shared by the
/// overview's rate card and the support page's rate row.
bool shouldFallBackToGitHub({
  required bool launched,
  required String url,
  bool isMasBuild = kIsMasBuild,
}) => !launched && !isMasBuild && url != kGitHubRepoUrl;

/// Opens where this install can be rated: the store review page for a Mac App
/// Store or Microsoft Store install, the GitHub repository on every other
/// channel (installer, portable, package-managed), which has no store listing.
/// Shared by this section and the rate card of the Übersicht.
Future<void> openRateDestination(DeployChannel channel) async {
  final url = rateDestinationUrl(
    channel: channel,
    isMacOs: defaultTargetPlatform == TargetPlatform.macOS,
    isWindows: defaultTargetPlatform == TargetPlatform.windows,
  );
  // If the store page cannot be opened (no store app, offline store), fall
  // back to the GitHub repository rather than doing nothing. A Mac App Store
  // build never leaves for GitHub (growth review R-15).
  final launched = await _open(url);
  if (shouldFallBackToGitHub(launched: launched, url: url)) {
    await _open(kGitHubRepoUrl);
  }
}

/// The rating destination of [channel] on the running platform.
@visibleForTesting
String rateDestinationUrl({
  required DeployChannel channel,
  required bool isMacOs,
  required bool isWindows,
}) => switch (channel) {
  DeployChannel.store when isMacOs => kMacAppStoreReviewUrl,
  DeployChannel.store when isWindows => kWindowsStoreReviewUrl,
  _ => kGitHubRepoUrl,
};

Future<bool> _open(String url) async {
  final uri = Uri.parse(url);
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
