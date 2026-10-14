/// "Support WhisPaste" page (decisions 2026-10-13 S1, S4-S10).
///
/// Every block is chosen by [supportCapabilitiesProvider] for this build, so
/// the channel matrix lives in one place. Payment blocks appear in the order
/// the capability list gives them: store-first on direct Windows and macOS
/// builds, sponsoring-first on package-managed builds. Mac App Store builds
/// show no external link at all (App Review guideline 3.1.1); their share
/// row is reduced to copying the store listing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_urls.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/deploy_channel_service.dart';
import '../../services/support/support_capabilities.dart';
import '../../services/support/support_share_links.dart';
import '../../services/support/support_state.dart';
import '../../services/support_prompt_service.dart';
import '../../services/telemetry_service.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/support_purchase_sheet.dart';
import '../../widgets/toast.dart';
import '../../widgets/wp_button.dart';

final _log = AppLogger('SupportPage');

/// Opens [url] in the system browser. Returns whether the OS accepted it.
Future<bool> _launchExternal(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } on Exception catch (e) {
    _log.error('launch failed: $e', e);
    return false;
  }
}

void _record(WidgetRef ref, SupportTelemetryEvent event, {String? name}) {
  try {
    recordSupportEvent(ref.read(telemetryProvider), event, name: name);
  } on Exception catch (e) {
    _log.debug('support telemetry skipped: $e');
  }
}

/// The sponsoring page reached from the status-bar chip and from About.
/// Where the rate action leads on each platform. Null where no store rates
/// the app, so a Windows URL can never appear on macOS.
String? supportRateUrl(SupportPlatform platform) => switch (platform) {
  SupportPlatform.macos => kMacAppStoreReviewUrl,
  SupportPlatform.windows => kWindowsStoreReviewUrl,
  SupportPlatform.linux => null,
};

class SupportPage extends ConsumerStatefulWidget {
  const SupportPage({super.key});

