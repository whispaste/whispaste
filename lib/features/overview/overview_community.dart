/// "Mitmachen" on the Übersicht: on top, once, the follow-up of the "Über
/// dich" questions ([OverviewAboutFollowUp]), then two link cards for the
/// project's GitHub repository and YouTube channel (each with its live number
/// when the server has one), the pills for support, store rating and the ideas
/// board, the newsletter sign-up ([OverviewNewsletterSignup]) and the
/// maintainer's own profiles as chips. The YouTube card carries the trailer
/// as a bundled thumbnail styled like an embedded player ([_TrailerFrame]); a
/// click opens the video on YouTube in the browser, the app itself never
/// contacts YouTube.
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
import '../../core/theme/generated/wp_tokens.g.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/deploy_channel_service.dart';
import '../../services/social_stats/social_stats_logic.dart'
    show SocialStatsView;
import '../../services/social_stats/social_stats_service.dart';
import '../../services/support/support_capabilities.dart'
    show SupportPlatform, supportCapabilities;
import '../../services/support/support_state.dart'
    show
        SupportLinkSurface,
        kTrailerLinkTarget,
        recordLinkOpened,
        supportPlatformProvider;
import '../../services/telemetry_service.dart';
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

/// The bundled thumbnail of the trailer [trailerVideoIdFor] picks for
/// [languageCode]: the German cut's for German, the English cut's otherwise.
/// Rendered from the trailer's own thumbnail compositions (the image on
/// YouTube), so the app needs no network for it.
String trailerThumbnailAssetFor(String languageCode) =>
    trailerVideoIdFor(languageCode) == kTrailerVideoIdDe
    ? 'assets/social/trailer-thumb-de.webp'
    : 'assets/social/trailer-thumb-en.webp';

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
    final languageCode = Localizations.localeOf(context).languageCode;
    final trailerId = trailerVideoIdFor(languageCode);
    final trailerTitle = l10n.overviewCommunityTrailerTitle;
    final trailer = _TrailerFrame(
      asset: trailerThumbnailAssetFor(languageCode),
      title: trailerTitle,
      spoken: l10n.overviewCommunityTrailerSemantics(trailerTitle),
      onPressed: () => _openTrailer(context, ref, trailerId),
    );

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
            github: _statCard(l10n, CommunityEntry.github, stats, open),
            youtube: (cardWidth) => _statCard(
              l10n,
              CommunityEntry.youtube,
              stats,
              open,
              trailer: trailer,
              cardWidth: cardWidth,
            ),
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

/// Opens the trailer on YouTube in the browser and counts the opened link
/// (`overview_community.youtube_video`), only once the browser took it.
Future<void> _openTrailer(
  BuildContext context,
  WidgetRef ref,
  String videoId,
) async {
  // Read before the await: the block may be gone once the browser is open.
  final telemetry = ref.read(telemetryProvider);
  if (!await openExternalUrl(context, youTubeWatchUrl(videoId))) return;
  recordLinkOpened(
    telemetry,
    SupportLinkSurface.overviewCommunity,
    kTrailerLinkTarget,
  );
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

/// Two cards side by side when each is wide enough to hold the trailer next
/// to its text, one under the other when not. Stacking first keeps the
/// trailer beside the text on mid widths instead of under it, which would
/// leave the GitHub card next to it half empty.
class _StatCards extends StatelessWidget {
  const _StatCards({required this.github, required this.youtube});

  final Widget github;

  /// The YouTube card for the width it gets (the trailer's place depends on
  /// it; a [LayoutBuilder] inside the card would break [IntrinsicHeight]).
  final Widget Function(double cardWidth) youtube;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = (constraints.maxWidth - WpSpacing.xs) / 2;
        if (half < _StatCard.trailerBesideFrom) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              github,
              const SizedBox(height: WpSpacing.xs),
              youtube(constraints.maxWidth),
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: github),
              const SizedBox(width: WpSpacing.xs),
              Expanded(child: youtube(half)),
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
  void Function(CommunityEntry) open, {
  Widget? trailer,
  double cardWidth = 0,
}) {
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
    trailer: trailer,
    cardWidth: cardWidth,
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
    this.trailer,
    this.cardWidth = 0,
  });

  /// Card width from which the trailer sits beside the text instead of
  /// under it: the text keeps about 180 px next to a 200 px frame.
  static const double trailerBesideFrom = 448;

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

  /// The trailer frame of the YouTube card; null on the GitHub card.
  final Widget? trailer;

  /// The width the card gets, which places [trailer] beside or under the text.
  final double cardWidth;

  /// Full screen-reader label of the card: name, benefit, number, action.
  final String spoken;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: WpColors.cardFillElevated,
      borderRadius: WpRadius.borderMd,
      border: Border.all(color: WpColors.borderSubtle),
    );
    final frame = trailer;
    if (frame == null) {
      return _LinkSurface(
        testId: testId,
        spoken: spoken,
        onPressed: onPressed,
        decoration: decoration,
        // WpCard's inside edge, so its text lines up with the newsletter
        // card below.
        builder: (hovered, pressed) => Padding(
          padding: const EdgeInsets.all(WpSpacing.xl),
          child: _content(hovered, pressed),
        ),
      );
    }
    // With the trailer the card holds two targets side by side (or one
    // under the other): the channel link and the video. Never one inside the
    // other, so each keeps its own focus stop and screen-reader name.
    const inset = WpSpacing.xl;
    final inner = cardWidth - 2 * inset;
    final beside = cardWidth >= trailerBesideFrom;
    final frameWidth = beside
        ? (inner / 2).clamp(200.0, 360.0)
        : inner.clamp(0.0, double.infinity);
    // Width only: the frame sets its own height (16:9 picture plus the title
    // line). The tight width also answers the intrinsic-width query of the
    // IntrinsicHeight row, which the picture's LayoutBuilder could not.
    final sized = SizedBox(width: frameWidth, child: frame);
    Widget link(EdgeInsets padding) => _LinkSurface(
      testId: testId,
      spoken: spoken,
      onPressed: onPressed,
      builder: (hovered, pressed) =>
          Padding(padding: padding, child: _content(hovered, pressed)),
    );
    return DecoratedBox(
      decoration: decoration,
      child: beside
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: link(const EdgeInsets.all(inset))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, inset, inset, inset),
                    child: Align(alignment: Alignment.topCenter, child: sized),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                link(
                  const EdgeInsets.fromLTRB(inset, inset, inset, WpSpacing.md),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(inset, 0, inset, inset),
                  child: sized,
                ),
              ],
            ),
    );
  }

  Widget _content(bool hovered, bool pressed) => Column(
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
  );
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

