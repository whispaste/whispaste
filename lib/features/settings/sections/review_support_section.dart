/// Always-on „WhisPaste bewerten & unterstützen" settings section.
///
/// A cooldown- and gate-free path for users who want to rate or support the
/// app on their own initiative — independent of the review-prompt trigger
/// logic. On Windows it opens the Microsoft Store review deep-link; on
/// macOS/Linux it opens the GitHub repository (no store listing exists).
/// All URLs come from the single-source [kGitHubRepoUrl] /
/// [kWindowsStoreReviewUrl] constants.
library;

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_urls.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/section.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';

class ReviewSupportSection extends ConsumerWidget {
  const ReviewSupportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
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
              onPressed: _launchReviewSupport,
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

  // Platform-branched review URL, consistent with the review-prompt dialog's
  // platform convention (store review where a store exists, GitHub otherwise).
  Future<void> _launchReviewSupport() async {
    final url = io.Platform.isWindows ? kWindowsStoreReviewUrl : kGitHubRepoUrl;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
