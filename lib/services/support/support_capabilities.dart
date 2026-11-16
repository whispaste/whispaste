/// Which support asks a build may present, and in which order.
///
/// Pure decision: the channel and platform are inputs, so every row of the
/// channel matrix (decisions S1, S9 and S10) is unit-testable without a running OS. Unknown combinations fail
/// closed to reach-only asks (star and share), never to a payment link.
library;

import '../../core/app_urls.dart';
import '../deploy_channel_service.dart';

/// One thing a support surface may offer.
enum SupportAsk {
  /// Buy the paid app in the store (direct builds only).
  storePurchaseUpsell,

  /// Native one-time support through the store's purchase API.
  nativeTip,

  /// GitHub Sponsors (external; the only monthly route).
  githubSponsors,

  /// External coffee pages: Ko-fi and configured Buy Me a Coffee link.
  kofi,

  /// PayPal (external, one-time, extra button per S9).
  paypal,

  /// Star the repository on GitHub.
  star,

  /// Rate the app in the store.
  rate,

  /// Share the product link.
  share,
}

/// Operating system family of the running build.
enum SupportPlatform { windows, macos, linux }

/// Asks allowed for a build, in display order.
///
/// - Windows direct builds (installer, portable) lead with the store purchase,
///   then sponsoring. Package-managed (Scoop) leads with sponsoring.
/// - Windows Store builds lead with native one-time support, then offer
///   GitHub Sponsors, Ko-fi/Buy Me a Coffee and PayPal without digital rewards
///   (Microsoft Store policy 10.8.2; decision 2026-11-05, #1036).
///   Browser checkout is allowed after installation; third-party providers
///   must be disclosed in Partner Center during submission. Policy source:
///   https://learn.microsoft.com/en-us/windows/apps/publish/store-policies#108-financial-transactions
/// - Mac App Store builds ([DeployChannel.store] on macOS) offer the same
///   channels as direct builds, with the native tip first (maintainer decision
///   2026-11-09, #1006). Guideline 3.1.1 only bars calls to action towards
///   other purchasing mechanisms for unlocking content; voluntary support
///   unlocks nothing (grey zone, 3.2.1(vii)). If App Review objects, remove
///   [SupportAsk.githubSponsors], [SupportAsk.kofi] and [SupportAsk.paypal]
///   from [_macAppStoreAsks] below, the only place to change, and resubmit
///   (`internal-notes`).
/// - Linux gets sponsoring and reach asks only.
List<SupportAsk> supportCapabilities(
  DeployChannel channel,
  SupportPlatform platform,
) {
  switch (platform) {
    case SupportPlatform.windows:
      return _windowsAsks(channel);
    case SupportPlatform.macos:
      if (channel == DeployChannel.store) {
        return _macAppStoreAsks;
      }
      return _macDirectAsks(channel);
    case SupportPlatform.linux:
      return _linuxAsks(channel);
  }
}

const _macAppStoreAsks = <SupportAsk>[
  SupportAsk.nativeTip,
  SupportAsk.githubSponsors,
  SupportAsk.kofi,
  SupportAsk.paypal,
  SupportAsk.rate,
  SupportAsk.star,
  SupportAsk.share,
];

const _reachOnlyAsks = <SupportAsk>[SupportAsk.star, SupportAsk.share];

List<SupportAsk> _windowsAsks(DeployChannel channel) => switch (channel) {
  DeployChannel.store => const [
    SupportAsk.nativeTip,
    SupportAsk.githubSponsors,
    SupportAsk.kofi,
    SupportAsk.paypal,
    SupportAsk.rate,
    SupportAsk.star,
    SupportAsk.share,
  ],
  DeployChannel.installer || DeployChannel.portable => const [
    SupportAsk.storePurchaseUpsell,
    SupportAsk.githubSponsors,
    SupportAsk.kofi,
    SupportAsk.paypal,
    SupportAsk.star,
    SupportAsk.rate,
    SupportAsk.share,
  ],
  DeployChannel.packageManaged => const [
    SupportAsk.githubSponsors,
    SupportAsk.kofi,
    SupportAsk.paypal,
    SupportAsk.storePurchaseUpsell,
    SupportAsk.star,
    SupportAsk.share,
  ],
};

List<SupportAsk> _macDirectAsks(DeployChannel channel) => switch (channel) {
  DeployChannel.portable => const [
    SupportAsk.storePurchaseUpsell,
    SupportAsk.githubSponsors,
    SupportAsk.kofi,
    SupportAsk.paypal,
    SupportAsk.star,
    SupportAsk.share,
  ],
  DeployChannel.packageManaged => const [
    SupportAsk.githubSponsors,
    SupportAsk.kofi,
    SupportAsk.paypal,
    SupportAsk.storePurchaseUpsell,
    SupportAsk.star,
    SupportAsk.share,
  ],
  DeployChannel.store || DeployChannel.installer => _reachOnlyAsks,
};

