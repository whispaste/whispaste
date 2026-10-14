/// Shared fakes for the support UI tests: a status notifier that never touches
/// SharedPreferences or a store bridge, and the provider overrides that pin a
/// build to one deploy channel and platform.
library;

import 'package:http/http.dart' as http;
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/support/support_capabilities.dart';
import 'package:whispaste/services/support/support_state.dart';
import 'package:whispaste/services/support/support_store_bridge.dart';
import 'package:whispaste/services/telemetry_service.dart';

/// Records calls and answers purchases with [purchaseResult]. Overrides every
/// method the UI reaches, so the real `loaded` gate is never awaited.
class FakeSupportStatusNotifier extends SupportStatusNotifier {
  FakeSupportStatusNotifier([this.initial = const SupportStatus()]);

  final SupportStatus initial;
  final List<String> calls = [];
  SupportPurchaseStatus purchaseResult = SupportPurchaseStatus.succeeded;

  @override
  SupportStatus build() => initial;

  @override
  Future<void> dismissStoreOffer() async {
    calls.add('dismissStoreOffer');
    state = state.copyWith(storeOfferDismissed: true);
  }

  @override
  Future<void> restoreStoreOffer() async {
    calls.add('restoreStoreOffer');
    state = state.copyWith(storeOfferDismissed: false);
  }

  @override
  Future<void> declareSelfSupporter() async {
    calls.add('declareSelfSupporter');
    state = state.copyWith(selfDeclaredSupporter: true, chipHidden: true);
  }

  @override
  Future<void> hideChip() async {
    calls.add('hideChip');
    state = state.copyWith(chipHidden: true);
  }

  @override
  Future<void> restoreChip() async {
    calls.add('restoreChip');
    state = state.copyWith(chipHidden: false);
  }

  @override
  Future<SupportPurchaseStatus> purchase([
    String productId = kDefaultSupportProductId,
  ]) async {
    calls.add('purchase:$productId');
    if (purchaseResult == SupportPurchaseStatus.succeeded) {
      state = state.copyWith(verifiedSupporter: true);
    }
    return purchaseResult;
  }
}

/// Telemetry that never sends anything (consent off, no endpoint).
TelemetryService silentTelemetry() => TelemetryService(
  client: http.Client(),
  endpointUrl: '',
  siteId: 0,
  consentGranted: false,
  dntActive: false,
);

/// Pins one deploy channel and platform. The capability list comes from the
/// real decision table, so these tests also cover the channel matrix.
List<Object> supportOverrides({
  required DeployChannel channel,
  required SupportPlatform platform,
  required FakeSupportStatusNotifier status,
  List<SupportProduct> products = const [],
  Object? productsError,
  Future<List<SupportProduct>>? pendingCatalogue,
}) => [
  deployChannelProvider.overrideWithValue(channel),
  supportPlatformProvider.overrideWithValue(platform),
  supportCapabilitiesProvider.overrideWithValue(
    supportCapabilities(channel, platform),
  ),
  supportStatusProvider.overrideWith(() => status),
  supportTipProductsProvider.overrideWith((ref) async {
    if (pendingCatalogue != null) return pendingCatalogue;
    if (productsError != null) throw productsError;
    return products;
  }),
  telemetryProvider.overrideWithValue(silentTelemetry()),
];