/// The trailer as a frame that looks like an embedded YouTube player: the
/// bundled 16:9 thumbnail with a light shade on top, a red play button in the
/// middle and a "YouTube" mark bottom right, and the video title as one line
/// of card text under it. No app text ever lies on the picture: the thumbnail
/// carries its own headline, which must stay readable (#2028). Picture and
/// title are one link that opens the video in the browser; nothing plays
/// inside the app and nothing is loaded from YouTube.
///
/// The parent gives the width (see [_StatCard]); the picture keeps 16:9.
class _TrailerFrame extends StatefulWidget {
  const _TrailerFrame({
    required this.asset,
    required this.title,
    required this.spoken,
    required this.onPressed,
  });

  final String asset;
  final String title;

  /// Screen-reader name: "Watch video: <title> (opens YouTube)".
  final String spoken;
  final VoidCallback onPressed;

  @override
  State<_TrailerFrame> createState() => _TrailerFrameState();
}

class _TrailerFrameState extends State<_TrailerFrame> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'CommunityTrailer');
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hover and focus darken the button and dim the picture. The button never
    // grows: that keeps it clear of the thumbnail's headline and needs no
    // motion, so "reduce motion" has nothing to switch off.
    final active = _hovered || _focused;
    final radius = WpRadius.borderMd;
    return Semantics(
      container: true,
      link: true,
      enabled: true,
      label: widget.spoken,
      identifier: 'overview-community-trailer',
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: WpFocusRing(
        focusNode: _focusNode,
        radius: WpRadius.md,
        child: InkWell(
          key: const ValueKey('overview-community-trailer'),
          focusNode: _focusNode,
          onTap: widget.onPressed,
          onHover: (on) => setState(() => _hovered = on),
          onFocusChange: (on) => setState(() => _focused = on),
          borderRadius: radius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: radius,
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        _picture(constraints.maxWidth, active),
                  ),
                ),
              ),
              const SizedBox(height: WpSpacing.xs),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WpTextStyles.rowNote.copyWith(
                  color: WpColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _picture(double width, bool active) {
    // YouTube's play button keeps its 68 x 48 shape. At 14 % of the width it
    // stays clear of the thumbnail's headline (left half, upper half) in
    // both cuts; it never exceeds YouTube's own 68 px.
    final buttonWidth = (width * 0.14).clamp(36.0, 68.0);
    final buttonHeight = buttonWidth * 48 / 68;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          widget.asset,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          // A missing image leaves the trailer's own ground colour under the
          // button, never an error text.
          errorBuilder: (_, _, _) => const ColoredBox(
            color: WpOnboardingTokens.onboardingStageGroundBottom,
          ),
        ),
        // Hover and focus dim the picture a little, as a player does.
        ColoredBox(color: WpPalette.black.withValues(alpha: active ? 0.12 : 0)),
        // A light shade on top, as on an embedded player; no text on it.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: width * 9 / 16 * 0.3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  WpPalette.black.withValues(alpha: 0.35),
                  WpPalette.black.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            width: buttonWidth,
            height: buttonHeight,
            decoration: BoxDecoration(
              color: active
                  ? WpBrandTokens.brandYoutubeFillHover
                  : WpBrandTokens.brandYoutubeFill,
              borderRadius: BorderRadius.circular(buttonHeight * 0.3),
            ),
            child: Icon(
              Icons.play_arrow_rounded,
              size: buttonHeight * 0.75,
              color: WpBrandTokens.brandYoutubeOnFill,
            ),
          ),
        ),
        Positioned(
          right: WpSpacing.xs,
          bottom: WpSpacing.xs,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: WpPalette.black.withValues(alpha: 0.72),
              borderRadius: WpRadius.borderSm,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.xs,
                vertical: 2,
              ),
              child: Text(
                'YouTube',
                style: WpTextStyles.rowNote.copyWith(color: WpPalette.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
