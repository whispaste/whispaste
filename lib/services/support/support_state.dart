/// Persisted support state: verified supporters, self-declared supporters and
/// sponsor-chip visibility (decisions S2, S4, S5 and S7 in
/// `internal-notes`).
///
/// Sponsoring never unlocks a feature. A verified purchase earns the cosmetic
/// badge and silences the automatic support prompt. A browser sponsorship
/// earns neither; it only starts the prompt's quiet period.
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../deploy_channel_service.dart';
import '../telemetry_service.dart';
import 'support_capabilities.dart';
import 'support_store_bridge.dart';
import 'support_store_bridge_factory.dart';

final _log = AppLogger('SupportState');

const _keyVerifiedSupporter = 'support_verified_supporter';
const _keySelfDeclared = 'support_self_declared';
const _keyChipHidden = 'support_chip_hidden';
const _keyStoreOfferDismissed = 'support_store_offer_dismissed';

/// Retired modal flag of the store thank-you dialog (S5). It only recorded
/// that the modal had been shown, so it is dropped on load and grants nothing.
const _keyLegacyStoreThankYouShown = 'store_thank_you_shown';

/// Snapshot of what the user has already done for the project.
final class SupportStatus {
  const SupportStatus({
    this.verifiedSupporter = false,
    this.selfDeclaredSupporter = false,
    this.chipHidden = false,
    this.storeOfferDismissed = false,
  });

  /// Verified store purchase of a support add-on or of the app itself (S4).
  final bool verifiedSupporter;

  /// Unverified local declaration on a direct build (S2). No badge.
  final bool selfDeclaredSupporter;

  /// Sponsor chip hidden by the user, or by a self-declaration.
  final bool chipHidden;

  /// The store card on the support page was dismissed by the user (S6). It
  /// only hides the card; nothing else depends on it.
  final bool storeOfferDismissed;

  /// Verified and self-declared supporters are never asked again.
  bool get suppressesPrompts => verifiedSupporter || selfDeclaredSupporter;

  /// The cosmetic supporter badge is earned by verified purchases only.
  bool get showsBadge => verifiedSupporter;

  bool get showsSponsorChip => !chipHidden;

  SupportStatus copyWith({
    bool? verifiedSupporter,
    bool? selfDeclaredSupporter,
    bool? chipHidden,
    bool? storeOfferDismissed,
  }) => SupportStatus(
    verifiedSupporter: verifiedSupporter ?? this.verifiedSupporter,
    selfDeclaredSupporter: selfDeclaredSupporter ?? this.selfDeclaredSupporter,
    chipHidden: chipHidden ?? this.chipHidden,
    storeOfferDismissed: storeOfferDismissed ?? this.storeOfferDismissed,
  );
}

/// Operating system family of the running process.
SupportPlatform currentSupportPlatform() {
  if (Platform.isWindows) return SupportPlatform.windows;
  if (Platform.isMacOS) return SupportPlatform.macos;
  return SupportPlatform.linux;
}

/// Store bridge for native purchases; see [resolveSupportStoreBridge].
final supportStoreBridgeProvider = Provider<SupportStoreBridge>(
  (ref) => resolveSupportStoreBridge(
    platform: ref.watch(supportPlatformProvider),
    channel: ref.watch(deployChannelProvider),
  ),
);

final supportPlatformProvider = Provider<SupportPlatform>(
  (ref) => currentSupportPlatform(),
);

/// Whether the store can sell a coffee purchase right now. Asked once per
/// process; any failure counts as unavailable, so the button stays hidden.
final supportStoreTipAvailableProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(supportStoreBridgeProvider).isAvailable();
  } on Exception catch (e) {
    _log.debug('store availability check failed (non-fatal): $e');
    return false;
  }
});

/// Where the coffee button of this build leads. A store build without a
/// purchase the store can sell right now shows no button.
final coffeeSupportTargetProvider = Provider<CoffeeSupportTarget>((ref) {
  final target = coffeeSupportTarget(
    ref.watch(deployChannelProvider),
    ref.watch(supportPlatformProvider),
  );
  if (target != CoffeeSupportTarget.storePurchase) return target;
  final available = ref.watch(supportStoreTipAvailableProvider).value ?? false;
  return available ? target : CoffeeSupportTarget.hidden;
});

