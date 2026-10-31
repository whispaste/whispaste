/// "Mitmachen" on the Übersicht: two link cards for the project's GitHub
/// repository and YouTube channel (each with its live number when the server
/// has one), the pills for support, store rating and the ideas board, and the
/// maintainer's own profiles as chips.
///
/// Which rows a build shows is a pure rule ([communityRows]) so the channel
/// matrix is tested without a widget tree. The numbers come from
/// [socialStatsProvider]; the block asks for them once it is on screen. A card
/// without a number shows its benefit line instead, never an error.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_urls.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/navigation/help_target.dart';
import '../../core/navigation/page_state.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/deploy_channel_service.dart';
import '../../services/social_stats/social_stats_logic.dart'
    show SocialStatsView;
import '../../services/social_stats/social_stats_service.dart';
import '../../services/support/support_capabilities.dart'
    show SupportPlatform, supportCapabilities;
import '../../services/support/support_state.dart' show supportPlatformProvider;
import '../../widgets/external_link.dart';
import '../../widgets/section.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_focus_ring.dart';
import 'overview_providers.dart';

/// One link of the "Mitmachen" block.
enum CommunityEntry {
  github,
  youtube,

  /// The in-app support page, not a web address.
  support,

  /// The store's review page, on store builds of macOS and Windows only.
  rateStore,
  votepit,
  devX,
  devGitHub,
}

/// The rows of one build, in display order, in two groups that are never
/// mixed: the project's channels and the maintainer's own profiles.
typedef CommunityRows = ({
  List<CommunityEntry> project,
  List<CommunityEntry> developer,
});

/// The rows a build shows. Pure: the channel and the platform are inputs.
///
/// - Every build: GitHub and YouTube (project), X and GitHub (developer).
/// - Support: on every build that has any support ask (see [supportCapabilities]).
/// - Store builds: the store rating, on macOS and Windows.
/// - Direct builds: the ideas board.
CommunityRows communityRows({
  required DeployChannel channel,
  required SupportPlatform platform,
}) {
  final store = channel == DeployChannel.store;
  final canRate = store && platform != SupportPlatform.linux;
  final showSupport = supportCapabilities(channel, platform).isNotEmpty;
  return (
    project: [
      CommunityEntry.github,
      CommunityEntry.youtube,
      if (showSupport) CommunityEntry.support,
      if (canRate) CommunityEntry.rateStore,
      if (!store) CommunityEntry.votepit,
    ],
    developer: [CommunityEntry.devX, CommunityEntry.devGitHub],
  );
}

/// The web or store address of [entry] on [platform]; null for the in-app
/// support page. Addresses come only from `app_urls.dart`.
String? communityUrl(CommunityEntry entry, SupportPlatform platform) =>
    switch (entry) {
      CommunityEntry.github => kGitHubRepoUrl,
      CommunityEntry.youtube => kYouTubeChannelUrl,
      CommunityEntry.support => null,
      CommunityEntry.rateStore =>
        platform == SupportPlatform.macos
            ? kMacAppStoreReviewUrl
            : kWindowsStoreReviewUrl,
      CommunityEntry.votepit => kVotepitBoardUrl,
      CommunityEntry.devX => kMaintainerXUrl,
      CommunityEntry.devGitHub => kMaintainerGitHubUrl,
    };

/// The "Mitmachen" block. Shown or hidden by the page through
/// [OverviewBlock.community]; its own close field stores the same switch.
class OverviewCommunity extends ConsumerStatefulWidget {
  const OverviewCommunity({super.key});

  @override
  ConsumerState<OverviewCommunity> createState() => _OverviewCommunityState();
}

class _OverviewCommunityState extends ConsumerState<OverviewCommunity> {
  @override
  void initState() {
    super.initState();
    // The block exists only while the Übersicht shows it, so this is the one
    // place that asks for the live numbers. After the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(socialStatsProvider.notifier).refreshIfDue());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final channel = ref.watch(deployChannelProvider);
    final platform = ref.watch(supportPlatformProvider);
    final stats = ref.watch(socialStatsProvider);
    final rows = communityRows(channel: channel, platform: platform);
    void open(CommunityEntry entry) => _open(context, ref, entry, platform);

    return WpSection(
      title: l10n.overviewCommunityTitle,
      testId: 'overview-community',
      trailing: WpButton(
        testId: 'overview-community-hide',
        label: l10n.overviewCommunityHide,
        variant: WpButtonVariant.ghost,
        onPressed: () => ref
            .read(overviewPrefsProvider.notifier)
            .setBlockVisible(OverviewBlock.community, visible: false),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupLabel(text: l10n.overviewCommunityProject),
          _StatCards(
            cards: [
              _statCard(l10n, CommunityEntry.github, stats, open),
              _statCard(l10n, CommunityEntry.youtube, stats, open),
            ],
          ),
          const SizedBox(height: WpSpacing.md),
          Wrap(
            spacing: WpSpacing.xs,
            runSpacing: WpSpacing.xs,
            children: [
              for (final entry in rows.project)
                if (entry != CommunityEntry.github &&
                    entry != CommunityEntry.youtube)
                  _pill(l10n, entry, platform, open),
            ],
          ),
          const SizedBox(height: WpSpacing.lg),
          _GroupLabel(text: l10n.overviewCommunityDeveloper),
          Wrap(
            spacing: WpSpacing.xs,
            runSpacing: WpSpacing.xs,
            children: [
              for (final entry in rows.developer) _chip(l10n, entry, open),
            ],
          ),
        ],
      ),
    );
  }
}

