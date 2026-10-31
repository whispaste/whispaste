/// Which support asks a build may present, and in which order.
///
/// Pure decision: the channel and platform are inputs, so every row of the
/// channel matrix (`internal-notes` §2.2, decisions S1 and
/// S9/S10) is unit-testable without a running OS. Unknown combinations fail
/// closed to reach-only asks (star and share), never to a payment link.
library;

import '../deploy_channel_service.dart';

/// One thing a support surface may offer.
enum SupportAsk {
  /// Buy the paid app in the store (direct builds only).
  storePurchaseUpsell,

  /// Native one-time support through the store's purchase API.
  nativeTip,

  /// GitHub Sponsors (external; the only monthly route).
  githubSponsors,

  /// Ko-fi (external, one-time).
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
/// - Windows Store builds get native one-time support plus GitHub Sponsors
///   for monthly/free amounts, per the Microsoft Store policy 10.8 rule.
/// - Mac App Store builds ([DeployChannel.store] on macOS) get no external
///   payment links at all (App Review guideline 3.1.1).
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
  SupportAsk.rate,
  SupportAsk.star,
  SupportAsk.share,
];

const _reachOnlyAsks = <SupportAsk>[SupportAsk.star, SupportAsk.share];

List<SupportAsk> _windowsAsks(DeployChannel channel) => switch (channel) {
  DeployChannel.store => const [
    SupportAsk.nativeTip,
    SupportAsk.githubSponsors,
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
