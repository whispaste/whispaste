import Cocoa
import FlutterMacOS
import StoreKit

/// MethodChannel host for the native App Store rating request
/// (`com.whispaste.store_review`), consumed by `MacStoreReviewRequest`.
///
/// Only the Mac App Store build calls this. StoreKit shows the rating sheet
/// at its own discretion (at most three times per 365 days, never after a
/// button tap) and gives no callback whether it was displayed, so the Dart
/// side counts requests, not displays.
final class StoreReviewHost {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.store_review",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestReview":
      SKStoreReviewController.requestReview()
      result("requested")
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