void _open(
  BuildContext context,
  WidgetRef ref,
  CommunityEntry entry,
  SupportPlatform platform,
) {
  final url = communityUrl(entry, platform);
  if (url == null) {
    _openSupportTab(ref);
    return;
  }
  openExternalUrl(context, url);
}

/// Opens Help › Unterstützen (the Support tab), as the support prompt does.
void _openSupportTab(WidgetRef ref) {
  ref
      .read(helpTargetProvider.notifier)
      .set(const HelpTarget(tab: HelpTab.support));
  ref.read(activePageProvider.notifier).setPage('help');
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The same 12 px reading edge as the section title (WpSection).
      padding: const EdgeInsets.fromLTRB(WpSpacing.sm, 0, 0, WpSpacing.xs),
      child: Text(text, style: WpTextStyles.rowNote),
    );
  }
}

/// Two cards side by side when there is room, one under the other when not.
class _StatCards extends StatelessWidget {
  const _StatCards({required this.cards});

  final List<Widget> cards;

  static const double _sideBySideFrom = 560;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _sideBySideFrom) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cards.first,
              const SizedBox(height: WpSpacing.xs),
              cards.last,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards.first),
              const SizedBox(width: WpSpacing.xs),
              Expanded(child: cards.last),
            ],
          ),
        );
      },
    );
  }
}

/// The card of one project channel. Its benefit line comes first, the live
/// number (when there is one) second, the action last.
Widget _statCard(
  L10n l10n,
  CommunityEntry entry,
  SocialStatsView stats,
  void Function(CommunityEntry) open,
) {
  final isGithub = entry == CommunityEntry.github;
  final number = isGithub ? stats.stars : stats.subscribers;
  final title = isGithub
      ? l10n.overviewCommunityGithub
      : l10n.overviewCommunityYoutube;
  final benefit = isGithub
      ? l10n.overviewCommunityGithubBenefit
      : l10n.overviewCommunityYoutubeBenefit;
  final numberLabel = isGithub
      ? l10n.overviewCommunityStarsLabel
      : l10n.overviewCommunitySubscribersLabel;
  final action = isGithub
      ? l10n.overviewCommunityGithubAction
      : l10n.overviewCommunityYoutubeAction;
  final opensLabel = l10n.overviewCommunityOpensBrowser;
  final spoken = [
    title,
    benefit,
    if (number != null) '$number $numberLabel',
    action,
    opensLabel,
  ].join(', ');
  return Semantics(
    label: spoken,
    child: _StatCard(
      spoken: spoken,
      testId: isGithub
          ? 'overview-community-github'
          : 'overview-community-youtube',
      numberTestId: isGithub
          ? 'overview-community-stat-github'
          : 'overview-community-stat-youtube',
      logo: isGithub ? _Logo.github : _Logo.youtube,
      title: title,
      benefit: benefit,
      number: number,
      numberLabel: numberLabel,
      action: action,
      opensLabel: opensLabel,
      onPressed: () => open(entry),
    ),
  );
}

Widget _pill(
  L10n l10n,
  CommunityEntry entry,
  SupportPlatform platform,
  void Function(CommunityEntry) open,
) {
  final external = communityUrl(entry, platform) != null;
  final (label, icon, testId, opens) = switch (entry) {
    CommunityEntry.support => (
      l10n.overviewCommunitySupport,
      LucideIcons.heart,
      'overview-community-support',
      null,
    ),
    CommunityEntry.rateStore => (
      l10n.overviewCommunityRateStore,
      LucideIcons.star,
      'overview-community-rate-store',
      l10n.overviewCommunityOpensStore,
    ),
    _ => (
      l10n.overviewCommunityVotepit,
      LucideIcons.lightbulb,
      'overview-community-votepit',
      external ? l10n.overviewCommunityOpensBrowser : null,
    ),
  };
  return WpButton(
    testId: testId,
    label: label,
    semanticsLabel: opens == null ? label : '$label, $opens',
    variant: WpButtonVariant.secondary,
    icon: icon,
    onPressed: () => open(entry),
  );
}

