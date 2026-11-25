/// "Support WhisPaste" page (decisions 2026-10-13 S1, S4-S10; #395).
///
/// Only ways to support the project, in the channel matrix's provider order.
/// One-time and monthly headings follow that order rather than overriding it.
/// Feedback and contact live on their own Help tab. Store builds share their
/// store listing link.
library;

import 'dart:async';

import '../../widgets/external_link.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/accessibility/announce.dart';
import '../../core/app_urls.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/logging/app_logger.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/deploy_channel_service.dart';
import '../../services/support/support_capabilities.dart';
import '../../services/support/support_state.dart';
import '../../services/support_prompt_service.dart';
import '../../services/social_stats/social_stats_service.dart';
import '../../services/telemetry_service.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/support_purchase_sheet.dart';
import '../../widgets/wp_coffee_button.dart';
import '../../widgets/wp_provider_tile.dart';
import '../settings/sections/review_support_section.dart';
import '../settings/widgets/wp_settings_group.dart';
import '../../widgets/wp_copy_feedback.dart';
import 'recommend_share_buttons.dart';
import 'support_value.dart';
import '../overview/overview_providers.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/wp_button.dart';
import '../../widgets/wp_card.dart';

final _log = AppLogger('SupportPage');

void _record(WidgetRef ref, SupportTelemetryEvent event, {String? name}) {
  try {
    recordSupportEvent(ref.read(telemetryProvider), event, name: name);
  } on Exception catch (e) {
    _log.debug('support telemetry skipped: $e');
  }
}

/// Where the rate action leads on each platform, so a Windows URL can never
/// appear on macOS. Linux has no store to rate in; the row stays (parity, and
/// the settings search jumps to it) and leads to the GitHub repository, as
/// the rate action did before the support page was split.
String supportRateUrl(SupportPlatform platform) => switch (platform) {
  SupportPlatform.macos => kMacAppStoreReviewUrl,
  SupportPlatform.windows => kWindowsStoreReviewUrl,
  SupportPlatform.linux => kGitHubRepoUrl,
};

class SupportPage extends ConsumerStatefulWidget {
  const SupportPage({super.key, this.embedded = false});

  /// True inside the Help hub, which supplies the page shell and scrolling.
  final bool embedded;