/// Asks allowed for this build, in display order.
final supportCapabilitiesProvider = Provider<List<SupportAsk>>(
  (ref) => supportCapabilities(
    ref.watch(deployChannelProvider),
    ref.watch(supportPlatformProvider),
  ),
);

/// Reads the persisted state and refreshes the verified-purchase flag.
///
/// Once a verified purchase is stored it stays set, so the badge survives
/// offline starts. The bridge is queried only while nothing is stored yet.
Future<SupportStatus> loadSupportStatus({
  required SharedPreferences prefs,
  required SupportStoreBridge bridge,
}) async {
  await prefs.remove(_keyLegacyStoreThankYouShown);
  var verified = prefs.getBool(_keyVerifiedSupporter) ?? false;
  if (!verified && await _bridgeReportsSupport(bridge)) {
    verified = true;
    await prefs.setBool(_keyVerifiedSupporter, true);
  }
  return SupportStatus(
    verifiedSupporter: verified,
    selfDeclaredSupporter: prefs.getBool(_keySelfDeclared) ?? false,
    chipHidden: prefs.getBool(_keyChipHidden) ?? false,
    storeOfferDismissed: prefs.getBool(_keyStoreOfferDismissed) ?? false,
  );
}

Future<bool> _bridgeReportsSupport(SupportStoreBridge bridge) async {
  try {
    return await bridge.hasVerifiedAppPurchase() ||
        await bridge.hasVerifiedSupportPurchase();
  } on Exception catch (e) {
    _log.debug('store purchase check failed (non-fatal): $e');
    return false;
  }
}

/// Owns [SupportStatus]. Loads asynchronously on first build; every change
/// waits for that first load, so a late load can never overwrite a change.
class SupportStatusNotifier extends Notifier<SupportStatus> {
  late final Future<void> _loaded;

  /// Completes once the persisted status has been read.
  Future<void> get loaded => _loaded;

  @override
  SupportStatus build() {
    _loaded = _load();
    return const SupportStatus();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loaded = await loadSupportStatus(
        prefs: prefs,
        bridge: ref.read(supportStoreBridgeProvider),
      );
      if (ref.mounted) state = loaded;
    } on Exception catch (e) {
      _log.error('refresh failed: $e', e);
    }
  }

  /// Records the local "I already support WhisPaste" declaration (S2).
  /// Direct builds only. It hides the chip and stops prompts, but earns no
  /// badge because nothing verifies it.
  Future<void> declareSelfSupporter() async {
    await _loaded;
    if (ref.read(deployChannelProvider) == DeployChannel.store) return;
    state = state.copyWith(selfDeclaredSupporter: true, chipHidden: true);
    await _setBool(_keySelfDeclared, true);
    await _setBool(_keyChipHidden, true);
  }

  /// Hides the sponsor chip for every user (growth review R-12). The choice is
  /// persisted, and a hidden chip also silences the automatic support prompt.
  Future<void> hideChip() async {
    await _loaded;
    state = state.copyWith(chipHidden: true);
    await _setBool(_keyChipHidden, true);
  }

  /// Shows the sponsor chip again. Reachable from Settings › Oberfläche.
  Future<void> restoreChip() async {
    await _loaded;
    state = state.copyWith(chipHidden: false);
    await _setBool(_keyChipHidden, false);
  }

  /// Hides the store card on the support page until [restoreStoreOffer].
  Future<void> dismissStoreOffer() async {
    await _loaded;
    state = state.copyWith(storeOfferDismissed: true);
    await _setBool(_keyStoreOfferDismissed, true);
  }

  /// Shows the store card on the support page again.
  Future<void> restoreStoreOffer() async {
    await _loaded;
    state = state.copyWith(storeOfferDismissed: false);
    await _setBool(_keyStoreOfferDismissed, false);
  }

  /// Starts the store purchase for [productId] and persists a verified
  /// success. The caller must show the returned status to the user.
  Future<SupportPurchaseStatus> purchase([
    String productId = kDefaultSupportProductId,
  ]) async {
    await _loaded;
    if (!kSupportProductIds.contains(productId)) {
      return SupportPurchaseStatus.unavailable;
    }
    final SupportPurchaseStatus status;
    try {
      status = await ref.read(supportStoreBridgeProvider).purchase(productId);
    } on Exception catch (e) {
      _log.error('purchase failed: $e', e);
      return SupportPurchaseStatus.unavailable;
    }
    if (status == SupportPurchaseStatus.succeeded) {
      state = state.copyWith(verifiedSupporter: true);
      await _setBool(_keyVerifiedSupporter, true);
    }
    _track(SupportTelemetryEvent.purchase, name: status.name);
    return status;
  }

  void _track(SupportTelemetryEvent event, {String? name}) {
    try {
      recordSupportEvent(ref.read(telemetryProvider), event, name: name);
    } on Exception catch (e) {
      _log.debug('support telemetry skipped: $e');
    }
  }

  Future<void> _setBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } on Exception catch (e) {
      _log.error('persisting $key failed: $e', e);
    }
  }
}