Widget _chip(
  L10n l10n,
  CommunityEntry entry,
  void Function(CommunityEntry) open,
) {
  final isX = entry == CommunityEntry.devX;
  final name = isX ? 'X' : l10n.overviewCommunityProfileGithub;
  final handle = isX ? '@silviolindstedt' : '@silvio-l';
  final opensLabel = l10n.overviewCommunityOpensBrowser;
  return Semantics(
    label: '$name, $handle, $opensLabel',
    child: _ProfileChip(
      spoken: '$name, $handle, $opensLabel',
      testId: isX ? 'overview-community-x' : 'overview-community-dev-github',
      logo: isX ? _Logo.x : _Logo.github,
      name: name,
      handle: handle,
      opensLabel: opensLabel,
      onPressed: () => open(entry),
    ),
  );
}

/// Which mark a card or chip shows. GitHub and X are one-colour marks and
/// take the text colour (black on light, white on dark); YouTube keeps its red.
enum _Logo {
  github('assets/social/github-mark.svg', tint: true),
  x('assets/social/x-logo.svg', tint: true),
  youtube('assets/social/youtube-logo.svg', tint: false);

  const _Logo(this.asset, {required this.tint});

  final String asset;
  final bool tint;

  Widget build(double size) => SvgPicture.asset(
    asset,
    width: size,
    height: size,
    excludeFromSemantics: true,
    colorFilter: tint
        ? ColorFilter.mode(WpColors.textPrimary, BlendMode.srcIn)
        : null,
  );
}

/// The shared link surface of a card or chip: the whole area is one target,
/// with a focus ring and a minimum touch size.
class _LinkSurface extends StatefulWidget {
  const _LinkSurface({
    required this.testId,
    required this.spoken,
    required this.onPressed,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(WpRadius.md)),
    this.decoration,
  });

  final String testId;
  final String spoken;
  final VoidCallback onPressed;
  final Widget child;
  final BorderRadius borderRadius;
  final BoxDecoration? decoration;

  @override
  State<_LinkSurface> createState() => _LinkSurfaceState();
}

class _LinkSurfaceState extends State<_LinkSurface> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'CommunityLink');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      enabled: true,
      label: widget.spoken,
      identifier: widget.testId,
      excludeSemantics: true,
      child: WpFocusRing(
        focusNode: _focusNode,
        child: DecoratedBox(
          decoration: widget.decoration ?? const BoxDecoration(),
          child: InkWell(
            key: ValueKey(widget.testId),
            focusNode: _focusNode,
            onTap: widget.onPressed,
            borderRadius: widget.borderRadius,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// One project card: benefit, number, action. Flat: a surface and a 1 px edge.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.spoken,
    required this.testId,
    required this.numberTestId,
    required this.logo,
    required this.title,
    required this.benefit,
    required this.number,
    required this.numberLabel,
    required this.action,
    required this.opensLabel,
    required this.onPressed,
  });

  final String testId;
  final String numberTestId;
  final _Logo logo;
  final String title;
  final String benefit;
  final int? number;
  final String numberLabel;
  final String action;
  final String opensLabel;
  final VoidCallback onPressed;

  /// Full screen-reader label of the card: name, benefit, number, action.
  final String spoken;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: spoken,
      child: _LinkSurface(
        testId: testId,
        spoken: spoken,
        onPressed: onPressed,
        decoration: BoxDecoration(
          color: WpColors.surfaceElevated,
          borderRadius: WpRadius.borderMd,
          border: Border.all(color: WpColors.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WpSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  logo.build(WpIconSize.sm),
                  const SizedBox(width: WpSpacing.xs),
                  Expanded(child: Text(title, style: WpTextStyles.rowTitle)),
                ],
              ),
              const SizedBox(height: WpSpacing.xs),
              Text(benefit, style: WpTextStyles.rowNote),
              if (number != null) ...[
                const SizedBox(height: WpSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$number',
                      key: ValueKey(numberTestId),
                      style: WpTextStyles.lead.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    Text(numberLabel, style: WpTextStyles.rowNote),
                  ],
                ),
              ],
              const SizedBox(height: WpSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      action,
                      style: WpTextStyles.rowTitle.copyWith(
                        color: WpColors.accent,
                      ),
                    ),
                  ),
                  Icon(
                    LucideIcons.externalLink,
                    size: WpIconSize.xs,
                    color: WpColors.accent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A developer profile: mark and handle in a small pill.
class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.spoken,
    required this.testId,
    required this.logo,
    required this.name,
    required this.handle,
    required this.opensLabel,
    required this.onPressed,
  });

  final String testId;
  final _Logo logo;
  final String name;
  final String handle;
  final String opensLabel;
  final VoidCallback onPressed;

  /// Full screen-reader label of the chip: name, handle, opens browser.
  final String spoken;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: spoken,
      child: _LinkSurface(
        testId: testId,
        spoken: spoken,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(WpRadius.full),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(WpRadius.full),
          border: Border.all(color: WpColors.borderSubtle),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: WpLayout.minTouchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: WpSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                logo.build(WpIconSize.xs),
                const SizedBox(width: WpSpacing.xs),
                Text(handle, style: WpTextStyles.rowNote),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