  @override
  ConsumerState<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends ConsumerState<SupportPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _record(ref, SupportTelemetryEvent.pageOpened);
      unawaited(_refreshStatsIfCommunityShown());
    });
  }

  /// The star count of the "without money" block: the same once-a-day
  /// request the overview makes, never more often. Hiding "Mitmachen" on the
  /// Übersicht is the one switch for these numbers: then this page does not
  /// ask either (local-first, #735).
  Future<void> _refreshStatsIfCommunityShown() async {
    await ref.read(overviewPrefsProvider.notifier).ready;
    if (!mounted) return;
    final prefs = ref.read(overviewPrefsProvider);
    if (!overviewBlockShown(
      OverviewBlock.community,
      hidden: prefs.hiddenBlocks,
      shown: prefs.shownBlocks,
    )) {
      return;
    }
    await ref.read(socialStatsProvider.notifier).refreshIfDue();
  }

  /// `linkOpened` with the surface of this page (GR-022).
  void _recordLink(String target) => _record(
    ref,
    SupportTelemetryEvent.linkOpened,
    name: linkOpenedName(SupportLinkSurface.supportTab, target),
  );

  Future<void> _openLink(String url, String target) async {
    if (await openExternalUrl(context, url) && mounted) {
      _recordLink(target);
    }
  }

  /// The store review page; when it cannot be opened (no store app, store
  /// offline) the GitHub repository instead, except in the Mac App Store
  /// build, which never leaves for GitHub (growth review R-15).
  Future<void> _openRate(String url, {required bool isMasBuild}) async {
    final launched = await openExternalUrl(context, url);
    if (!mounted) return;
    if (launched) {
      _recordLink('rate');
    } else if (shouldFallBackToGitHub(
      launched: launched,
      url: url,
      isMasBuild: isMasBuild,
    )) {
      await _openLink(kGitHubRepoUrl, 'github');
    }
  }

  /// Sponsor links count as a browser sponsorship for the prompt's quiet
  /// period (S7). Store and share links do not; the coffee tiles start it
  /// through [openCoffeeLink].
  Future<void> _openSponsorLink(String url, String target) async {
    // Read before the await: the ref is gone once the page has closed.
    final prompt = ref.read(supportPromptProvider.notifier);
    if (await openExternalUrl(context, url)) {
      if (mounted) _recordLink(target);
      await prompt.markLinkOpened();
    }
  }

  Widget _storeCard({
    required L10n l10n,
    required ThemeData theme,
    required SupportPlatform platform,
    required String storeListingUrl,
  }) {
    return _SupportCard(
      key: const ValueKey('support-store-card'),
      title: platform == SupportPlatform.macos
          ? l10n.supportStoreTitleMac
          : l10n.supportStoreTitleWindows,
      // Reasons in the fixed order of the purchase copy (#1941): what the
      // store version gives on this platform, what it costs, what the money
      // is for, and that the free version stays complete.
      children: [
        _Bullet(
          text: platform == SupportPlatform.macos
              ? l10n.supportStoreFactManagedMac
              : l10n.supportStoreFactManagedWindows,
        ),
        _Bullet(text: l10n.supportStoreFactOneTime),
        _Bullet(text: l10n.supportStoreFactPurchase),
        _Bullet(text: l10n.supportStoreFactSameFeatures),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.supportStoreCoffeeNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: WpColors.textSecondary,
          ),
        ),
        const SizedBox(height: WpSpacing.md),
        Row(
          children: [
            Expanded(
              child: WpButton(
                key: const ValueKey('support-store-cta'),
                label: platform == SupportPlatform.macos
                    ? l10n.supportStoreCtaMac
                    : l10n.supportStoreCtaWindows,
                variant: WpButtonVariant.secondary,
                onPressed: () => _openLink(storeListingUrl, 'store'),
              ),
            ),
            const SizedBox(width: WpSpacing.xs),
            WpButton(
              key: const ValueKey('support-store-offer-dismiss'),
              label: l10n.supportStoreDismiss,
              variant: WpButtonVariant.ghost,
              tone: WpButtonTone.neutral,
              onPressed: () =>
                  ref.read(supportStatusProvider.notifier).dismissStoreOffer(),
            ),
          ],
        ),
      ],
    );
  }

  /// A provider tile that opens [url] as a browser sponsorship (PayPal,
  /// GitHub Sponsors): it starts the prompt's quiet period (S7).
  Widget _sponsorTile(
    L10n l10n,
    WpSupportProvider provider, {
    required String description,
    required String testId,
    required String url,
    required String target,
  }) => WpProviderTile(
    provider: provider,
    description: description,
    semanticLabel: l10n.supportWithProvider(provider.label),
    testId: testId,
    onPressed: () => _openSponsorLink(url, target),
  );

  /// The coffee pages as tiles, in the install's drawn order (GR-025). Empty
  /// on every build whose matrix has no Ko-fi ask.
  ///
  /// While the draw loads, both slots are held by invisible tiles of the same
  /// size (UX-082, UX-083): the order is only shown once it is known, and
  /// neither the coffee block nor the tiles after it move when it arrives.
  List<Widget> _coffeeTiles(L10n l10n, List<SupportAsk> asks) {
    if (!asks.contains(SupportAsk.kofi)) return const [];
    final links = orderedCoffeeLinks(ref);
    if (ref.watch(coffeeBuyMeACoffeeFirstProvider).isLoading) {
      return [
        for (final link in links)
          Visibility.maintain(
            visible: false,
            child: WpProviderTile(
              provider: link.idSuffix.isEmpty
                  ? WpSupportProvider.kofi
                  : WpSupportProvider.buyMeACoffee,
              description: l10n.supportCoffeeDesc,
              semanticLabel: '',
              testId: 'support-coffee-pending${link.idSuffix}',
              onPressed: () {},
            ),
          ),
      ];
    }
    return [
      for (final link in links)
        if (link.idSuffix.isEmpty)
          _coffeeTile(
            l10n,
            WpSupportProvider.kofi,
            link,
            'support-kofi-button',
            'kofi',
          )
        else
          _coffeeTile(
            l10n,
            WpSupportProvider.buyMeACoffee,
            link,
            'support-buy-me-a-coffee-button',
            'buymeacoffee',
          ),
    ];
  }

  Widget _coffeeTile(
    L10n l10n,
    WpSupportProvider provider,
    CoffeeLink link,
    String testId,
    String target,
  ) => WpProviderTile(
    provider: provider,
    description: l10n.supportCoffeeDesc,
    semanticLabel: l10n.supportWithProvider(provider.label),
    testId: testId,
    onPressed: () => unawaited(
      openCoffeeLink(
        context,
        ref,
        url: link.url,
        target: target,
        surface: SupportLinkSurface.supportTab,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final asks = ref.watch(supportCapabilitiesProvider);
    final platform = ref.watch(supportPlatformProvider);
    final channel = ref.watch(deployChannelProvider);
    final status = ref.watch(supportStatusProvider);
    final langCode = ref.watch(localeProvider).languageCode;

    final isStoreBuild = channel == DeployChannel.store;
    final isMasBuild = isStoreBuild && platform == SupportPlatform.macos;
    final isWindowsStore = isStoreBuild && platform == SupportPlatform.windows;
    final shareUrl = isMasBuild
        ? kMacAppStoreListingUrl
        : isWindowsStore
        ? kMicrosoftStoreListingUrl
        : websiteLocalizedHomeUrl(langCode);
    final storeListingUrl = platform == SupportPlatform.macos
        ? kMacAppStoreListingUrl
        : kMicrosoftStoreListingUrl;
    final hasPaymentAsk =
        asks.contains(SupportAsk.githubSponsors) ||
        asks.contains(SupportAsk.kofi) ||
        asks.contains(SupportAsk.paypal) ||
        asks.contains(SupportAsk.nativeTip);

    // Group adjacent payment asks without changing the matrix's priority.
    // Coffee expands in place to the installation's persisted pair order.
    final payments = <Widget>[];
    var tiles = <Widget>[];
    bool? monthlySection;
    void flushTiles() {
      if (tiles.isEmpty) return;
      payments.add(_TileGrid(children: tiles));
      payments.add(const SizedBox(height: WpSpacing.sm));
      tiles = <Widget>[];
    }

    for (final ask in asks) {
      if (ask == SupportAsk.rate ||
          ask == SupportAsk.star ||
          ask == SupportAsk.share) {
        continue;
      }
      final monthly = ask == SupportAsk.githubSponsors;
      if (monthlySection != monthly) {
        flushTiles();
        if (monthlySection != null) {
          payments.add(const SizedBox(height: WpSpacing.lg));
        }
        payments.add(
          _SectionTitle(
            text: monthly
                ? l10n.supportSectionMonthly
                : l10n.supportSectionOnce,
          ),
        );
        payments.add(const SizedBox(height: WpSpacing.sm));
        monthlySection = monthly;
      }
      switch (ask) {
        case SupportAsk.storePurchaseUpsell:
        case SupportAsk.nativeTip:
          flushTiles();
          payments.addAll(
            _storeCards(l10n, theme, platform, [ask], status, storeListingUrl),
          );
          payments.add(const SizedBox(height: WpSpacing.sm));
        case SupportAsk.githubSponsors:
          tiles.add(
            _sponsorTile(
              l10n,
              WpSupportProvider.githubSponsors,
              description: l10n.supportSponsorsDesc,
              testId: 'support-sponsors-button',
              url: kGitHubSponsorsUrl,
              target: 'github',
            ),
          );
        case SupportAsk.kofi:
          tiles.addAll(_coffeeTiles(l10n, asks));
        case SupportAsk.paypal:
          tiles.add(
            _sponsorTile(
              l10n,
              WpSupportProvider.paypal,
              description: l10n.supportPayPalDesc,
              testId: 'support-paypal-button',
              url: kPayPalUrl,
              target: 'paypal',
            ),
          );
        case SupportAsk.rate:
        case SupportAsk.star:
        case SupportAsk.share:
          break;
      }
    }
    flushTiles();

    final showSelfDeclare =
        !isStoreBuild && hasPaymentAsk && !status.verifiedSupporter;
    // The rate row is permanent on every channel (the settings search jumps
    // to it); without a store ask it leads to the GitHub repository.
    final rateUrl = asks.contains(SupportAsk.rate)
        ? supportRateUrl(platform)
        : kGitHubRepoUrl;
    final free = _freeRows(l10n, asks, isMasBuild, shareUrl, rateUrl);

    final body = Column(
      key: const ValueKey('support-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          !isStoreBuild
              ? l10n.supportIntroDirect
              : ref.watch(supportStoreThankYouLineProvider)
              ? l10n.supportStoreThankYouLine
              : l10n.supportStoreTestEnvironment,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: WpColors.textSecondary,
            height: 1.5,
          ),
        ),
        if (ref.watch(supportValueProvider).value case final value?) ...[
          const SizedBox(height: WpSpacing.xs),
          Text(
            supportValueText(l10n, langCode, value),
            key: const ValueKey('support-value-line'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: WpColors.textSecondary,
            ),
          ),
        ],
        if (!isStoreBuild) ...[
          const SizedBox(height: WpSpacing.xs),
          Text(
            l10n.supportCostsNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: WpColors.textSecondary,
            ),
          ),
        ],
        if (status.suppressesPrompts) ...[
          const SizedBox(height: WpSpacing.lg),
          _SupporterLine(
            text: l10n.supportSupporterLine,
            badge: status.showsBadge ? l10n.supportSupporterBadge : null,
          ),
        ],
        const SizedBox(height: WpSpacing.lg),
        ...payments,
        if (payments.isNotEmpty) const SizedBox(height: WpSpacing.lg),
        if (showSelfDeclare) ...[
          _SelfDeclare(
            declared: status.selfDeclaredSupporter,
            onDeclare: () {
              ref.read(supportStatusProvider.notifier).declareSelfSupporter();
              // The live region below only speaks when it is already in the
              // tree; the announcement makes the confirmation reliable.
              announce(
                View.of(context),
                l10n.supportSelfDeclareNote,
                Directionality.of(context),
              );
            },
            hint: l10n.supportSelfDeclareHint,
            confirmation: l10n.supportSelfDeclareNote,
            label: l10n.supportSelfDeclareCta,
          ),
          const SizedBox(height: WpSpacing.lg),
        ],
        if (free.isNotEmpty)
          WpSettingsGroup(heading: l10n.supportSectionFree, children: free),
      ],
    );
    return widget.embedded ? body : WpPageShell(child: body);
  }

  /// The store's own blocks: the purchase offer on direct builds, the native
  /// one-time purchase on store builds.
  List<Widget> _storeCards(
    L10n l10n,
    ThemeData theme,
    SupportPlatform platform,
    List<SupportAsk> asks,
    SupportStatus status,
    String storeListingUrl,
  ) => [
    if (asks.contains(SupportAsk.nativeTip))
      _SupportCard(
        key: const ValueKey('support-native-card'),
        title: l10n.supportNativeTitle,
        children: [
          Text(
            l10n.supportNativeDescription,
            style: TextStyle(
              color: WpColors.textSecondary,
              fontSize: WpTypography.body,
              height: 1.5,
            ),
          ),
          const SizedBox(height: WpSpacing.md),
          WpButton(
            key: const ValueKey('support-native-tip-button'),
            label: l10n.supportNativeCta,
            variant: WpButtonVariant.primary,
            onPressed: () => showWpSupportPurchaseDialog(context),
          ),
        ],
      ),
    if (asks.contains(SupportAsk.storePurchaseUpsell))
      status.storeOfferDismissed
          ? _StoreOfferRestore(
              onRestore: () =>
                  ref.read(supportStatusProvider.notifier).restoreStoreOffer(),
            )
          : _storeCard(
              l10n: l10n,
              theme: theme,
              platform: platform,
              storeListingUrl: storeListingUrl,
            ),
  ];

  /// The ways to help without money, as settings rows: rating in this
  /// build's own store, the GitHub star (with the live count when it is
  /// fresh) and telling others.
  List<Widget> _freeRows(
    L10n l10n,
    List<SupportAsk> asks,
    bool isMasBuild,
    String shareUrl,
    String rateUrl,
  ) {
    final stars = ref.watch(socialStatsProvider).stars;
    return <Widget>[
      WpSettingsRow(
        rowId: 'advanced-review',
        title: l10n.reviewSupportLabel,
        subtitle: l10n.supportRateDesc,
        trailing: WpButton(
          key: const ValueKey('support-rate-button'),
          label: l10n.supportRateCta,
          variant: WpButtonVariant.secondary,
          tone: WpButtonTone.neutral,
          icon: LucideIcons.star,
          onPressed: () => _openRate(rateUrl, isMasBuild: isMasBuild),
        ),
      ),
      if (asks.contains(SupportAsk.star))
        WpSettingsRow(
          rowId: 'advanced-github-star',
          title: l10n.reviewSupportGitHubLabel,
          subtitle: stars == null
              ? l10n.supportStarDesc
              : '${l10n.supportStarCount(stars)} ${l10n.supportStarDesc}',
          trailing: WpButton(
            key: const ValueKey('support-star-button'),
            label: l10n.reviewSupportGitHubAction,
            variant: WpButtonVariant.secondary,
            tone: WpButtonTone.neutral,
            icon: LucideIcons.star,
            onPressed: () => _openLink(kGitHubRepoUrl, 'star'),
          ),
        ),
      if (asks.contains(SupportAsk.share)) ...[
        WpSettingsRow(
          rowId: 'support-share',
          title: l10n.supportShareTitle,
          trailing: WpCopyButton(
            testId: 'support-share-link',
            label: l10n.supportShareCopy,
            variant: WpButtonVariant.secondary,
            tone: WpButtonTone.neutral,
            text: () => shareUrl,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
          child: RecommendShareButtons(
            baseUrl: shareUrl,
            languageCode: ref.watch(localeProvider).languageCode,
            testIdPrefix: 'support-share',
            onShared: (channel) =>
                _record(ref, SupportTelemetryEvent.share, name: channel),
          ),
        ),
      ],
    ];
  }
}

