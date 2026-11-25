import Cocoa
import FlutterMacOS
import Security
import StoreKit

#if MAS_BUILD
private let isMasBuild = true
#else
private let isMasBuild = false
#endif

/// MethodChannel host for sponsoring purchases via StoreKit 2
/// (`com.whispaste.support_store`), consumed by `MacStoreKitSupportStoreBridge`.
///
/// Only the Mac App Store build can sell anything: `isAvailable` is false
/// everywhere else, and the Dart side only registers this bridge for
/// `kIsMasBuild`. The purchase code itself compiles in every configuration
/// so that a debug build type-checks it too.
///
/// Sponsoring never unlocks a feature.
/// The verified-purchase flag below is a cosmetic supporter badge only.
///
/// `AppTransaction` needs macOS 13, which is the app's deployment target.
final class SupportStoreHost {
  /// Consumable ids shared with the Microsoft Store add-ons; see
  /// `lib/services/support/support_store_bridge.dart`.
  private static let supportProductIds: Set<String> = [
    "whispaste.support.once.1",
    "whispaste.support.once.2",
    "whispaste.support.once.3",
    "whispaste.support.once.4",
    "whispaste.support.once.5",
  ]

  /// Fallback for consumables: finished consumable transactions may not show
  /// up in `Transaction.all`, so a successful purchase is also recorded here.
  /// Cleared when a support transaction is revoked (refund).
  private static let verifiedSupportFlagKey = "whispaste.support.verifiedPurchaseFlag"

