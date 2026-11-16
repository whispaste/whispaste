/// "Mitmachen" on the Übersicht: on top, once, the follow-up of the "Über
/// dich" questions ([OverviewAboutFollowUp]), then two link cards for the
/// project's GitHub repository and YouTube channel (each with its live number
/// when the server has one), the pills for support, store rating and the ideas
/// board, the newsletter sign-up ([OverviewNewsletterSignup]) and the
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
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_urls.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/navigation/help_target.dart';
import '../../core/navigation/page_state.dart';
import '../../core/onboarding/onboarding_surface.dart';
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
import '../../widgets/wp_text_link.dart';
import '../../widgets/wp_focus_ring.dart';
import 'overview_about_followup.dart';
import 'overview_newsletter.dart';
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
/// - Every build: the public ideas board (the preferred way to send an idea).
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
      CommunityEntry.votepit,
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

class _OverviewCommunityState extends ConsumerState<OverviewCommunity>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The Übersicht is built under the onboarding surface, and a window that
    // starts hidden (start at login) builds it too, so the block can exist
    // without being seen. It asks for the live numbers only once it is really
    // on screen: after the first frame, with the window active and not while
    // the onboarding covers it (NETWORK.md: never at start-up).
    WidgetsBinding.instance.addPostFrameCallback((_) => _askIfShown());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A hidden window that comes back asks then (the service asks once).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _askIfShown();
  }

  void _askIfShown() {
    if (!mounted || ref.read(onboardingSurfaceActiveProvider)) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    unawaited(ref.read(socialStatsProvider.notifier).refreshIfDue());
  }

  @override
  Widget build(BuildContext context) {
    // The onboarding going away uncovers the block: ask then, once.
    ref.listen<bool>(onboardingSurfaceActiveProvider, (covered, now) {
      if (covered == true && !now) _askIfShown();
    });
    final l10n = L10n.of(context);
    final channel = ref.watch(deployChannelProvider);
    final platform = ref.watch(supportPlatformProvider);
    final stats = ref.watch(socialStatsProvider);
    final rows = communityRows(channel: channel, platform: platform);
    void open(CommunityEntry entry) => _open(context, ref, entry, platform);

    return WpSection(
      title: l10n.overviewCommunityTitle,
      testId: 'overview-community',
      // A text link, like the other Übersicht cards' title actions, so its
      // words end on the cards' edge instead of a ghost button's 16 px in.
      trailing: WpTextLink(
        key: const ValueKey('overview-community-hide'),
        testID: 'overview-community-hide',
        label: l10n.overviewCommunityHide,
        onPressed: () => ref
            .read(overviewPrefsProvider.notifier)
            .setBlockVisible(OverviewBlock.community, visible: false),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OverviewAboutFollowUp(),
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
          const OverviewNewsletterSignup(),
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
  if (entry == CommunityEntry.votepit) {
    // A third-party board: say so before the browser opens (#847).
    openExternalUrlConfirmed(
      context,
      url,
      destination: L10n.of(context).overviewCommunityVotepitDestination,
    );
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
      // On the section's edge, with the title above and the cards below.
      padding: const EdgeInsets.only(bottom: WpSpacing.xs),
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
  // No Semantics wrapper here: the card's `_LinkSurface` is the one node
  // that names it. A label on top of that was read as a second, identical
  // name (parent and child with the same text, #1498).
  return _StatCard(
    spoken: spoken,
    testId: isGithub
        ? 'overview-community-github'
        : 'overview-community-youtube',
    numberTestId: isGithub
        ? 'overview-community-stat-github'
        : 'overview-community-stat-youtube',
    logo: isGithub ? _Logo.github : _Logo.youtube,
    // Decorative star in front of the GitHub count, the same filled star
    // the app uses for pinned items. Left out of the screen-reader text.
    numberLeading: isGithub
        ? const ExcludeSemantics(
            child: FaIcon(
              FontAwesomeIcons.solidStar,
              size: WpIconSize.md,
              color: WpSharedColors.pinnedAccent,
            ),
          )
        : null,
    title: title,
    benefit: benefit,
    number: number,
    numberLabel: numberLabel,
    action: action,
    opensLabel: opensLabel,
    onPressed: () => open(entry),
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
      'overview-idea-pill',
      external ? l10n.overviewCommunityOpensBrowser : null,
    ),
  };
  return WpButton(
    testId: testId,
    label: label,
    semanticsLabel: opens == null ? label : '$label, $opens',
    variant: WpButtonVariant.secondary,
    icon: icon,
    opensExternally: external && entry == CommunityEntry.votepit,
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
  // Named once, by the chip's `_LinkSurface` (#1498).
  return _ProfileChip(
    spoken: '$name, $handle, $opensLabel',
    testId: isX ? 'overview-community-x' : 'overview-community-dev-github',
    logo: isX ? _Logo.x : _Logo.github,
    name: name,
    handle: handle,
    opensLabel: opensLabel,
    onPressed: () => open(entry),
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
/// with a focus ring and a minimum touch size. [builder] gets the surface's
/// hover and press, so a call to action inside reacts like any other link.
class _LinkSurface extends StatefulWidget {
  const _LinkSurface({
    required this.testId,
    required this.spoken,
    required this.onPressed,
    required this.builder,
    this.borderRadius = const BorderRadius.all(Radius.circular(WpRadius.md)),
    this.decoration,
  });

  final String testId;
  final String spoken;
  final VoidCallback onPressed;
  final Widget Function(bool hovered, bool pressed) builder;
  final BorderRadius borderRadius;
  final BoxDecoration? decoration;

  @override
  State<_LinkSurface> createState() => _LinkSurfaceState();
}

class _LinkSurfaceState extends State<_LinkSurface> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'CommunityLink');
  bool _hovered = false;
  bool _pressed = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The one node that names and activates the card or chip (#1498):
    // `container` keeps it from merging into a neighbour, `excludeSemantics`
    // drops the visible texts it would otherwise repeat, and `onTap` hands
    // back the activation the excluded InkWell carried.
    return Semantics(
      container: true,
      link: true,
      enabled: true,
      label: widget.spoken,
      identifier: widget.testId,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: WpFocusRing(
        focusNode: _focusNode,
        child: DecoratedBox(
          decoration: widget.decoration ?? const BoxDecoration(),
          child: InkWell(
            key: ValueKey(widget.testId),
            focusNode: _focusNode,
            onTap: widget.onPressed,
            onHover: (on) => setState(() => _hovered = on),
            onHighlightChanged: (down) => setState(() => _pressed = down),
            borderRadius: widget.borderRadius,
            child: widget.builder(_hovered, _pressed),
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
    this.numberLeading,
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
  final Widget? numberLeading;
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
    return _LinkSurface(
      testId: testId,
      spoken: spoken,
      onPressed: onPressed,
      decoration: BoxDecoration(
        color: WpColors.cardFillElevated,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: WpColors.borderSubtle),
      ),
      builder: (hovered, pressed) => Padding(
        // WpCard's inside edge, so its text lines up with the newsletter
        // card below.
        padding: const EdgeInsets.all(WpSpacing.xl),
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
                  if (numberLeading case final leading?) ...[
                    leading,
                    const SizedBox(width: WpSpacing.xs),
                  ],
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
            WpLinkLabel(
              label: action,
              kind: WpLinkKind.web,
              hovered: hovered,
              pressed: pressed,
            ),
          ],
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
    return _LinkSurface(
      testId: testId,
      spoken: spoken,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(WpRadius.full),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WpRadius.full),
        border: Border.all(color: WpColors.borderSubtle),
      ),
      builder: (_, _) => ConstrainedBox(
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
    );
  }
}