/// Provider tiles side by side at their own content width, flowing into the
/// next line when the window is narrow or the text large (#1070). Each tile
/// gets at most the full width, where its text wraps instead of overflowing.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: WpSpacing.sm, runSpacing: WpSpacing.sm, children: children);
}

/// A support route on [WpCard]: its title line, then the route's content.
class _SupportCard extends StatelessWidget {
  const _SupportCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return WpCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(color: WpColors.textSecondary),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.xxs),
      child: Text(
        text,
        style: TextStyle(
          color: WpColors.textSecondary,
          fontSize: WpTypography.body,
          height: 1.5,
        ),
      ),
    );
  }
}

class _StoreOfferRestore extends StatelessWidget {
  const _StoreOfferRestore({required this.onRestore});

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: WpButton(
        key: const ValueKey('support-store-offer-restore'),
        label: L10n.of(context).supportStoreShowAgain,
        variant: WpButtonVariant.ghost,
        tone: WpButtonTone.neutral,
        onPressed: onRestore,
      ),
    );
  }
}

class _SupporterLine extends StatelessWidget {
  const _SupporterLine({required this.text, this.badge});

  final String text;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          LucideIcons.heart,
          size: WpIconSize.sm,
          color: WpSharedColors.supportHeart,
        ),
        const SizedBox(width: WpSpacing.sm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
        if (badge != null)
          Container(
            key: const ValueKey('support-supporter-badge'),
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: WpSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: WpColors.surfaceChipFill,
              borderRadius: WpRadius.borderFull,
            ),
            child: Text(
              badge!,
              style: TextStyle(
                color: WpColors.textSecondary,
                fontSize: WpTypography.caption,
              ),
            ),
          ),
      ],
    );
  }
}

class _SelfDeclare extends StatelessWidget {
  const _SelfDeclare({
    required this.declared,
    required this.onDeclare,
    required this.hint,
    required this.confirmation,
    required this.label,
  });

  /// Once true, the block shows [confirmation] instead of the button.
  final bool declared;
  final VoidCallback onDeclare;
  final String hint;
  final String confirmation;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: WpColors.textSecondary);
    if (declared) {
      // A live region: the button the user just pressed is replaced by this
      // line, so a screen reader announces the confirmation instead of
      // falling silent.
      return Semantics(
        liveRegion: true,
        identifier: 'support-self-declare-confirmation',
        child: Text(confirmation, style: textStyle),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(hint, style: textStyle),
        const SizedBox(height: WpSpacing.xs),
        WpButton(
          key: const ValueKey('support-self-declare-button'),
          label: label,
          variant: WpButtonVariant.ghost,
          tone: WpButtonTone.neutral,
          onPressed: onDeclare,
        ),
      ],
    );
  }
}
