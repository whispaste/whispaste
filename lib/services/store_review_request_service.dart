/// Native Microsoft Store and Mac App Store rating request.
///
/// Calls the `com.whispaste.store_review` channel: `StoreHost` on macOS
/// (`SKStoreReviewController`) and `StoreReviewChannel` on Windows
/// (`StoreContext.RequestRateAndReviewAppAsync`). The OS decides whether a
/// sheet is shown and may not report it back, so a [NativeReviewOutcome.requested]
/// means the request was made, not that anything was displayed.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';

const String kStoreReviewChannelName = 'com.whispaste.store_review';

final _log = AppLogger('StoreReviewRequest');

/// What a native rating request led to. Only [requested] counts as a request
/// for the prompt cooldown.
enum NativeReviewOutcome {
  /// The OS rating request was made, or the Store dialog was shown or closed.
  requested,

  /// The channel is absent, or the process is not Store-installed. Nothing was
  /// asked, so the prompt stays due.
  unavailable,

  /// The Store could not show the request (network, server, or an exception).
  failed,
}

/// Makes one native rating request. Never throws.
Future<NativeReviewOutcome> requestNativeStoreReview({
  MethodChannel channel = const MethodChannel(kStoreReviewChannelName),
}) async {
  try {
    final status = await channel.invokeMethod<String>('requestReview');
    return switch (status) {
      'requested' || 'succeeded' || 'canceled' => NativeReviewOutcome.requested,
      'unavailable' => NativeReviewOutcome.unavailable,
      _ => NativeReviewOutcome.failed,
    };
  } on MissingPluginException {
    return NativeReviewOutcome.unavailable;
  } on PlatformException catch (e) {
    _log.error('native review request failed: ${e.code}', e);
    return NativeReviewOutcome.failed;
  }
}

/// Seam for the watcher: tests replace this with a fake.
final nativeStoreReviewRequestProvider =
    Provider<Future<NativeReviewOutcome> Function()>(
      (ref) => requestNativeStoreReview,
    );
