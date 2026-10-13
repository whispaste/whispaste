/// Native store purchases for sponsoring (Microsoft Store add-ons on
/// Windows, StoreKit consumables on the Mac App Store).
///
/// Sponsoring never unlocks a feature: a verified purchase only earns the
/// cosmetic supporter badge and silences the automatic support prompt
/// (`.scratch/support-donations/PRD.md`, decisions 2026-10-07 and S4).
/// Every implementation is client-side only; there is no server receipt
/// check because nothing is entitled.
library;

/// Product ids shared by the Microsoft Store (InAppOfferToken) and App Store
/// Connect, so both stores carry the same catalogue. Ordered from the
/// smallest to the largest amount; [kDefaultSupportProductId] is preselected.
const List<String> kSupportProductIds = [
  'whispaste.support.once.1',
  'whispaste.support.once.2',
  'whispaste.support.once.3',
  'whispaste.support.once.4',
  'whispaste.support.once.5',
];

const String kDefaultSupportProductId = 'whispaste.support.once.2';

/// A consumable as the store presents it. [formattedPrice] is localized by
/// the store and must be shown verbatim, never recomputed.
class SupportProduct {
  const SupportProduct({
    required this.productId,
    required this.title,
    required this.formattedPrice,
  });

  final String productId;
  final String title;
  final String formattedPrice;
}

enum SupportPurchaseStatus {
  /// The store confirmed the payment.
  succeeded,

  /// The user closed the store's purchase dialog. Not an error.
  cancelled,

  /// Awaiting confirmation (e.g. Ask to Buy); resolved later via
  /// [SupportStoreBridge.hasVerifiedSupportPurchase].
  pending,
  networkError,
  serverError,

  /// No store context (unpackaged build, sideload, catalogue missing).
  unavailable,
}

/// One per platform; [UnavailableSupportStoreBridge] everywhere else.
abstract interface class SupportStoreBridge {
  /// Whether native purchases can be offered at all in this process.
  Future<bool> isAvailable();

  /// Products for [productIds] that the store knows, in the given order.
  /// Missing ids are skipped; an empty list means "fall back".
  Future<List<SupportProduct>> loadProducts(List<String> productIds);

  /// Starts the store's own purchase UI for [productId].
  Future<SupportPurchaseStatus> purchase(String productId);

  /// Whether this installation holds a verified, non-trial license of the
  /// paid app itself (decision S4: buying the app counts as support).
  Future<bool> hasVerifiedAppPurchase();

  /// Whether any support consumable was ever bought and not refunded, so
  /// the badge can be restored after a reinstall.
  Future<bool> hasVerifiedSupportPurchase();
}

class UnavailableSupportStoreBridge implements SupportStoreBridge {
  const UnavailableSupportStoreBridge();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<SupportProduct>> loadProducts(List<String> productIds) async =>
      const [];

  @override
  Future<SupportPurchaseStatus> purchase(String productId) async =>
      SupportPurchaseStatus.unavailable;

  @override
  Future<bool> hasVerifiedAppPurchase() async => false;

  @override
  Future<bool> hasVerifiedSupportPurchase() async => false;
}