  @override
  ConsumerState<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends ConsumerState<SupportPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _record(ref, SupportTelemetryEvent.pageOpened);
    });
  }

  Future<void> _openLink(String url, String target) async {
    if (await _launchExternal(url)) {
      _record(ref, SupportTelemetryEvent.linkOpened, name: target);
    }
  }

  /// Sponsor links count as a browser sponsorship for the prompt's quiet
  /// period (S7). Store and share links do not.
  Future<void> _openSponsorLink(String url, String target) async {
    if (await _launchExternal(url)) {
      _record(ref, SupportTelemetryEvent.linkOpened, name: target);
      await ref.read(supportPromptProvider.notifier).markLinkOpened();
    }
  }

  Future<void> _share(SupportShareTarget target, String shareUrl) async {
    final l10n = L10n.of(context);
    final uri = buildSupportShareUri(
      target,
      text: l10n.supportShareText,
      url: shareUrl,
      subject: 'WhisPaste',
    );
    _record(ref, SupportTelemetryEvent.share, name: target.name);
    await _launchExternal(uri.toString());
  }

  Future<void> _copyLink(String shareUrl) async {
    await Clipboard.setData(ClipboardData(text: shareUrl));
    if (!mounted) return;
    WpToast.show(
      context,
      message: L10n.of(context).supportShareCopied,
      type: WpToastType.success,
    );
    _record(ref, SupportTelemetryEvent.share, name: 'copy');
  }

  Widget _storeCard({
    required L10n l10n,
    required ThemeData theme,
    required SupportPlatform platform,
    required String storeListingUrl,
    required bool primary,
  }) {
    return _SupportCard(
      key: const ValueKey('support-store-card'),
      title: platform == SupportPlatform.macos
          ? l10n.supportStoreTitleMac
          : l10n.supportStoreTitleWindows,
      children: [
        _Bullet(text: l10n.supportStoreFactManaged),
        _Bullet(text: l10n.supportStoreFactPurchase),
        _Bullet(text: l10n.supportStoreFactSameFeatures),
        const SizedBox(height: WpSpacing.xs),
        Text(
          '${l10n.supportStorePriceNote}. '
          '${l10n.supportStoreCoffeeNote}',
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
                variant: primary
                    ? WpButtonVariant.primary
                    : WpButtonVariant.secondary,
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

  Widget _othersCard(
    L10n l10n,
    ThemeData theme,
    List<SupportAsk> asks,
    bool Function() takePrimary,
  ) {
    return _SupportCard(
      key: const ValueKey('support-others-card'),
      title: l10n.supportSectionOthers,
      children: [
        if (asks.contains(SupportAsk.githubSponsors)) ...[
          Text(
            l10n.supportSponsorsNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: WpColors.textSecondary,
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          _SponsorButtonRow(
            children: [
              WpButton(
                key: const ValueKey('support-sponsors-button'),
                label: l10n.supportSponsorsCta,
                variant: takePrimary()
                    ? WpButtonVariant.primary
                    : WpButtonVariant.secondary,
                icon: FontAwesomeIcons.github.data,
                onPressed: () => _openSponsorLink(kGitHubSponsorsUrl, 'github'),
              ),
            ],
          ),
        ],
        if (asks.contains(SupportAsk.kofi) ||
            asks.contains(SupportAsk.paypal)) ...[
          const SizedBox(height: WpSpacing.sm),
          _SponsorButtonRow(
            children: [
              if (asks.contains(SupportAsk.kofi))
                WpButton(
                  key: const ValueKey('support-kofi-button'),
                  label: l10n.supportKofiCta,
                  variant: takePrimary()
                      ? WpButtonVariant.primary
                      : WpButtonVariant.secondary,
                  icon: FontAwesomeIcons.mugHot.data,
                  onPressed: () => _openSponsorLink(kKofiUrl, 'kofi'),
                ),
              if (asks.contains(SupportAsk.paypal))
                WpButton(
                  key: const ValueKey('support-paypal-button'),
                  label: l10n.supportPayPalCta,
                  variant: WpButtonVariant.secondary,
                  icon: LucideIcons.heart,
                  onPressed: () => _openSponsorLink(kPayPalUrl, 'paypal'),
                ),
            ],
          ),
        ],
      ],
    );
  }

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
        : websiteHomeUrl(langCode);
    final storeListingUrl = platform == SupportPlatform.macos
        ? kMacAppStoreListingUrl
        : kMicrosoftStoreListingUrl;
    final hasSponsoring =
        asks.contains(SupportAsk.githubSponsors) ||
        asks.contains(SupportAsk.kofi) ||
        asks.contains(SupportAsk.paypal);
    final hasPaymentAsk = hasSponsoring || asks.contains(SupportAsk.nativeTip);

    final payment = _paymentCards(
      l10n,
      theme,
      platform,
      asks,
      status,
      storeListingUrl,
    );

    final showSelfDeclare =
        !isStoreBuild && hasPaymentAsk && !status.verifiedSupporter;
    final rateUrl = asks.contains(SupportAsk.rate)
        ? supportRateUrl(platform)
        : null;

    final reach = _reachCards(l10n, asks, isMasBuild, shareUrl, rateUrl);

    return WpPageShell(
      child: Column(
        key: const ValueKey('support-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: WpSpacing.xl),
          Text(
            isStoreBuild
                ? l10n.supportStoreThankYouLine
                : l10n.supportIntroDirect,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: WpColors.textSecondary,
              height: 1.5,
            ),
          ),
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
          if (payment.isNotEmpty) ...[
            _SectionTitle(text: l10n.supportSectionOnce),
            const SizedBox(height: WpSpacing.sm),
            for (final (index, block) in payment.indexed) ...[
              if (index > 0) const SizedBox(height: WpSpacing.sm),
              block,
            ],
            const SizedBox(height: WpSpacing.lg),
          ],
          if (showSelfDeclare) ...[
            _SelfDeclare(
              declared: status.selfDeclaredSupporter,
              onDeclare: () => ref
                  .read(supportStatusProvider.notifier)
                  .declareSelfSupporter(),
              hint: l10n.supportSelfDeclareHint,
              confirmation: l10n.supportSelfDeclareNote,
              label: l10n.supportSelfDeclareCta,
            ),
            const SizedBox(height: WpSpacing.lg),
          ],
          if (reach.isNotEmpty) ...[
            _SectionTitle(text: l10n.supportSectionReach),
            const SizedBox(height: WpSpacing.sm),
            ...reach,
          ],
        ],
      ),
    );
  }

  List<Widget> _paymentCards(
    L10n l10n,
    ThemeData theme,
    SupportPlatform platform,
    List<SupportAsk> asks,
    SupportStatus status,
    String storeListingUrl,
  ) {
    final payment = <Widget>[];
    var othersShown = false;
    var primaryTaken = false;
    bool takePrimary() {
      final primary = !primaryTaken;
      primaryTaken = true;
      return primary;
    }

    for (final ask in asks) {
      switch (ask) {
        case SupportAsk.storePurchaseUpsell:
          payment.add(
            status.storeOfferDismissed
                ? _StoreOfferRestore(
                    onRestore: () => ref
                        .read(supportStatusProvider.notifier)
                        .restoreStoreOffer(),
                  )
                : _storeCard(
                    l10n: l10n,
                    theme: theme,
                    platform: platform,
                    storeListingUrl: storeListingUrl,
                    primary: takePrimary(),
                  ),
          );
        case SupportAsk.nativeTip:
          payment.add(
            _SupportCard(
              key: const ValueKey('support-native-card'),
              title: l10n.supportNativeTitle,
              children: [
                Text(
                  l10n.supportNativeDescription,
                  style: const TextStyle(
                    color: WpColors.textSecondary,
                    fontSize: WpTypography.body,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: WpSpacing.md),
                WpButton(
                  key: const ValueKey('support-native-tip-button'),
                  label: l10n.supportNativeCta,
                  variant: takePrimary()
                      ? WpButtonVariant.primary
                      : WpButtonVariant.secondary,
                  onPressed: () => showWpSupportPurchaseDialog(context),
                ),
              ],
            ),
          );
        case SupportAsk.githubSponsors:
        case SupportAsk.kofi:
        case SupportAsk.paypal:
          if (othersShown) break;
          othersShown = true;
          payment.add(_othersCard(l10n, theme, asks, takePrimary));
        case SupportAsk.star:
        case SupportAsk.rate:
        case SupportAsk.share:
          break;
      }
    }

    return payment;
  }

  List<Widget> _reachCards(
    L10n l10n,
    List<SupportAsk> asks,
    bool isMasBuild,
    String shareUrl,
    String? rateUrl,
  ) {
    return <Widget>[
      if (asks.contains(SupportAsk.share)) ...[
        if (!isMasBuild)
          Wrap(
            spacing: WpSpacing.xs,
            runSpacing: WpSpacing.xs,
            children: [
              for (final target in SupportShareTarget.values)
                WpButton(
                  key: ValueKey('support-share-${target.name}'),
                  label: _shareLabel(l10n, target),
                  variant: WpButtonVariant.secondary,
                  tone: WpButtonTone.neutral,
                  onPressed: () => _share(target, shareUrl),
                ),
            ],
          ),
        const SizedBox(height: WpSpacing.xs),
        WpButton(
          key: const ValueKey('support-share-link'),
          label: l10n.supportShareCopy,
          variant: WpButtonVariant.secondary,
          tone: WpButtonTone.neutral,
          icon: LucideIcons.copy,
          onPressed: () => _copyLink(shareUrl),
        ),
      ],
      if (asks.contains(SupportAsk.star) && !isMasBuild) ...[
        const SizedBox(height: WpSpacing.xs),
        WpButton(
          key: const ValueKey('support-star-button'),
          label: l10n.aboutStarOnGitHub,
          variant: WpButtonVariant.secondary,
          tone: WpButtonTone.neutral,
          icon: LucideIcons.star,
          onPressed: () => _openLink(kGitHubRepoUrl, 'star'),
        ),
      ],
      if (rateUrl != null) ...[
        const SizedBox(height: WpSpacing.xs),
        WpButton(
          key: const ValueKey('support-rate-button'),
          label: l10n.supportRateCta,
          variant: WpButtonVariant.secondary,
          tone: WpButtonTone.neutral,
          icon: LucideIcons.star,
          onPressed: () => _openLink(rateUrl, 'rate'),
        ),
      ],
    ];
  }

  static String _shareLabel(L10n l10n, SupportShareTarget target) =>
      switch (target) {
        SupportShareTarget.x => 'X',
        SupportShareTarget.facebook => 'Facebook',
        SupportShareTarget.whatsapp => 'WhatsApp',
        SupportShareTarget.linkedin => 'LinkedIn',
        SupportShareTarget.reddit => 'Reddit',
        SupportShareTarget.telegram => 'Telegram',
        SupportShareTarget.bluesky => 'Bluesky',
        SupportShareTarget.email => l10n.supportShareEmail,
      };
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WpSpacing.lg),
      decoration: BoxDecoration(
        color: WpColors.surfaceElevated,
        borderRadius: WpRadius.borderLg,
        border: Border.all(color: WpColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: WpSpacing.sm),
          ...children,
        ],
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
        style: const TextStyle(
          color: WpColors.textSecondary,
          fontSize: WpTypography.body,
          height: 1.5,
        ),
      ),
    );
  }
}

class _SponsorButtonRow extends StatelessWidget {
  const _SponsorButtonRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: WpSpacing.sm,
      runSpacing: WpSpacing.sm,
      children: children,
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
              style: const TextStyle(
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
      return Text(confirmation, style: textStyle);
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