List<SupportAsk> _linuxAsks(DeployChannel channel) => switch (channel) {
  DeployChannel.portable || DeployChannel.packageManaged => const [
    SupportAsk.githubSponsors,
    SupportAsk.kofi,
    SupportAsk.paypal,
    SupportAsk.star,
    SupportAsk.share,
  ],
  DeployChannel.store || DeployChannel.installer => _reachOnlyAsks,
};

/// Where the coffee support button ("Lade mich auf einen Kaffee ein") of a
/// build leads. Pure, so the channel matrix is testable per platform.
enum CoffeeSupportTarget {
  /// No coffee button: the build offers no coffee route.
  hidden,

  /// The store's own one-time purchase. Store builds only, and only where the
  /// store can sell it right now.
  storePurchase,

  /// External coffee pages (Ko-fi, optionally Buy Me a Coffee). Direct builds
  /// only; a store build never reaches this case (its coffee button stays the
  /// native tip; the external channels live on the support page).
  externalLinks,
}

/// The coffee target of a build. A store build's coffee button gets the native
/// purchase or nothing; the external channels a store build may offer (see
/// [supportCapabilities]) are reached through the support page, not this
/// button. Direct builds with a Ko-fi ask get the external pages.
CoffeeSupportTarget coffeeSupportTarget(
  DeployChannel channel,
  SupportPlatform platform,
) {
  final asks = supportCapabilities(channel, platform);
  if (channel == DeployChannel.store) {
    return asks.contains(SupportAsk.nativeTip)
        ? CoffeeSupportTarget.storePurchase
        : CoffeeSupportTarget.hidden;
  }
  return asks.contains(SupportAsk.kofi)
      ? CoffeeSupportTarget.externalLinks
      : CoffeeSupportTarget.hidden;
}

/// One external coffee page: its address and the suffix that extends the
/// button's test id (`about-coffee-button` + suffix).
typedef CoffeeLink = ({String url, String idSuffix});

/// The external coffee pages, Ko-fi first. Buy Me a Coffee is listed only
/// when [buyMeACoffeeUrl] is set, so a null constant yields Ko-fi alone.
List<CoffeeLink> coffeeExternalLinks({
  String? buyMeACoffeeUrl = kBuyMeACoffeeUrl,
}) => [
  (url: kKofiUrl, idSuffix: ''),
  if (buyMeACoffeeUrl != null)
    (url: buyMeACoffeeUrl, idSuffix: '-buy-me-a-coffee'),
];

/// One external way to give an amount of one's own choosing ("Other amount"
/// in the purchase sheet, decisions 3 and 8a+c in #155).
enum OtherAmountWay {
  /// GitHub Sponsors (also the only monthly route).
  githubSponsors,

  /// Ko-fi.
  kofi,

  /// Buy Me a Coffee; listed only when its link is configured.
  buyMeACoffee,

  /// PayPal.
  paypal,
}

/// The ways "Other amount" may lead to for a build, in matrix order. Derived
/// from [supportCapabilities], so a channel never gets a payment link its
/// matrix row does not allow (reach-only rows yield an empty list, and the
/// sheet then hides the entry). The fixed price ladder stays at five native
/// tiers (1,99 / 4,99 / 9,99 / 19,99 / 49,99 €, not the eight once proposed);
/// anything else goes through these external ways, so no further store
/// products are created.
List<OtherAmountWay> otherAmountWays(
  DeployChannel channel,
  SupportPlatform platform, {
  String? buyMeACoffeeUrl = kBuyMeACoffeeUrl,
}) {
  final asks = supportCapabilities(channel, platform);
  return [
    for (final ask in asks)
      ...switch (ask) {
        SupportAsk.githubSponsors => const [OtherAmountWay.githubSponsors],
        SupportAsk.kofi => [
          OtherAmountWay.kofi,
          if (buyMeACoffeeUrl != null) OtherAmountWay.buyMeACoffee,
        ],
        SupportAsk.paypal => const [OtherAmountWay.paypal],
        _ => const <OtherAmountWay>[],
      },
  ];
}

/// The address an [OtherAmountWay] opens.
String otherAmountUrl(OtherAmountWay way) => switch (way) {
  OtherAmountWay.githubSponsors => kGitHubSponsorsUrl,
  OtherAmountWay.kofi => kKofiUrl,
  OtherAmountWay.buyMeACoffee => kBuyMeACoffeeUrl,
  OtherAmountWay.paypal => kPayPalUrl,
};
