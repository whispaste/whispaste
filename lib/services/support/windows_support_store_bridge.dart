import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import 'support_store_bridge.dart';

final _log = AppLogger('SupportStoreBridge');

/// Microsoft Store implementation of [SupportStoreBridge], backed by the
/// native method channel in `windows/runner/support_store_channel.cpp`.
///
/// Only parses channel payloads and maps them to the typed contract. Every
/// failure degrades to the neutral answer (`false`, empty list, or
/// [SupportPurchaseStatus.unavailable] / `serverError`) so a broken Store
/// never breaks the sponsoring sheet.
///
/// Consumables have no license history, so the "verified support purchase"
/// answer comes from a local flag set on a succeeded purchase. A reinstall
/// cannot restore it from the Store; this is a known limitation.
class WindowsSupportStoreBridge implements SupportStoreBridge {
  const WindowsSupportStoreBridge({this.channel = _defaultChannel});

  static const _defaultChannel = MethodChannel('com.whispaste.support_store');

  /// SharedPreferences key set once a purchase reports `succeeded`.
  static const verifiedSupportPurchaseKey = 'support_store_verified_purchase';

  /// The native channel; injectable so tests can mock it.
  final MethodChannel channel;

  @override
  Future<bool> isAvailable() async {
    try {
      return await channel.invokeMethod<bool>('isAvailable') ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<List<SupportProduct>> loadProducts(List<String> productIds) async {
    final known = productIds.where(kSupportProductIds.contains).toList();
    if (known.isEmpty) return const [];
    try {
      final raw = await channel.invokeListMethod<Object?>('loadProducts', {
        'productIds': known,
      });
      final requested = known.toSet();
      return [
        for (final entry in raw ?? const <Object?>[])
          ?_parseProduct(entry, requested),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<SupportPurchaseStatus> purchase(String productId) async {
    if (!kSupportProductIds.contains(productId)) {
      return SupportPurchaseStatus.unavailable;
    }
    final status = await _requestPurchase(productId);
    if (status == SupportPurchaseStatus.succeeded) {
      await _markVerifiedSupportPurchase();
    }
    return status;
  }

  Future<SupportPurchaseStatus> _requestPurchase(String productId) async {
    try {
      final raw = await channel.invokeMethod<String>('purchase', {
        'productId': productId,
      });
      return _parseStatus(raw);
    } on PlatformException catch (error) {
      return error.code == 'store_unavailable'
          ? SupportPurchaseStatus.unavailable
          : SupportPurchaseStatus.serverError;
    } on MissingPluginException {
      return SupportPurchaseStatus.unavailable;
    } on Object {
      return SupportPurchaseStatus.serverError;
    }
  }

  @override
  Future<bool> hasVerifiedAppPurchase() async {
    try {
      return await channel.invokeMethod<bool>('hasVerifiedAppPurchase') ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> hasVerifiedSupportPurchase() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(verifiedSupportPurchaseKey) ?? false;
    } on Object {
      return false;
    }
  }

  Future<void> _markVerifiedSupportPurchase() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(verifiedSupportPurchaseKey, true);
    } on Object catch (error) {
      // The purchase itself succeeded; losing the badge flag is the only cost.
      _log.error('could not persist verified support purchase', error);
    }
  }

  static SupportProduct? _parseProduct(Object? entry, Set<String> requested) {
    if (entry case {
      'productId': final String productId,
      'title': final String title,
      'formattedPrice': final String formattedPrice,
    }) {
      if (!requested.contains(productId) || formattedPrice.isEmpty) {
        return null;
      }
      return SupportProduct(
        productId: productId,
        title: title,
        formattedPrice: formattedPrice,
      );
    }
    return null;
  }

  static SupportPurchaseStatus _parseStatus(String? raw) =>
      SupportPurchaseStatus.values.asNameMap()[raw] ??
      SupportPurchaseStatus.serverError;
}