  private let channel: FlutterMethodChannel
  private var products: [String: Product] = [:]
  private var transactionUpdates: Task<Void, Never>?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.support_store",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
    if isMasBuild {
      transactionUpdates = listenForTransactionUpdates()
    }
  }

  deinit {
    transactionUpdates?.cancel()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]

    switch call.method {
    case "isAvailable":
      result(isMasBuild && AppStore.canMakePayments)

    case "loadProducts":
      guard let ids = args?["ids"] as? [String] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'ids'", details: nil))
        return
      }
      Task { @MainActor in
        do {
          let payload = try await self.loadProducts(ids: ids)
          result(payload)
        } catch {
          result(FlutterError(code: "LOAD_FAILED", message: error.localizedDescription, details: nil))
        }
      }

    case "purchase":
      guard let id = args?["id"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'id'", details: nil))
        return
      }
      Task { @MainActor in
        let status = await self.purchase(id: id)
        result(status)
      }

    case "isTestEnvironment":
      DispatchQueue.global(qos: .userInitiated).async {
        let test = Self.signatureCheck() == .notStoreSigned
        DispatchQueue.main.async { result(isMasBuild && test) }
      }

    case "hasVerifiedAppPurchase":
      Task { @MainActor in
        let verified = await self.hasVerifiedAppPurchase()
        result(verified)
      }

    case "hasVerifiedSupportPurchase":
      Task { @MainActor in
        let verified = await self.hasVerifiedSupportPurchase()
        result(verified)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Catalogue

  private func loadProducts(ids: [String]) async throws -> [[String: String]] {
    guard isMasBuild, !ids.isEmpty else { return [] }
    let fetched = try await Product.products(for: ids)
    for product in fetched {
      products[product.id] = product
    }
    // Keep the caller's order and skip ids the store does not know.
    return ids.compactMap { id in
      guard let product = fetched.first(where: { $0.id == id }) else { return nil }
      return [
        "id": product.id,
        "displayName": product.displayName,
        "displayPrice": product.displayPrice,
      ]
    }
  }

  // MARK: - Purchase

  /// Returns the Dart `SupportPurchaseStatus` name.
  private func purchase(id: String) async -> String {
    guard isMasBuild else { return "unavailable" }
    do {
      let product: Product
      if let cached = products[id] {
        product = cached
      } else {
        guard let fetched = try await Product.products(for: [id]).first else {
          return "unavailable"
        }
        products[id] = fetched
        product = fetched
      }

      let outcome = try await product.purchase()
      switch outcome {
      case .success(let verification):
        guard case .verified(let transaction) = verification else {
          // Unverified: grant nothing and leave the transaction unfinished.
          return "serverError"
        }
        await transaction.finish()
        if Self.supportProductIds.contains(transaction.productID) {
          setVerifiedSupportFlag(true)
        }
        return "succeeded"
      case .userCancelled:
        return "cancelled"
      case .pending:
        return "pending"
      @unknown default:
        return "serverError"
      }
    } catch let error as StoreKitError {
      switch error {
      case .networkError:
        return "networkError"
      case .notAvailableInStorefront, .notEntitled:
        return "unavailable"
      default:
        return "serverError"
      }
    } catch {
      return "serverError"
    }
  }

  // MARK: - Verification

  private func hasVerifiedAppPurchase() async -> Bool {
    // A local preview or Xcode run gets a sandbox AppTransaction; that is no
    // purchase of the app and earns no supporter status.
    guard isMasBuild, Self.signatureCheck() == .storeSigned else { return false }
    do {
      switch try await AppTransaction.shared {
      case .verified:
        return true
      case .unverified:
        return false
      }
    } catch {
      return false
    }
  }

  private func hasVerifiedSupportPurchase() async -> Bool {
    guard isMasBuild else { return false }
    for await entitlement in Transaction.all {
      guard case .verified(let transaction) = entitlement else { continue }
      if Self.supportProductIds.contains(transaction.productID), transaction.revocationDate == nil {
        return true
      }
    }
    return UserDefaults.standard.bool(forKey: Self.verifiedSupportFlagKey)
  }

  // MARK: - Store environment

  enum SignatureCheck { case storeSigned, notStoreSigned, unknown }

  /// Leaf certificate extension that only Apple's Mac App Store distribution
  /// signature carries. A local preview (Developer ID) or an Xcode run lacks
  /// it; StoreKit then talks to the sandbox, whose storefront and currency
  /// follow the sandbox account, not the user's App Store country (#2202).
  private static let masRequirement =
    "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9]"

  private static let cachedSignatureCheck: SignatureCheck = {
    var code: SecCode?
    guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
      return .unknown
    }
    var requirement: SecRequirement?
    guard
      SecRequirementCreateWithString(masRequirement as CFString, SecCSFlags(), &requirement)
        == errSecSuccess,
      let requirement
    else { return .unknown }
    switch SecCodeCheckValidity(code, SecCSFlags(), requirement) {
    case errSecSuccess:
      return .storeSigned
    case errSecCSReqFailed:
      return .notStoreSigned
    default:
      // Any other failure says nothing about the store; never claim a test
      // environment on a real store build because of it.
      return .unknown
    }
  }()

  /// Whether Apple signed this process for the Mac App Store. Computed once.
  static func signatureCheck() -> SignatureCheck { cachedSignatureCheck }

  // MARK: - Transaction updates

  /// Finishes verified transactions that arrive outside `purchase()` (Ask to
  /// Buy approvals, interrupted purchases, refunds), so no consumable stays
  /// unfinished. Started at app launch (`AppDelegate`). A confirmed support
  /// purchase is pushed to Dart as `purchaseConfirmed`.
  private func listenForTransactionUpdates() -> Task<Void, Never> {
    // Transactions left unfinished by an earlier run (crash, quit during the
    // purchase) are finished too, so a consumable never stays stuck. Runs
    // beside the updates listener, which must start at launch without delay.
    Task.detached { [self] in
      for await unfinished in Transaction.unfinished {
        await self.handleTransactionUpdate(unfinished)
      }
    }
    return Task.detached { [self] in
      for await update in Transaction.updates {
        await self.handleTransactionUpdate(update)
      }
    }
  }

  private func handleTransactionUpdate(_ update: VerificationResult<Transaction>) async {
    guard case .verified(let transaction) = update else { return }
    await transaction.finish()
    guard Self.supportProductIds.contains(transaction.productID) else { return }
    if transaction.revocationDate != nil {
      setVerifiedSupportFlag(false)
    } else {
      setVerifiedSupportFlag(true)
      // Tells Dart that a pending purchase (Ask to Buy) went through. No
      // payload: amount, price and receipt never leave this host.
      await MainActor.run { self.channel.invokeMethod("purchaseConfirmed", arguments: nil) }
    }
  }

  private func setVerifiedSupportFlag(_ value: Bool) {
    UserDefaults.standard.set(value, forKey: Self.verifiedSupportFlagKey)
  }
}

/// MethodChannel host for the system rating dialog (`com.whispaste.review`).
/// Used by the Mac App Store build instead of an own rating card (guideline
/// 5.6.1); StoreKit limits it to three requests per 365 days.
final class ReviewHost {
  init(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.whispaste.review",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "requestReview" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        SKStoreReviewController.requestReview()
        result(nil)
      }
    }
  }
}