/// Store catalogue for native tips. Empty unless this build offers the
/// native tip ask, so no store call is made where the tip is not shown.
final supportTipProductsProvider = FutureProvider<List<SupportProduct>>((
  ref,
) async {
  final asks = ref.watch(supportCapabilitiesProvider);
  if (!asks.contains(SupportAsk.nativeTip)) return const [];
  return ref.watch(supportStoreBridgeProvider).loadProducts(kSupportProductIds);
});

final supportStatusProvider =
    NotifierProvider<SupportStatusNotifier, SupportStatus>(
      SupportStatusNotifier.new,
    );

/// The passive store thank-you line (S5) shows for store installs only.
final supportStoreThankYouLineProvider = Provider<bool>(
  (ref) => ref.watch(deployChannelProvider) == DeployChannel.store,
);

/// Anonymous support events. The category is always `support`; [name] is a
/// closed set of labels (prompt kind, link target, purchase status, share
/// target). Amounts, prices, texts and receipts are never sent.
enum SupportTelemetryEvent {
  pageOpened('page_opened'),
  promptShown('prompt_shown'),
  promptDismissed('prompt_dismissed'),
  linkOpened('link_opened'),
  purchase('purchase'),
  share('share');

  const SupportTelemetryEvent(this.wireName);

  final String wireName;
}

/// Sends one support event through the opt-out telemetry pipeline.
void recordSupportEvent(
  TelemetryService telemetry,
  SupportTelemetryEvent event, {
  String? name,
}) {
  telemetry.trackEvent(category: 'support', action: event.wireName, name: name);
}

/// Where a coffee or sponsoring link was opened (GR-022). A closed list, so the
/// `linkOpened` name never carries free text.
enum SupportLinkSurface {
  about('about'),
  supportTab('support_tab'),
  prompt('prompt'),
  tray('tray');

  const SupportLinkSurface(this.wireName);

  final String wireName;
}

/// The `linkOpened` event name: `<stelle>.<ziel>`, for example `prompt.kofi`.
String linkOpenedName(SupportLinkSurface surface, String target) =>
    '${surface.wireName}.$target';

/// Sends one `linkOpened` event with its surface (GR-022).
void recordLinkOpened(
  TelemetryService telemetry,
  SupportLinkSurface surface,
  String target,
) => recordSupportEvent(
  telemetry,
  SupportTelemetryEvent.linkOpened,
  name: linkOpenedName(surface, target),
);

const _keyCoffeeBuyMeACoffeeFirst = 'support_coffee_bmc_first';

/// Whether Buy Me a Coffee stands before Ko-fi (GR-025, decision 21c). Drawn
/// once per install and then kept. The draw only decides the order: both pages
/// stay equal in rank and in look.
Future<bool> coffeeBuyMeACoffeeFirst(
  SharedPreferences prefs, {
  Random? random,
}) async {
  final stored = prefs.getBool(_keyCoffeeBuyMeACoffeeFirst);
  if (stored != null) return stored;
  final drawn = (random ?? Random()).nextBool();
  await prefs.setBool(_keyCoffeeBuyMeACoffeeFirst, drawn);
  return drawn;
}

/// The persisted coffee-pair order. Null while loading or on failure; callers
/// then use the default (Ko-fi first).
final coffeeBuyMeACoffeeFirstProvider = FutureProvider<bool>((ref) async {
  return coffeeBuyMeACoffeeFirst(await SharedPreferences.getInstance());
});
