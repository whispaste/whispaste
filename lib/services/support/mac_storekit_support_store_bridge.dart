import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import 'support_store_bridge.dart';

final _log = AppLogger('MacStoreKitSupportStore');

/// MethodChannel name served by `macos/Runner/SupportStoreHost.swift`.
const String kMacStoreKitChannelName = 'com.whispaste.support_store';

/// StoreKit 2 bridge for the Mac App Store build. Registered only when
/// `kIsMasBuild` is true (see `resolveSupportStoreBridge`).
///
/// Every native failure degrades to the contract's fallback value; nothing
/// here throws to the caller.
class MacStoreKitSupportStoreBridge implements SupportStoreBridge {
  MacStoreKitSupportStoreBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kMacStoreKitChannelName);

  final MethodChannel _channel;

  @override
  Future<bool> isAvailable() => _invokeBool('isAvailable');

  @override
  Future<List<SupportProduct>> loadProducts(List<String> productIds) async {
    final knownIds = [
      for (final id in productIds)
        if (kSupportProductIds.contains(id)) id,
    ];
    if (knownIds.isEmpty) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('loadProducts', {
        'ids': knownIds,
      });
      return parseStoreKitProducts(raw, knownIds);
    } on PlatformException catch (error) {
      _log.warning('loadProducts failed: ${error.code}', error);
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<SupportPurchaseStatus> purchase(String productId) async {
    if (!kSupportProductIds.contains(productId)) {
      return SupportPurchaseStatus.unavailable;
    }
    try {
      final raw = await _channel.invokeMethod<String>('purchase', {
        'id': productId,
      });
      return parseStoreKitPurchaseStatus(raw);
    } on PlatformException catch (error) {
      _log.warning('purchase failed: ${error.code}', error);
      return SupportPurchaseStatus.serverError;
    } on MissingPluginException {
      return SupportPurchaseStatus.unavailable;
    }
  }

  @override
  Future<bool> hasVerifiedAppPurchase() =>
      _invokeBool('hasVerifiedAppPurchase');

  @override
  Future<bool> hasVerifiedSupportPurchase() =>
      _invokeBool('hasVerifiedSupportPurchase');

  Future<bool> _invokeBool(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException catch (error) {
      _log.warning('$method failed: ${error.code}', error);
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Maps the native result list to [SupportProduct]s in [requestedIds] order.
///
/// Malformed entries and ids the store did not return are skipped.
/// Visible for testing.
List<SupportProduct> parseStoreKitProducts(
  List<Object?>? raw,
  List<String> requestedIds,
) {
  if (raw == null) return const [];
  final byId = <String, SupportProduct>{};
  for (final entry in raw) {
    if (entry is! Map) continue;
    final id = entry['id'];
    final name = entry['displayName'];
    final price = entry['displayPrice'];
    if (id is! String || name is! String || price is! String) continue;
    byId[id] = SupportProduct(
      productId: id,
      title: name,
      formattedPrice: price,
    );
  }
  return [for (final id in requestedIds) ?byId[id]];
}

/// Maps the native status name to [SupportPurchaseStatus]. Null or unknown
/// names count as [SupportPurchaseStatus.serverError]. Visible for testing.
SupportPurchaseStatus parseStoreKitPurchaseStatus(String? raw) {
  for (final status in SupportPurchaseStatus.values) {
    if (status.name == raw) return status;
  }
  return SupportPurchaseStatus.serverError;
}
