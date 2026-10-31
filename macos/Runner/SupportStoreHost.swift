import Cocoa
import FlutterMacOS
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
/// Sponsoring never unlocks a feature (`internal-notes`).
/// The verified-purchase flag below is a cosmetic supporter badge only.
///
/// Deployment target is macOS 12; `AppTransaction` needs macOS 13 and is
/// guarded with `#available`, so app-purchase verification reports false on
/// macOS 12.
@available(macOS 12.0, *)
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
    guard isMasBuild else { return false }
    guard #available(macOS 13.0, *) else { return false }
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

  // MARK: - Transaction updates

  /// Finishes verified transactions that arrive outside `purchase()` (Ask to
  /// Buy approvals, restores, refunds). Dart re-queries
  /// `hasVerifiedSupportPurchase` when it needs the badge; there is no push.
  private func listenForTransactionUpdates() -> Task<Void, Never> {
    Task.detached { [self] in
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
    }
  }

  private func setVerifiedSupportFlag(_ value: Bool) {
    UserDefaults.standard.set(value, forKey: Self.verifiedSupportFlagKey)
  }
}
