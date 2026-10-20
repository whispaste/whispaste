/// Always-on „WhisPaste bewerten & unterstützen" settings section.
///
/// A cooldown- and gate-free path for users who want to rate or support the
/// app on their own initiative — independent of the review-prompt trigger
/// logic. Store installs (Mac App Store / Microsoft Store, per
/// [deployChannelProvider]) open their respective store review deep-link;
/// every other channel (installer, portable, package-managed) opens the
/// GitHub repository, since no store listing applies there. All URLs come
/// from the single-source [kGitHubRepoUrl] / [kWindowsStoreReviewUrl] /
/// [kMacAppStoreReviewUrl] constants.
library;

import '../../../widgets/external_link.dart';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_urls.dart';
import '../../../core/config/build_config.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../services/deploy_channel_service.dart';
import '../../../widgets/wp_button.dart';
import '../widgets/wp_settings_group.dart';

/// Whether a failed store page should be replaced by the GitHub repository.
///
/// Never in a Mac App Store build (growth review R-15 / decision 11c), and
/// never when the failed URL already is the GitHub repository.
@visibleForTesting
bool shouldFallBackToGitHub({
  required bool launched,
  required String url,
  bool isMasBuild = kIsMasBuild,
}) => !launched && !isMasBuild && url != kGitHubRepoUrl;

class ReviewSupportSection extends ConsumerWidget {
  const ReviewSupportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final channel = ref.watch(deployChannelProvider);
    return WpSettingsGroup(
      heading: l10n.reviewSupportEntry,
      children: [
        WpSettingsRow(
          rowId: 'advanced-review',
          title: l10n.reviewSupportLabel,
          trailing: WpButton(
            label: l10n.reviewSupportAction,
            variant: WpButtonVariant.secondary,
            onPressed: () => _launchReviewSupport(channel),
          ),
        ),
        // Same quiet, gate-free register as the row above — an
        // opt-in destination for users who want to shape the roadmap,
        // not a prompt anyone is pushed toward.
        WpSettingsRow(
          rowId: 'advanced-ideas',
          title: l10n.ideasBoardLabel,
          trailing: WpButton(
            label: l10n.ideasBoardAction,
            variant: WpButtonVariant.secondary,
            onPressed: () => _launchIdeasBoard(context),
          ),
        ),
      ],
    );
  }

  Future<void> _launchIdeasBoard(BuildContext context) async {
    await openExternalUrl(context, kVotepitBoardUrl);
  }

  // Channel-branched review URL, consistent with the review-prompt dialog's
  // platform convention (store review where a store exists, GitHub
  // otherwise). `DeployChannel.store` covers both the Mac App Store
  // (macOS) and the Microsoft Store (Windows) — every other channel
  // (installer, portable, package-managed) has no store listing to link to.
  Future<void> _launchReviewSupport(DeployChannel channel) async {
    final url = switch (channel) {
      DeployChannel.store when io.Platform.isMacOS => kMacAppStoreReviewUrl,
      DeployChannel.store when io.Platform.isWindows => kWindowsStoreReviewUrl,
      _ => kGitHubRepoUrl,
    };
    // If the store page cannot be opened (no store app, offline store), fall
    // back to the GitHub repository rather than doing nothing. A Mac App Store
    // build never leaves for GitHub (growth review R-15).
    final launched = await _open(url);
    if (shouldFallBackToGitHub(launched: launched, url: url)) {
      await _open(kGitHubRepoUrl);
    }
  }

  Future<bool> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
