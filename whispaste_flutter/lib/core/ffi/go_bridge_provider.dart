import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'go_bridge_async.dart';

/// Manages the [AsyncGoBridge] lifecycle as a Riverpod 3.x Notifier.
///
/// The bridge isolate is created when the provider is first read and
/// disposed automatically when the provider is no longer watched.
class AsyncGoBridgeNotifier extends Notifier<AsyncGoBridge> {
  @override
  AsyncGoBridge build() {
    final bridge = AsyncGoBridge();
    ref.onDispose(bridge.dispose);
    return bridge;
  }
}

/// Global provider for the isolate-backed Go FFI bridge.
final asyncGoBridgeProvider =
    NotifierProvider<AsyncGoBridgeNotifier, AsyncGoBridge>(
  AsyncGoBridgeNotifier.new,
);
