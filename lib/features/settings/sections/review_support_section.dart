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

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_urls.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../services/deploy_channel_service.dart';
import '../../../widgets/section.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';

class ReviewSupportSection extends ConsumerWidget {
  const ReviewSupportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final channel = ref.watch(deployChannelProvider);
    return WpSection(
      title: l10n.reviewSupportEntry,
      subtitle: l10n.reviewSupportSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.star,
            label: l10n.reviewSupportLabel,
            trailing: WpButton(
              label: l10n.reviewSupportAction,
              variant: WpButtonVariant.secondary,
              onPressed: () => _launchReviewSupport(channel),
            ),
          ),
          // Same quiet, gate-free register as the row above — an
          // opt-in destination for users who want to shape the roadmap,
          // not a prompt anyone is pushed toward.
          SettingRow(
            icon: LucideIcons.lightbulb,
            label: l10n.ideasBoardLabel,
            trailing: WpButton(
              label: l10n.ideasBoardAction,
              variant: WpButtonVariant.secondary,
              onPressed: _launchIdeasBoard,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchIdeasBoard() async {
    final uri = Uri.parse(kVotepitBoardUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
